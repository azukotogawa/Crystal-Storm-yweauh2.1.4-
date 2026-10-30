extends SceneTree

const _ItemTypes = preload("res://helpers/item_types.gd")
const _ItemAnim = preload("res://systems/item_anim.gd")
const _GameFeelConfig = preload("res://config/game_feel_config.gd")
const _Cast = preload("res://player/tool_feel_cast.gd")
const _Gate = preload("res://player/action_resolve_gate.gd")
const _Ranged = preload("res://weapons/ranged_aim.gd")
const _Weapons = preload("res://weapons/weapon_controller.gd")

const DT := 1.0 / 60.0
const DOC := "res://docs/combat/hit-timing-frames.md"

const WEAPONS: Array[String] = [
	"wooden_sword",
	"spear",
	"crystal_hammer",
	"stone_pick",
	"shortbow",
	"sling",
]

var _failed := 0
var _heard: Array[String] = []


func _fail(msg: String) -> void:
	_failed += 1
	print("FAIL " + msg)


func _init() -> void:
	call_deferred("_run")


func _steps(sec: float) -> int:
	var left := sec
	var n := 0
	while left > 0.000000001 and n < 10000:
		n += 1
		left = maxf(left - DT, 0.0)
	return n


func _clock_window(item_id: String) -> Dictionary:
	var pb := _ItemAnim.playback_for(item_id)
	var step := 0
	var fire := 0
	var fin := 0
	while fin == 0 and step < 5000:
		step += 1
		if pb.advance(DT) and fire == 0:
			fire = step
		if pb.finished():
			fin = step
	return {"wind": fire - 1, "active": 1, "recovery": fin - fire, "fire": fire}


func _draw_window(item_id: String) -> Dictionary:
	var draw_sec := float(_GameFeelConfig.active().draw_sec)
	var release := 1
	var held := 0.0
	while release < 5000:
		release += 1
		held += DT
		if held + 0.000000001 >= draw_sec:
			break
	var pb := _ItemAnim.playback_for(item_id)
	var step := 0
	var fire_step := 0
	var fin_step := 0
	while fin_step == 0 and step < 5000:
		step += 1
		if pb.advance(DT) and fire_step == 0:
			fire_step = step
		if pb.finished():
			fin_step = step
	var fire_frame := release + fire_step - 1
	return {
		"wind": fire_frame - 1,
		"active": 1,
		"recovery": fin_step - fire_step,
		"fire": fire_frame,
		"charge": _Ranged.charge_of(held),
	}


func _on_hook(cue_id: String) -> void:
	_heard.append(cue_id)


func _feel_window(host: Host, action_id: String) -> Dictionary:
	_Gate.reset()
	_heard.clear()
	host.resolved = 0
	var cast := _Cast.new()
	if not cast.try_begin(host, action_id):
		_fail("%s did not start" % action_id)
		return {"wind": -1, "recovery": -1}
	var frame := 0
	while host.resolved == 0 and frame < 4000:
		frame += 1
		cast.advance(host, DT)
	var rec := 0
	while cast.pacing_blocks() and rec < 4000:
		rec += 1
		cast.advance(host, DT)
	return {"wind": frame - 1, "recovery": rec, "frame": frame}


func _row(action_id: String) -> Dictionary:
	return _GameFeelConfig.active().action(action_id)


func _measure() -> Dictionary:
	var out := {}
	var sword_clock := _clock_window("wooden_sword")
	var sword_row := _row("sword_swing")
	out["wooden_sword"] = {
		"wind": sword_clock["wind"],
		"active": _steps(float(sword_row["hit_stop_sec"])),
		"recovery": _steps(float(sword_row["recovery_sec"])),
	}
	var spear := _clock_window("spear")
	out["spear"] = {"wind": spear["wind"], "active": 1, "recovery": spear["recovery"]}
	var hammer := _clock_window("crystal_hammer")
	out["crystal_hammer"] = {"wind": hammer["wind"], "active": 1, "recovery": hammer["recovery"]}
	var pick_row := _row("multi_block_break")
	out["stone_pick"] = {
		"wind": _steps(float(pick_row["telegraph_sec"])) - 1,
		"active": _steps(float(pick_row["hit_stop_sec"])),
		"recovery": _steps(float(pick_row["recovery_sec"])),
	}
	var bow := _draw_window("shortbow")
	out["shortbow"] = {"wind": bow["wind"], "active": 1, "recovery": bow["recovery"]}
	var sling := _draw_window("sling")
	out["sling"] = {"wind": sling["wind"], "active": 1, "recovery": sling["recovery"]}
	return out


func _table() -> Dictionary:
	var text := FileAccess.get_file_as_string(DOC)
	var out := {}
	if text.is_empty():
		_fail("hit timing doc is missing")
		return out
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if not line.begins_with("|"):
			continue
		var parts := line.split("|")
		if parts.size() < 5:
			continue
		var id := parts[1].strip_edges()
		if not WEAPONS.has(id):
			continue
		out[id] = {
			"wind": int(parts[2].strip_edges()),
			"active": int(parts[3].strip_edges()),
			"recovery": int(parts[4].strip_edges()),
		}
	return out


func _run() -> void:
	var live := root.get_node_or_null("GameFeel")
	if live == null or not live.has_signal("sound_hook"):
		_fail("GameFeel autoload is missing")
	else:
		live.sound_hook.connect(_on_hook)
	var host := Host.new()
	root.add_child(host)
	var weapons := _Weapons.new()
	_assert_routes(weapons)
	_assert_hammer(weapons)
	_assert_feel_cast(host)
	var measured := _measure()
	var table := _table()
	for id in WEAPONS:
		if not table.has(id):
			_fail("doc is missing %s" % id)
			continue
		var got: Dictionary = measured[id]
		var row: Dictionary = table[id]
		print("%s wind %d active %d recovery %d" % [id, int(got["wind"]), int(got["active"]), int(got["recovery"])])
		if int(got["wind"]) != int(row["wind"]) or int(got["active"]) != int(row["active"]) or int(got["recovery"]) != int(row["recovery"]):
			_fail("%s doc %d/%d/%d does not match the clocks %d/%d/%d" % [id, int(row["wind"]), int(row["active"]), int(row["recovery"]), int(got["wind"]), int(got["active"]), int(got["recovery"])])
		_assert_active_matches_config(id, int(got["active"]))
	host.queue_free()
	weapons.free()
	if _failed == 0:
		print("All hit timing frame tests OK")
		quit(0)
	else:
		quit(1)


func _assert_active_matches_config(id: String, active: int) -> void:
	var feel_id := ""
	if id == "wooden_sword":
		feel_id = "sword_swing"
	elif id == "stone_pick":
		feel_id = "multi_block_break"
	if feel_id == "":
		if active != 1:
			_fail("%s active window is %d frames, the clock connects on one frame" % [id, active])
		return
	var expect := _steps(float(_row(feel_id)["hit_stop_sec"]))
	if active != expect:
		_fail("%s active-frame window %d does not match %s hit-stop %d" % [id, active, feel_id, expect])


func _assert_routes(weapons) -> void:
	if weapons._configured_attack_id("wooden_sword", _ItemTypes.get_def("wooden_sword")) != "sword_swing":
		_fail("sword does not use sword_swing")
	if weapons._configured_attack_id("shortbow", _ItemTypes.get_def("shortbow")) != "bow_shot":
		_fail("bow id is not bow_shot")
	for id in ["spear", "crystal_hammer", "sling", "stone_pick"]:
		if weapons._configured_attack_id(id, _ItemTypes.get_def(id)) != "":
			_fail("%s was routed onto a feel swing" % id)
	weapons._feel_item = "wooden_sword"
	var impact := float(weapons.tool_feel_impact_sec("sword_swing"))
	var spec := float(_ItemAnim.spec_for("wooden_sword").get("impact_time", -1.0))
	if not is_equal_approx(impact, spec):
		_fail("sword wind-up is not the impact sample")
	var telegraph := float(_row("sword_swing")["telegraph_sec"])
	if is_equal_approx(impact, telegraph):
		_fail("sword impact and the sword_swing telegraph are the same, so the override is invisible")
	weapons._feel_item = "stone_pick"
	if weapons.tool_feel_impact_sec("multi_block_break") >= 0.0:
		_fail("pick wind-up was replaced and no longer uses multi_block_break")
	var src := FileAccess.get_file_as_string("res://weapons/weapon_controller.gd")
	var draw_at := src.find("if not _begin_draw()")
	if draw_at < 0 or src.substr(draw_at, 220).find("_try_attack()") < 0:
		_fail("a ranged press no longer draws before the attack")


func _assert_hammer(weapons) -> void:
	var def := _ItemTypes.get_def("crystal_hammer")
	if not is_equal_approx(float(def.get("anim_duration", 0.0)), 1.1):
		_fail("hammer duration moved off 1.1 s")
	if not is_equal_approx(float(def.get("impact_ratio", 0.0)), 0.62):
		_fail("hammer pre-hit ratio moved off 0.62")
	var impact := float(_ItemAnim.spec_for("crystal_hammer").get("impact_time", -1.0))
	if not is_equal_approx(impact, 1.1 * 0.62):
		_fail("hammer pre-hit delay is not 1.1 * 0.62")
	var clock := _clock_window("crystal_hammer")
	if int(clock["fire"]) != _steps(impact):
		_fail("hammer hit frame %d is not the 0.682 s sample" % int(clock["fire"]))
	if weapons._configured_attack_id("crystal_hammer", def) != "":
		_fail("hammer pre-hit now waits on a feel telegraph")


func _assert_feel_cast(host: Host) -> void:
	host.impact = float(_ItemAnim.spec_for("wooden_sword").get("impact_time", -1.0))
	var sword := _feel_window(host, "sword_swing")
	if int(sword["wind"]) != _steps(host.impact) - 1:
		_fail("sword feel wind %d is not the impact sample" % int(sword["wind"]))
	if int(sword["wind"]) == _steps(float(_row("sword_swing")["telegraph_sec"])) - 1:
		_fail("sword feel wind used the telegraph instead of the impact sample")
	if int(sword["recovery"]) != _steps(float(_row("sword_swing")["recovery_sec"])):
		_fail("sword feel recovery does not match sword_swing")
	if _heard.is_empty() or str(_heard[0]) != "sword_swing":
		_fail("sword hit did not play sword_swing")
	host.impact = -1.0
	var pick := _feel_window(host, "multi_block_break")
	if int(pick["wind"]) != _steps(float(_row("multi_block_break")["telegraph_sec"])) - 1:
		_fail("pick feel wind does not match multi_block_break")
	if int(pick["recovery"]) != _steps(float(_row("multi_block_break")["recovery_sec"])):
		_fail("pick feel recovery does not match multi_block_break")
	if _heard.is_empty() or str(_heard[0]) != "multi_block_break":
		_fail("pick hit did not play multi_block_break")


class Host extends Node:
	var impact := -1.0
	var resolved := 0

	func tool_feel_impact_sec(_action_id: String) -> float:
		return impact

	func resolve_tool_feel(_action_id: String) -> bool:
		resolved += 1
		return true


