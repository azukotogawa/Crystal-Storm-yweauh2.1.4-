extends RefCounted

const _Build = preload("res://scripts/honest_bot/honest_build.gd")
const _Hands = preload("res://scripts/honest_bot/honest_input.gd")
const _Bot = preload("res://scripts/honest_bot/honest_play_bot.gd")
const _Combat = preload("res://scripts/honest_bot/honest_combat.gd")
const _Fight = preload("res://scripts/honest_bot/honest_fight.gd")
const _Cast = preload("res://scripts/honest_bot/honest_skill_cast.gd")
const _Hazard = preload("res://scripts/honest_bot/honest_hazard.gd")
const _Nav = preload("res://scripts/honest_bot/honest_nav.gd")
const _Pace = preload("res://scripts/honest_bot/honest_pace.gd")
const _Move = preload("res://entities/entity_navigation.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _GI = preload("res://helpers/gameplay_input.gd")
const _Worlds = preload("res://systems/world_manager.gd")
const _Edits = preload("res://world/terrain_edits.gd")
const _Features = preload("res://world/feature_registry.gd")
const _Corrupt = preload("res://crystal/crystal_corruption.gd")
const _RelicChoice = preload("res://relics/relic_choice.gd")
const _RelicPanel = preload("res://ui/relic_choice_panel.gd")

const MAIN_SCENE := "res://scenes/main.tscn"
const SEED := 12349
const STEP := 1.0 / 60.0
const BOOT_FRAMES := 2400
const DIG_FRAMES := 4200
const BUILD_FRAMES := 7200
const MULTI_FRAMES := 7200

const OPENING_BANNER := "Watch the purple front — dig trenches & walls where it advances"
const WALL_BANNER := "Wall raised — crystal slows here; it will find another way"

var _off_film: int = 0
var _film_bound: Dictionary = {}
var _film_tree: SceneTree
var _combat_tree: SceneTree
var _combat_player: Node
var _combat_job: Dictionary = {}


func play(tree: SceneTree, scenario: String) -> int:
	var name := scenario.strip_edges()
	if name == "break":
		return _break(tree)
	if name == "crystals" or name == "corruption" or name == "combat":
		return await _play_feature(tree, name)
	if name == "mite_fight":
		return await _play_mite(tree)
	if name == "relic_esc":
		return await _play_relic(tree)
	var multi := name == "multi_dig" or name == "multi_build" or name == "mouse_build" or name == "water_dig" or name == "dev_keys" or name == "water_trench" or name == "swim" or name == "camera" or name == "hotbar" or name == "controls_tour"
	_film_tree = tree
	if name != "dig" and name != "build" and not multi:
		print("FAIL harness unknown scenario %s" % name)
		return 1
	print("HARNESS seed %d" % SEED)
	print("HARNESS setup pending_launch harness-%s seed %d resume off" % [name, SEED])
	var seen: PackedStringArray = PackedStringArray()
	var player = await _boot(tree, name, seen)
	if player == null:
		return 1
	var bot = _Bot.new()
	bot.chapter = name
	bot.objective = _objective(name)
	var before := _snap(tree, player)
	var build = _Build.new()
	var hands = _Hands.new()
	build.reset(_segment(name))
	var cap := DIG_FRAMES if name == "dig" else BUILD_FRAMES
	if multi:
		cap = MULTI_FRAMES
	var result := ""
	var frames := 0
	while frames < cap:
		var delta := _delta(tree)
		result = build.tick(delta, tree, player, hands, null)
		_note_banner(tree, seen)
		if result == "fail":
			return _give_up(bot, player, "play returned fail")
		if (name == "dig" or multi) and result == "pass":
			break
		if name == "build" and build.beat >= 10:
			result = "pass"
			break
		await tree.process_frame
		frames += 1
	if result != "pass":
		return _give_up(bot, player, "scenario did not finish")
	var after := _snap(tree, player)
	_stamp_world(name, build, after)
	var reason := _expect(name, before, after, seen)
	if reason != "":
		print("FAIL harness assertion %s" % reason)
		return _give_up(bot, player, "assertion %s" % reason)
	_print_see(name, before, after, seen)
	var pos := _xz(player)
	var shot := bot.save_view(name, pos)
	if shot == "":
		return _give_up(bot, player, "screenshot was not saved")
	return 0


func _objective(name: String) -> String:
	if name == "multi_dig":
		return "dig several blocks in one stroke"
	if name == "multi_build" or name == "mouse_build":
		return "place several blocks in one stroke"
	if name == "water_dig":
		return "dig beside a lake and watch it flow"
	if name == "swim":
		return "walk into a lake, swim across and climb out"
	if name == "water_trench":
		return "dig a trench from a lake, then wall it off"
	if name == "controls_tour":
		return "tour every control: camera, hotbar, skill, rotate, chat"
	if name == "hotbar":
		return "pick slots with 3, 0 and the wheel, wrapping both ways"
	if name == "camera":
		return "snap the view with E, look around with Alt, zoom and reset with Home"
	if name == "dev_keys":
		return "press T and Shift+T and leave the terrain alone"
	return "dig one column" if name == "dig" else "place one stone wall"


func _segment(name: String) -> String:
	if name == "multi_dig" or name == "multi_build" or name == "mouse_build" or name == "water_dig" or name == "dev_keys" or name == "water_trench" or name == "swim" or name == "camera" or name == "hotbar" or name == "controls_tour":
		return name
	return "dig_tool" if name == "dig" else "structure_place"


func _play_relic(tree: SceneTree) -> int:
	var seeds := _mite_seeds()
	var held := 0
	var bot = _Bot.new()
	bot.chapter = "relic_esc"
	bot.objective = "keep the relic panel up when Esc is pressed"
	var last_pos := Vector2.ZERO
	for seed_value in seeds:
		var row: Dictionary = await _relic_attempt(tree, int(seed_value))
		var pause_closed := bool(row.get("pause_closed", false))
		var panel_held := bool(row.get("panel_held", false))
		var picked := bool(row.get("picked", false))
		print("HARNESS relic seed %d pause_closed %s panel_held %s picked %s" % [
			int(seed_value),
			"yes" if pause_closed else "no",
			"yes" if panel_held else "no",
			"yes" if picked else "no",
		])
		if not bool(row.get("ok", false)):
			var why := str(row.get("why", "relic esc failed"))
			print("FAIL harness assertion %s" % why)
			var at: Vector2 = row.get("pos", Vector2.ZERO)
			bot.home = at
			bot.fail_closed(at, why)
			return 1
		held += 1
		last_pos = row.get("pos", last_pos)
	print("HARNESS relic %d/%d pause_closed %d/%d panel_held" % [held, seeds.size(), held, seeds.size()])
	var shot := bot.save_view("relic_esc", last_pos)
	if shot == "":
		print("FAIL harness assertion screenshot was not saved")
		bot.fail_closed(last_pos, "screenshot was not saved")
		return 1
	return 0


func _relic_attempt(tree: SceneTree, seed_value: int) -> Dictionary:
	print("HARNESS seed %d" % seed_value)
	print("HARNESS setup pending_launch harness-relic_esc seed %d resume off" % seed_value)
	var seen: PackedStringArray = PackedStringArray()
	var player = await _boot(tree, "relic_esc", seen, seed_value)
	if player == null:
		return {"ok": false, "why": "boot failed"}
	var relic_mgr = player.get_node_or_null("RelicManager")
	var pos := _xz(player)
	if relic_mgr == null:
		await _drop_game(tree, player)
		return {"ok": false, "why": "no relic manager", "pos": pos}
	var before := _equipped_count(relic_mgr)
	_RelicChoice.present(tree, relic_mgr, seed_value, "Choose a relic")
	var panel = null
	for _wait in 8:
		await tree.process_frame
		panel = _RelicPanel._open
		if panel != null and is_instance_valid(panel):
			break
	if panel == null or not is_instance_valid(panel):
		pos = _xz(player)
		await _drop_game(tree, player)
		return {"ok": false, "why": "relic panel did not open", "pos": pos}
	var hands = _Hands.new()
	var weapon = player.get_node_or_null("WeaponController")
	var hotbar := -1
	var cool := 0.0
	if weapon != null and weapon.has_method("get_active_hotbar_index"):
		hotbar = int(weapon.get_active_hotbar_index())
		cool = float(weapon.get("_cooldown_timer"))
	var body := player as Node3D
	var origin := body.global_position
	var pause = tree.get_first_node_in_group("pause_menu")
	if not hands.pulse("hotbar_4") or not hands.pulse("attack") or not hands.pulse_key(KEY_ESCAPE):
		pos = _xz(player)
		await _drop_game(tree, player)
		return {"ok": false, "why": "esc input was not sent", "pos": pos}
	hands.set_held(PackedStringArray(["move_forward"]))
	for _step in 45:
		await tree.process_frame
	hands.begin_tick()
	hands.release_all()
	var pause_closed: bool = _pause_stays_closed(tree, pause)
	var still = _RelicPanel._open
	var panel_held: bool = still != null and is_instance_valid(still) and still == panel
	var moved := body.global_position.distance_to(origin)
	var hotbar_same := true
	var cool_same := true
	if weapon != null and weapon.has_method("get_active_hotbar_index"):
		hotbar_same = int(weapon.get_active_hotbar_index()) == hotbar
		cool_same = float(weapon.get("_cooldown_timer")) <= cool + 0.001
	var blocked: bool = _GI.modal_open and _GI.blocks_actions()
	if not pause_closed or not panel_held or not blocked or moved > 0.2 or not hotbar_same or not cool_same:
		var why := "esc leaked pause %s panel %s blocked %s moved %.3f hotbar %s cooldown %s" % [
			"closed" if pause_closed else "open",
			"held" if panel_held else "gone",
			"yes" if blocked else "no",
			moved,
			"same" if hotbar_same else "changed",
			"same" if cool_same else "started",
		]
		pos = _xz(player)
		await _drop_game(tree, player)
		return {
			"ok": false,
			"why": why,
			"pos": pos,
			"pause_closed": pause_closed,
			"panel_held": panel_held,
			"picked": false,
		}
	var picked := false
	for _try in 10:
		if await _click_relic_offer(tree, still, hands, relic_mgr):
			picked = true
			break
		await tree.process_frame
	for _settle in 8:
		await tree.process_frame
		if _RelicPanel._open == null:
			break
	var gone: bool = _RelicPanel._open == null or not is_instance_valid(_RelicPanel._open)
	var pause_after: bool = _pause_stays_closed(tree, pause)
	var kept: bool = _equipped_count(relic_mgr) >= before and _equipped_count(relic_mgr) > 0
	var cleared: bool = not _GI.modal_open and not _GI.blocks_actions()
	pos = _xz(player)
	print("HARNESS see relic_esc seed %d pause %s panel_after %s equipped %d moved %.3f" % [
		seed_value,
		"closed" if pause_after else "open",
		"gone" if gone else "open",
		_equipped_count(relic_mgr),
		moved,
	])
	await _drop_game(tree, player)
	if not picked or not gone or not pause_after or not kept or not cleared:
		return {
			"ok": false,
			"why": "pick leaked pause %s panel %s picked %s equipped %s modal %s" % [
				"closed" if pause_after else "open",
				"gone" if gone else "open",
				"yes" if picked else "no",
				"kept" if kept else "lost",
				"clear" if cleared else "stuck",
			],
			"pos": pos,
			"pause_closed": pause_closed,
			"panel_held": panel_held,
			"picked": picked,
		}
	return {
		"ok": true,
		"why": "",
		"pos": pos,
		"pause_closed": pause_closed and pause_after,
		"panel_held": panel_held,
		"picked": picked,
	}


func _pause_stays_closed(tree: SceneTree, pause) -> bool:
	if tree != null and tree.paused:
		return false
	if pause != null and bool(pause.visible):
		return false
	return not _GI.pause_open


func _equipped_count(relic_mgr) -> int:
	if relic_mgr == null or not ("equipped" in relic_mgr):
		return 0
	var raw = relic_mgr.equipped
	if raw is Array:
		return raw.size()
	return 0


func _offer_button(panel: Node, relic_mgr) -> Button:
	var fallback: Button = null
	for node in panel.find_children("*", "Button", true, false):
		if not node is Button:
			continue
		if str(node.get_meta("relic_role", "")) != "offer":
			continue
		var button := node as Button
		if fallback == null:
			fallback = button
		var relic_id := str(button.get_meta("relic_id", ""))
		if relic_id == "" or _has_relic(relic_mgr, relic_id):
			continue
		return button
	return fallback


func _has_relic(relic_mgr, relic_id: String) -> bool:
	if relic_mgr == null or not ("equipped" in relic_mgr):
		return false
	var raw = relic_mgr.equipped
	if not raw is Array:
		return false
	for old in raw:
		if str(old) == relic_id:
			return true
	return false


func _click_relic_offer(tree: SceneTree, panel: Node, hands, relic_mgr) -> bool:
	if panel == null or not is_instance_valid(panel):
		return false
	var button := _offer_button(panel, relic_mgr)
	if button == null:
		return false
	_place_offer_button(panel, button)
	var rect := button.get_global_rect()
	print("HARNESS relic click rect %.1f,%.1f %.1fx%.1f" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y])
	if rect.size.x < 4.0 or rect.size.y < 4.0:
		return false
	var at := rect.position + rect.size * 0.5
	if not hands.click_at(button, at, true):
		return false
	await tree.process_frame
	if is_instance_valid(button):
		hands.click_at(button, at, false)
	await tree.process_frame
	return _RelicPanel._open == null or not is_instance_valid(_RelicPanel._open)


func _place_offer_button(panel: Node, button: Button) -> void:
	var host := panel as Control
	if host == null:
		return
	var vp := host.get_viewport()
	var size := Vector2(1152, 648)
	if vp != null:
		var seen := vp.get_visible_rect().size
		if seen.x >= 8.0 and seen.y >= 8.0:
			size = seen
	var rect := button.get_global_rect()
	var at := rect.position + rect.size * 0.5
	if rect.size.x >= 4.0 and rect.size.y >= 4.0 and at.x >= 0.0 and at.y >= 0.0 and at.x <= size.x and at.y <= size.y:
		return
	button.set_as_top_level(true)
	button.global_position = Vector2(80, 120)
	button.size = Vector2(280, 48)


func _break(tree: SceneTree) -> int:
	var bot = _Bot.new()
	bot.chapter = "dig"
	bot.objective = "height drop"
	bot.set_target(Vector2(10.0, 0.0))
	var reason := "height drop expected 1 saw 0"
	print("FAIL harness assertion %s" % reason)
	bot.fail_closed(Vector2.ZERO, "assertion %s" % reason)
	if bot.fail_report == "" or bot.fail_shot == "":
		print("FAIL harness report missing")
		return 1
	if tree == null:
		return 1
	return 1


func _boot(tree: SceneTree, scenario: String, seen: PackedStringArray, seed_value: int = -1):
	var use_seed := seed_value if seed_value >= 0 else SEED
	var held_scale := Engine.time_scale
	Engine.time_scale = 0.0
	_Worlds.start_fresh_run(use_seed)
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		Engine.time_scale = held_scale if held_scale > 0.0 else 1.0
		print("FAIL harness no main scene")
		return null
	var game: Node = packed.instantiate()
	tree.root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while frames < BOOT_FRAMES:
		if compose != null and int(compose.stage) >= compose.Stage.INITIAL_STREAM_READY:
			break
		await tree.process_frame
		_note_banner(tree, seen)
		frames += 1
	if compose == null or int(compose.stage) < compose.Stage.INITIAL_STREAM_READY:
		Engine.time_scale = held_scale if held_scale > 0.0 else 1.0
		print("FAIL harness start region not ready")
		return null
	Engine.time_scale = held_scale if held_scale > 0.0 else 1.0
	for _w in 120:
		await tree.process_frame
		_note_banner(tree, seen)
		if not _GI.blocks_actions():
			break
	if _GI.blocks_actions():
		Engine.time_scale = held_scale if held_scale > 0.0 else 1.0
		print("FAIL harness actions still blocked")
		return null
	var player = tree.get_first_node_in_group("player")
	if player == null or not bool(player.get("world_ready")):
		Engine.time_scale = held_scale if held_scale > 0.0 else 1.0
		print("FAIL harness player not world_ready")
		return null
	var world = game.get_node_or_null("World")
	var seeded := int(world.world_seed) if world != null and "world_seed" in world else -1
	if seeded != use_seed:
		Engine.time_scale = held_scale if held_scale > 0.0 else 1.0
		print("FAIL harness seed %d want %d" % [seeded, use_seed])
		return null
	Engine.time_scale = held_scale if held_scale > 0.0 else 1.0
	print("HARNESS booted seed %d" % seeded)
	return player


func _expect(name: String, before: Dictionary, after: Dictionary, seen: PackedStringArray) -> String:
	if not bool(after.get("hp_panel", false)):
		return "hp bar hidden"
	var want_hp := "%d / %d" % [int(round(float(after.get("hp", 0.0)))), int(round(float(after.get("max", 0.0))))]
	if str(after.get("hp_label", "")) != want_hp:
		return "hp label %s want %s" % [str(after.get("hp_label", "")), want_hp]
	if absf(float(after.get("hp", -1.0)) - float(before.get("hp", -2.0))) > 0.01:
		return "hp changed"
	if not _saw(seen, OPENING_BANNER):
		return "opening banner missing"
	if name == "controls_tour":
		var checks: Dictionary = after.get("tour", {})
		var bad: PackedStringArray = []
		for key in checks:
			if not bool(checks[key]):
				bad.append(str(key))
		if checks.size() < 16:
			return "tour ran %d of 16 checks" % checks.size()
		if not bad.is_empty():
			return "controls failed: %s" % ", ".join(bad)
		print("CONTROLS TOUR OK")
		return ""
	if name == "hotbar":
		var h: Dictionary = after.get("cam", {})
		if h.get("hotbar", []) != [2, 9, 0, 9]:
			return "hotbar sequence %s want [2, 9, 0, 9]" % str(h.get("hotbar", []))
		if absf(float(h.zoom1) - float(h.zoom0)) > 0.001:
			return "plain wheel changed zoom"
		return ""
	if name == "camera":
		var c: Dictionary = after.get("cam", {})
		var dy := fposmod(float(c.yaw1) - float(c.yaw0) + 180.0, 360.0) - 180.0
		if dy < 5.0 or dy > 85.0:
			return "held E yaw changed %.1f want a smooth 5..85" % dy
		if absf(float(c.pitch1) - float(c.pitch0)) < 1.0:
			return "Alt look did not change pitch"
		if float(c.zoom1) >= float(c.zoom0):
			return "= did not zoom in"
		if absf(float(c.zoom2) - float(c.zoom0)) > 0.01:
			return "Home did not restore zoom"
		return ""
	if name == "dev_keys":
		if not bool(after.get("t_chat", false)):
			return "plain T did not open dev chat"
		if int(after.get("shift_changes", 1)) != 0 or int(after.get("t_changes", 1)) != 0:
			return "T or Shift+T changed terrain"
		return ""
	if name == "swim":
		if not bool(after.get("swam", false)):
			return "player never swam in the lake"
		if not bool(after.get("climbed_out", false)):
			return "player did not climb out on the far bank"
		return ""
	if name == "water_trench":
		var steps: Array = [0.875, 0.75, 0.625, 0.5, 0.375, 0.25, 0.125, 0.0, 0.0, 0.0]
		var fill: Array = after.get("fill_levels", [])
		if fill != steps:
			return "trench fill %s want %s" % [str(fill), str(steps)]
		var down: Array = after.get("step_levels", [])
		if down.size() != fill.size() or down.slice(0, 7) != fill.slice(0, 7) or float(down[7]) != 0.875 or float(down[8]) != 0.0 or float(down[9]) != 0.0:
			return "down-step did not continue the flow %s" % str(down)
		var wall: Array = after.get("wall_levels", [])
		if wall.size() != fill.size() or wall.slice(0, 3) != fill.slice(0, 3):
			return "lake side levels changed after the wall %s" % str(wall)
		if not bool(after.get("wall_built", false)):
			return "wall was not built across the trench"
		return ""
	if name == "water_dig":
		var levels: Array = after.get("levels", [])
		var want: Array = [0.875, 0.75, 0.625, 0.5, 0.375, 0.25, 0.125, 0.0, 0.0, 0.0]
		if levels != want:
			return "trench levels %s want the 7 cell stepped spread %s" % [str(levels), str(want)]
		if int(after.get("flow_ticks", 0)) < 1:
			return "no flow tick ran"
		return ""
	if name == "multi_dig":
		if int(after.get("columns", 0)) < 3:
			return "multi dig broke %d columns want 3" % int(after.get("columns", 0))
		if int(after.get("stone", 0)) <= int(before.get("stone", 0)):
			return "stone did not increase"
		return ""
	if name == "multi_build" or name == "mouse_build":
		var placed := int(after.get("walls", 0))
		if placed < 3:
			return "multi build placed %d want 3" % placed
		if int(after.get("stone_spent", -1)) != placed:
			return "stone spent %d for %d blocks" % [int(after.get("stone_spent", -1)), placed]
		for line in seen:
			if line == OPENING_BANNER or line == WALL_BANNER:
				continue
			if line.begins_with("Brush: ") or line.begins_with("New brush unlocked") or line.begins_with("Placed ") or line.begins_with("Broke "):
				continue
			if line.begins_with("First steps "):
				continue
			return "unexpected banner %s" % line
		return ""
	if name == "dig":
		if int(after.get("stone", 0)) <= int(before.get("stone", 0)):
			return "stone did not increase"
		if float(after.get("drop", 0.0)) < 0.01:
			return "height drop missing"
		return ""
	if int(after.get("walls", 0)) < 1:
		return "stone wall missing"
	if int(after.get("stone_spent", 0)) < 1:
		return "stone was not spent"
	for line in seen:
		if line == OPENING_BANNER or line == WALL_BANNER:
			continue
		if line.begins_with("Gate ") or line.begins_with("Bridge ") or line.begins_with("Trench "):
			continue
		if line.begins_with("First steps "):
			continue
		return "unexpected banner %s" % line
	return ""


func _print_see(name: String, before: Dictionary, after: Dictionary, seen: PackedStringArray) -> void:
	print("HARNESS see %s drop %.3f walls %d stone %d to %d hp %s banners %s" % [
		name,
		float(after.get("drop", 0.0)),
		int(after.get("walls", 0)),
		int(before.get("stone", 0)),
		int(after.get("stone", 0)),
		str(after.get("hp_label", "")),
		"|".join(seen),
	])


func _snap(tree: SceneTree, player) -> Dictionary:
	var hp := float(player.health) if "health" in player else -1.0
	var mx := float(player.max_health) if "max_health" in player else 100.0
	var stone := 0
	var inv = player.get("inventory")
	if inv != null and inv.has_method("count_item"):
		stone = int(inv.count_item("stone"))
	var label := ""
	var panel_on := false
	var panel = tree.root.find_child("PlayerHealthBar", true, false)
	if panel != null:
		panel_on = panel.visible
		label = _label_under(panel)
	return {
		"hp": hp,
		"max": mx,
		"hp_label": label,
		"hp_panel": panel_on,
		"stone": stone,
		"drop": 0.0,
		"walls": 0,
	}


func _stamp_world(name: String, build, after: Dictionary) -> void:
	if name == "swim":
		after["swam"] = build.swam
		after["climbed_out"] = build.climbed_out
		print("HARNESS swim swam %s climbed out %s crossing %d cells" % [str(build.swam), str(build.climbed_out), build.swim_width])
		return
	if name == "water_trench":
		after["fill_levels"] = build.fill_levels
		after["wall_levels"] = build.wall_levels
		after["step_levels"] = build.step_levels
		var wc: Vector2i = build._trench_cell(build.WALL_AT)
		after["wall_built"] = load("res://world/terrain_edits.gd").get_build_tile(wc.x, wc.y) >= 0
		print("HARNESS water_trench down-step %s" % str(build.step_levels))
		print("HARNESS water_trench fill %s after wall %s wall cell %d (cells past the wall are idx %d..)" % [str(build.fill_levels), str(build.wall_levels), build.WALL_AT, build.WALL_AT])
		return
	if name == "controls_tour":
		after["tour"] = build.tour_checks
		return
	if name == "camera" or name == "hotbar":
		after["cam"] = build.cam_log
		print("HARNESS camera %s" % str(build.cam_log))
		return
	if name == "dev_keys":
		after["t_chat"] = build.t_opened_chat
		after["shift_changes"] = 0 if build.shift_signature == build.pre_signature else 1
		after["t_changes"] = 0 if build.t_signature == build.pre_signature else 1
		print("HARNESS dev_keys plain T chat %s, terrain unchanged after Shift+T %s and T %s" % [str(build.t_opened_chat), str(build.shift_signature == build.pre_signature), str(build.t_signature == build.pre_signature)])
		return
	if name == "water_dig":
		after["levels"] = build.water_levels()
		var svc = _film_tree.get_first_node_in_group("voxel_fluid_service") if _film_tree != null else null
		if svc != null:
			after["flow_ticks"] = int(svc.get_sim_diagnostics().get("tick_id", 0))
		print("HARNESS water entry request_flow -> VoxelFluidEngine.tick_flow ticks %d levels %s" % [int(after.get("flow_ticks", 0)), str(after.get("levels", []))])
		return
	if name == "multi_dig":
		after["columns"] = build._dropped_count()
		return
	if name == "multi_build" or name == "mouse_build":
		after["walls"] = int(build._new_tiles())
		after["stone_spent"] = int(build.stone_pre) - int(build.stone_post)
		return
	if name == "dig":
		var cell: Vector2i = build._dropped()
		if cell.x >= 900000:
			return
		var was := float(build.heights.get(cell, _Edits.get_height_delta(cell.x, cell.y)))
		after["drop"] = was - _Edits.get_height_delta(cell.x, cell.y)
		return
	after["walls"] = int(build._new_tiles())
	after["stone_spent"] = int(build.stone_pre) - int(build.stone_post)


func _note_banner(tree: SceneTree, seen: PackedStringArray) -> void:
	var toast = tree.root.find_child("ToastLabel", true, false)
	if toast == null or not toast.visible:
		return
	var text := str(toast.text).strip_edges()
	if text == "" or _saw(seen, text):
		return
	seen.append(text)


func _saw(seen: PackedStringArray, text: String) -> bool:
	for line in seen:
		if line == text:
			return true
	return false


func _label_under(node: Node) -> String:
	var found := ""
	for child in node.get_children():
		if child is Label:
			var text := str(child.text)
			if "/" in text:
				return text
		var nested := _label_under(child)
		if nested != "":
			found = nested
	return found


func _give_up(bot, player, reason: String) -> int:
	var pos := _xz(player)
	bot.home = pos
	bot.fail_closed(pos, reason)
	return 1


func _xz(player) -> Vector2:
	if player == null or not ("voxel_position" in player):
		return Vector2.ZERO
	var feet: Vector3 = player.voxel_position
	return Vector2(feet.x, feet.z)


func _delta(tree: SceneTree) -> float:
	var delta := tree.root.get_process_delta_time()
	if delta <= 0.0:
		return STEP
	return minf(delta, 1.0 / 30.0)


const FEATURE_LIMIT := {
	"crystals": 90.0,
	"corruption": 240.0,
	"combat": 240.0,
}
const POINT_BLANK_COLUMNS := 0.5
const FIND_COLUMNS := 8.0
const FILM_DEPTH := 0.2
const SWING_GAP := 0.42


func _play_feature(tree: SceneTree, name: String) -> int:
	print("HARNESS seed %d" % SEED)
	print("HARNESS setup pending_launch harness-%s seed %d resume off" % [name, SEED])
	var seen: PackedStringArray = PackedStringArray()
	var player = await _boot(tree, name, seen)
	if player == null:
		return 1
	var crystal = tree.get_first_node_in_group("crystal_manager")
	if crystal == null or not crystal.has_method("get_origin_cell"):
		print("FAIL harness no crystal")
		return 1
	var origin: Vector2i = crystal.get_origin_cell()
	var origin_xz := Vector2(float(origin.x) + 0.5, float(origin.y) + 0.5)
	var bot = _Bot.new()
	bot.chapter = name
	bot.objective = name
	bot.stuck_limit = 12
	var hands = _Hands.new()
	var fight = _Combat.new()
	fight.chip_skills = false
	var cast = _Cast.new()
	var before := _snap(tree, player)
	var heart0 := _heart_hp(crystal)
	var shards0 := _count(player, "crystal_shard")
	var corrupt0 := _corrupt_near(origin, 18)
	var scars0 := _Corrupt.scar_count()
	var job := {
		"found": false,
		"collected": false,
		"used": false,
		"spread": false,
		"cleansed": false,
		"burn_seen": false,
		"burned": false,
		"warned": false,
		"struck": false,
		"melee": false,
		"skilled": false,
		"cast_on": false,
		"heart_mark": heart0,
		"warn_hp": -1.0,
		"burn_hp": -1.0,
		"foe_hp": -1.0,
		"foe_id": "",
		"cell": Vector2i(999999, 999999),
		"swings": 0,
		"gap": 0.0,
		"pick": false,
		"sword": false,
	}
	job["corrupt_boot"] = corrupt0
	job["scars_boot"] = scars0
	var elapsed := 0.0
	var limit := float(FEATURE_LIMIT.get(name, 90.0))
	while elapsed < limit:
		var delta := _delta(tree)
		elapsed += delta
		_note_banner(tree, seen)
		if float(player.health) <= 0.0:
			return _give_up(bot, player, "player died")
		var done := _feature_tick(name, tree, player, crystal, origin, origin_xz, bot, hands, fight, cast, job, delta)
		if done != "":
			return _give_up(bot, player, done)
		if _feature_ready(name, job):
			break
		await tree.process_frame
	if not _feature_ready(name, job):
		return _give_up(bot, player, "scenario did not finish %s" % _feature_miss(name, job))
	var after := _snap(tree, player)
	after["shards"] = _count(player, "crystal_shard")
	after["heart"] = _heart_hp(crystal)
	after["corrupt"] = _corrupt_near(origin, 18)
	after["scars"] = _Corrupt.scar_count()
	before["shards"] = shards0
	before["heart"] = heart0
	before["corrupt"] = corrupt0
	before["scars"] = scars0
	var reason := _expect_feature(name, before, after, seen, job)
	if reason != "":
		print("FAIL harness assertion %s" % reason)
		return _give_up(bot, player, "assertion %s" % reason)
	_print_feature(name, before, after, seen, job)
	var shot := bot.save_view(name, _xz(player))
	if shot == "":
		return _give_up(bot, player, "screenshot was not saved")
	return 0


func _feature_ready(name: String, job: Dictionary) -> bool:
	if name == "crystals":
		return bool(job["found"]) and bool(job["collected"]) and bool(job["used"])
	if name == "corruption":
		return bool(job["spread"]) and bool(job["cleansed"]) and bool(job["burned"])
	return bool(job["struck"]) and bool(job["melee"]) and bool(job["skilled"])


func _feature_miss(name: String, job: Dictionary) -> String:
	var bits: PackedStringArray = PackedStringArray()
	if name == "crystals":
		if not bool(job["found"]):
			bits.append("find")
		if not bool(job["collected"]):
			bits.append("collect")
		if not bool(job["used"]):
			bits.append("use")
	elif name == "corruption":
		if not bool(job["spread"]):
			bits.append("spread")
		if not bool(job["cleansed"]):
			bits.append("cleanse")
		if not bool(job["burned"]):
			bits.append("burn")
	else:
		if not bool(job["struck"]):
			bits.append("warning")
		if not bool(job["melee"]):
			bits.append("melee")
		if not bool(job["skilled"]):
			bits.append("skill")
	return ",".join(bits)


func _feature_tick(name: String, tree: SceneTree, player: Node, crystal: Node, origin: Vector2i, origin_xz: Vector2, bot, hands, fight, cast, job: Dictionary, delta: float) -> String:
	var pos := _xz(player)
	if name == "crystals":
		return _tick_crystals(tree, player, crystal, origin, origin_xz, bot, hands, job, delta, pos)
	if name == "corruption":
		return _tick_corruption(tree, player, crystal, origin, origin_xz, bot, hands, job, delta, pos)
	return _tick_combat(tree, player, crystal, origin, origin_xz, bot, hands, fight, cast, job, delta, pos)


func _tick_crystals(tree: SceneTree, player: Node, crystal: Node, origin: Vector2i, origin_xz: Vector2, bot, hands, job: Dictionary, delta: float, pos: Vector2) -> String:
	if _attack_warn(tree):
		_step_away(tree, player, bot, origin_xz, delta, pos)
		return ""
	if not bool(job["found"]):
		if pos.distance_to(origin_xz) <= FIND_COLUMNS:
			job["found"] = true
			print("HARNESS found heart %.1f" % pos.distance_to(origin_xz))
			return ""
		_step_toward(bot, player, origin_xz, delta, pos)
		return ""
	if not bool(job["collected"]):
		if _count(player, "crystal_shard") > 0:
			job["collected"] = true
			job["cell"] = Vector2i(999999, 999999)
			job["swings"] = 0
			job["pick"] = false
			job["heart_mark"] = _heart_hp(crystal)
			print("HARNESS collected shards %d" % _count(player, "crystal_shard"))
			return ""
		_swing_film(tree, player, crystal, origin, origin_xz, bot, hands, job, delta, pos, false)
		return ""
	if not bool(job["used"]):
		var heart := _heart_hp(crystal)
		if heart >= 0.0 and heart < float(job["heart_mark"]) - 0.05:
			job["used"] = true
			print("HARNESS used heart %.1f to %.1f" % [float(job["heart_mark"]), heart])
			bot.release()
			return ""
		_swing_heart(tree, player, origin, bot, hands, job, delta, pos)
	return ""


func _tick_corruption(tree: SceneTree, player: Node, crystal: Node, origin: Vector2i, origin_xz: Vector2, bot, hands, job: Dictionary, delta: float, pos: Vector2) -> String:
	var corrupt_now := _corrupt_near(origin, 18)
	if not bool(job["spread"]) and corrupt_now > int(job["corrupt_boot"]):
		job["spread"] = true
		job["corrupt_seen"] = corrupt_now
		print("HARNESS spread corrupt %d to %d" % [int(job["corrupt_boot"]), corrupt_now])
	if not bool(job["cleansed"]):
		if _attack_warn(tree) or _Hazard.ring_hot(tree, pos):
			_leave_attack(tree, player, bot, origin_xz, job, delta, pos)
			return ""
		if _Corrupt.scar_count() > int(job["scars_boot"]):
			job["cleansed"] = true
			job["scars_seen"] = _Corrupt.scar_count()
			job["cell"] = Vector2i(999999, 999999)
			print("HARNESS cleansed scars %d" % int(job["scars_seen"]))
		else:
			_swing_film(tree, player, crystal, origin, origin_xz, bot, hands, job, delta, pos, false)
			return ""
	if bool(job["burned"]):
		bot.release()
		return ""
	var tier := int(crystal.get("strength_tier"))
	var warned := _attack_warn(tree) or _Hazard.ring_hot(tree, pos)
	var deep_here := _Hazard.depth_at(tree, pos) >= _Hazard.BURN_DEPTH
	var burn := tree.root.find_child("BurnWarn", true, false)
	var burn_up: bool = burn != null and bool(burn.visible)
	if not burn_up and (warned or (tier < 1 and deep_here)):
		_leave_attack(tree, player, bot, origin_xz, job, delta, pos)
		return ""
	if tier < 1:
		job["dodge"] = Vector2.INF
		var foe := _nearest_foe_xz(tree, pos)
		if foe != Vector2.INF and pos.distance_to(foe) < 8.0:
			_leave_attack(tree, player, bot, origin_xz, job, delta, pos)
			return ""
		_step_toward(bot, player, _orbit_wait(origin_xz, pos), delta, pos, true)
		return ""
	var deep := _deep_stand(crystal, origin, pos)
	if not deep_here:
		job["dodge"] = Vector2.INF
		_step_toward(bot, player, deep, delta, pos, true)
		return ""
	if not bool(job.get("stand_logged", false)):
		job["stand_logged"] = true
		print("HARNESS burn stand tier %d hp %.1f" % [tier, float(player.health)])
	job["dodge"] = Vector2.INF
	bot.release()
	if burn_up:
		if not bool(job["burn_seen"]):
			job["burn_seen"] = true
			job["burn_hp"] = float(player.health)
			print("HARNESS burn warning hp %.1f" % float(player.health))
		elif float(player.health) < float(job["burn_hp"]) - 0.05:
			job["burned"] = true
			print("HARNESS burn hit %.1f to %.1f" % [float(job["burn_hp"]), float(player.health)])
			var away := _Hazard.leave_goal(tree, pos, origin_xz)
			_step_toward(bot, player, away, delta, pos)
	return ""


func _tick_combat(tree: SceneTree, player: Node, crystal: Node, origin: Vector2i, origin_xz: Vector2, bot, hands, fight, cast, job: Dictionary, delta: float, pos: Vector2) -> String:
	_note_hit_feedback(tree, job)
	_combat_tree = tree
	_combat_player = player
	_combat_job = job
	if float(job.get("mite_far", -1.0)) >= 0.0:
		return "mite hit %.2f columns" % float(job["mite_far"])
	if not bool(job["struck"]):
		if _mite_telegraph_columns(tree, pos, job) < 90.0:
			bot.release()
			if float(job["warn_hp"]) < 0.0:
				job["warn_hp"] = float(player.health)
				job["warned"] = true
				print("HARNESS attack warning hp %.1f" % float(player.health))
			return ""
		if _attack_warn(tree):
			_step_away(tree, player, bot, origin_xz, delta, pos)
			return ""
		if pos.distance_to(origin_xz) > 12.0:
			_step_toward(bot, player, origin_xz, delta, pos)
			return ""
		_swing_film(tree, player, crystal, origin, origin_xz, bot, hands, job, delta, pos, false)
		return ""
	if not bool(job["melee"]):
		if (_attack_warn(tree) and pos.distance_to(_nearest_foe_xz(tree, pos)) > 1.5) or _Hazard.ring_hot(tree, pos):
			_step_away(tree, player, bot, origin_xz, delta, pos)
			return ""
		var rows := _near_foes(tree, pos)
		fight.set_vitals(float(player.health), float(player.max_health))
		fight.observe(rows)
		var foe_id := str(job["foe_id"])
		if foe_id != "":
			var now_hp := _foe_health(tree, foe_id)
			var was := float(job["foe_hp"])
			if was >= 0.0 and (now_hp < 0.0 or now_hp < was - 0.05):
				var swung := float(job.get("blank_swing", 99.0))
				if swung > POINT_BLANK_COLUMNS:
					job["foe_hp"] = now_hp
				elif _blank_missed():
					return "melee no entity hit"
				else:
					job["melee"] = true
					job["blank_cols"] = swung
					print("HARNESS point blank %.2f" % swung)
					print("HARNESS melee %s %.1f to %.1f" % [foe_id, was, now_hp])
					fight.release()
					return ""
		var picked := _combat_foe(rows, pos)
		if foe_id == "" or not _foe_alive(tree, foe_id):
			foe_id = str(picked.get("id", ""))
			job["foe_id"] = foe_id
			job["foe_hp"] = _foe_health(tree, foe_id)
			job["blank_swing"] = 99.0
			job["blank_swings"] = 0
		if foe_id == "":
			_step_toward(bot, player, origin_xz, delta, pos)
			return ""
		var aim_at: Vector2 = picked.get("xz", Vector2.INF)
		if str(picked.get("id", "")) != foe_id:
			aim_at = _foe_xz(rows, foe_id)
		bot.release()
		if aim_at == Vector2.INF:
			_step_toward(bot, player, origin_xz, delta, pos)
			return ""
		var dist := pos.distance_to(aim_at)
		hands.begin_tick()
		hands.aim_foe(player, aim_at.x, aim_at.y)
		if dist > POINT_BLANK_COLUMNS:
			fight.walk_to(_past_contact(pos, aim_at), pos, _yaw(player), delta)
			return ""
		if int(job.get("blank_swings", 0)) == 0:
			CombatLog.clear()
		var swings_before := int(fight.swings)
		fight.aim_ready = true
		fight.strike_point(pos, aim_at, _yaw(player), delta)
		if fight.swings > swings_before:
			job["blank_swings"] = int(job["blank_swings"]) + 1
			job["blank_swing"] = dist
		if int(job.get("blank_swings", 0)) > 0 and _blank_missed():
			return "melee no entity hit"
		return ""
	if bool(job["skilled"]):
		bot.release()
		return ""
	if _points(tree) < 1 and not _unlocked(tree, "dash"):
		if not bool(job.get("farm_logged", false)):
			job["farm_logged"] = true
			print("HARNESS skill farm points %d" % _points(tree))
		var close := _nearest_foe_xz(tree, pos)
		if close != Vector2.INF and pos.distance_to(close) <= 1.5:
			_farm_strike(player, bot, hands, job, delta, close)
			return ""
		if _attack_warn(tree):
			_step_away(tree, player, bot, origin_xz, delta, pos)
			return ""
		_swing_film(tree, player, crystal, origin, origin_xz, bot, hands, job, delta, pos, false)
		return ""
	if bool(job.get("dash_walk", false)):
		var mark: Vector2 = job.get("dash_from", pos)
		if pos.distance_to(mark) < 6.0:
			var goal: Vector2 = job.get("dash_goal", Vector2.INF)
			if goal == Vector2.INF:
				var side := pos - origin_xz
				if side.length() < 0.4:
					side = Vector2(1.0, 0.0)
				side = Vector2(-side.y, side.x).normalized()
				goal = _Hazard.skirt_goal(tree, pos, pos + side * 12.0)
				job["dash_goal"] = goal
			_step_toward(bot, player, goal, delta, pos, true)
			return ""
		job["dash_walk"] = false
		job["dash_goal"] = Vector2.INF
	if not bool(job["cast_on"]):
		cast.begin("skill_dash")
		job["cast_on"] = true
	var result: String = cast.tick(delta, tree, player, hands, bot, origin_xz, null)
	if result == "pass":
		job["skilled"] = true
		print("HARNESS skill dash")
		return ""
	if result == "fail":
		if int(job.get("dash_tries", 0)) >= 2:
			return "dash did not cast"
		job["dash_tries"] = int(job.get("dash_tries", 0)) + 1
		job["cast_on"] = false
		job["dash_walk"] = true
		job["dash_from"] = pos
		job["dash_goal"] = Vector2.INF
		bot.release()
		return ""
	return ""


func _swing_film(tree: SceneTree, player: Node, crystal: Node, origin: Vector2i, origin_xz: Vector2, bot, hands, job: Dictionary, delta: float, pos: Vector2, any_film: bool) -> void:
	if _attack_warn(tree):
		_step_away(tree, player, bot, origin_xz, delta, pos)
		return
	var cell: Vector2i = job["cell"]
	if cell.x > 900000 or int(job["swings"]) >= 10:
		cell = _film_cell(crystal, origin, pos, any_film)
		job["cell"] = cell
		job["swings"] = 0
		job["pick"] = false
	if cell.x > 900000:
		_step_toward(bot, player, origin_xz, delta, pos)
		return
	var stand := _stand_near(crystal, cell, pos)
	if pos.distance_to(stand) > 0.8:
		_step_toward(bot, player, stand, delta, pos)
		return
	if _GI.blocks_actions():
		bot.release()
		return
	bot.release()
	hands.begin_tick()
	hands.aim_column(player, float(cell.x) + 0.5, float(cell.y) + 0.5)
	if not bool(job["pick"]):
		if hands.pulse(&"hotbar_2"):
			job["pick"] = true
		return
	job["gap"] = float(job["gap"]) - delta
	if float(job["gap"]) > 0.0:
		return
	if hands.pulse(&"attack"):
		job["swings"] = int(job["swings"]) + 1
		job["gap"] = SWING_GAP


func _farm_strike(player: Node, bot, hands, job: Dictionary, delta: float, foe: Vector2) -> void:
	bot.release()
	hands.begin_tick()
	hands.aim_foe(player, foe.x, foe.y)
	if bool(job["pick"]):
		if hands.pulse(&"hotbar_1"):
			job["pick"] = false
		return
	job["gap"] = float(job["gap"]) - delta
	if float(job["gap"]) > 0.0:
		return
	if hands.pulse(&"attack"):
		job["gap"] = _Pace.strike_gap("sword_swing")


func _swing_heart(tree: SceneTree, player: Node, origin: Vector2i, bot, hands, job: Dictionary, delta: float, pos: Vector2) -> void:
	var cell_origin := Vector2(float(origin.x), float(origin.y))
	var aim := cell_origin + Vector2(0.5, 0.5)
	var pad := _Hazard.sword_pad(tree, cell_origin)
	if pad == Vector2.INF:
		pad = aim + Vector2(1.6, 0.2)
	if pos.distance_to(pad) > 0.8:
		job["aim_hold"] = 0.0
		_step_toward(bot, player, pad, delta, pos)
		return
	if _GI.blocks_actions():
		bot.release()
		return
	bot.release()
	hands.begin_tick()
	hands.aim_column(player, aim.x, aim.y)
	var facing := _Nav.face_action(pos, aim, _yaw(player))
	if facing != "":
		job["aim_hold"] = 0.0
		hands.set_held(PackedStringArray([facing]))
		return
	var locked := _heart_aimed(player, origin)
	if locked:
		job["aim_hold"] = 0.0
	else:
		job["aim_hold"] = float(job.get("aim_hold", 0.0)) + delta
	if not locked and float(job["aim_hold"]) < 0.35:
		return
	if not bool(job["sword"]):
		if hands.pulse(&"hotbar_1"):
			job["sword"] = true
		return
	job["gap"] = float(job["gap"]) - delta
	if float(job["gap"]) > 0.0:
		return
	if hands.pulse(&"attack"):
		if not bool(job.get("sword_logged", false)):
			job["sword_logged"] = true
			print("HARNESS sword at heart")
		job["gap"] = _Pace.strike_gap("sword_swing")


func _note_hit_feedback(tree: SceneTree, job: Dictionary) -> void:
	if bool(job.get("feedback", false)):
		return
	var vfx := tree.get_first_node_in_group("combat_visual_feedback")
	if vfx == null:
		return
	var marks = vfx.get_node_or_null("HitMarkers")
	if marks == null or not marks.has_method("has_live"):
		return
	if not bool(marks.has_live()):
		return
	job["feedback"] = true
	print("HARNESS hit feedback")


func _blank_missed() -> bool:
	return "no entity hit" in CombatLog.get_recent(" ")


func _past_contact(pos: Vector2, foe: Vector2) -> Vector2:
	var away := foe - pos
	if away.length() < 0.05:
		away = Vector2(1.0, 0.0)
	else:
		away = away.normalized()
	return foe + away * 1.2


func _combat_foe(rows: Array, pos: Vector2) -> Dictionary:
	var mite := {}
	var mite_d := INF
	var other := {}
	var other_d := INF
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var at: Vector2 = row.get("xz", Vector2.INF)
		var dist := pos.distance_to(at)
		if str(row.get("kind", "")) == "crystal_mite":
			if dist < mite_d:
				mite_d = dist
				mite = row
		elif dist < other_d:
			other_d = dist
			other = row
	if not mite.is_empty():
		return mite
	return other


func _foe_xz(rows: Array, foe_id: String) -> Vector2:
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str(row.get("id", "")) == foe_id:
			return row.get("xz", Vector2.INF)
	return Vector2.INF


func _foe_aimed(player: Node, foe: Vector2) -> bool:
	var hl = player.get_node_or_null("TargetHighlight")
	if hl == null or not hl.has_method("get_action_column"):
		return false
	var shared: Vector3 = hl.get_action_column()
	if shared == Vector3.ZERO:
		return false
	var cell := Vector2(float(floori(shared.x)) + 0.5, float(floori(shared.z)) + 0.5)
	return cell.distance_to(foe) <= 1.15


func _heart_aimed(player: Node, origin: Vector2i) -> bool:
	var hl = player.get_node_or_null("TargetHighlight")
	if hl == null or not hl.has_method("get_action_column"):
		return false
	var shared: Vector3 = hl.get_action_column()
	if shared == Vector3.ZERO:
		return false
	var cell := Vector2(float(floori(shared.x)) + 0.5, float(floori(shared.z)) + 0.5)
	var want := Vector2(float(origin.x) + 0.5, float(origin.y) + 0.5)
	return cell.distance_to(want) <= 1.15


func _step_toward(bot, player: Node, goal: Vector2, delta: float, pos: Vector2, sprint_now: bool = false) -> void:
	if bot.gave_up:
		var spin := float(bot.stuck_reports + 1)
		bot.set_target(goal + Vector2(spin, -spin))
	elif not bot.has_target or bot.target.distance_to(goal) > 1.5:
		bot.set_target(goal)
	var extras := PackedStringArray()
	if sprint_now or pos.distance_to(goal) > 6.0:
		extras.append("sprint")
	bot.extra_held = extras
	bot.tick(pos, _yaw(player), delta)


func _orbit_wait(origin_xz: Vector2, pos: Vector2) -> Vector2:
	var offset := pos - origin_xz
	if offset.length() < 8.0:
		if offset.length() < 0.2:
			offset = Vector2(1.0, 0.0)
		else:
			offset = offset.normalized()
		return origin_xz + offset * 12.0
	var side := Vector2(-offset.y, offset.x)
	if side.length_squared() < 0.01:
		side = Vector2(0.0, 1.0)
	return pos + side.normalized() * 4.0


func _leave_attack(tree: SceneTree, player: Node, bot, origin_xz: Vector2, job: Dictionary, delta: float, pos: Vector2) -> void:
	var foe := _nearest_foe_xz(tree, pos)
	var away := pos - foe if foe != Vector2.INF else pos - origin_xz
	var reach := 6.0
	for row in _Hazard.guardian_bubbles(tree):
		if typeof(row) != TYPE_DICTIONARY or not bool(row.get("hard", false)):
			continue
		reach = maxf(reach, float(row.get("radius", reach)))
		var at: Vector2 = row.get("xz", pos)
		var from_ring := pos - at
		if from_ring.length_squared() > 0.01:
			away = from_ring
	var proposed := _Hazard.slam_exit(pos, away, reach, origin_xz)
	if _Hazard.depth_at(tree, proposed) >= _Hazard.BURN_DEPTH:
		var clear := _Hazard.leave_goal(tree, pos, origin_xz)
		if clear != Vector2.INF:
			proposed = clear
	var previous: Vector2 = job.get("dodge", Vector2.INF)
	var goal := _Hazard.keep_dodge(pos, previous, proposed)
	job["dodge"] = goal
	_step_toward(bot, player, goal, delta, pos, true)


func _step_away(tree: SceneTree, player: Node, bot, origin_xz: Vector2, delta: float, pos: Vector2) -> void:
	var foe := _nearest_foe_xz(tree, pos)
	var action := "move_back"
	if foe != Vector2.INF:
		action = _Hazard.flee_action(pos, foe, _yaw(player))
	else:
		var away := _Hazard.leave_goal(tree, pos, origin_xz)
		_step_toward(bot, player, away, delta, pos)
		return
	bot.release()
	bot.input.begin_tick()
	var held := PackedStringArray()
	held.append(action)
	held.append("sprint")
	bot.input.set_held(held)


func _film_cell(crystal: Node, origin: Vector2i, pos: Vector2, any_film: bool) -> Vector2i:
	var best := Vector2i(999999, 999999)
	var best_d := 1.0e9
	for dz in range(-14, 15):
		for dx in range(-14, 15):
			var cell := Vector2i(origin.x + dx, origin.y + dz)
			if not any_film and cell == origin:
				continue
			var depth := float(crystal.get_depth_at(cell.x, cell.y))
			if depth < FILM_DEPTH:
				continue
			var at := Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5)
			var dist := pos.distance_to(at)
			if dist < best_d:
				best_d = dist
				best = cell
	return best


func _stand_near(crystal: Node, cell: Vector2i, pos: Vector2) -> Vector2:
	var best := Vector2(float(cell.x) + 2.2, float(cell.y) + 0.5)
	var best_d := 1.0e9
	var center := Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5)
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var at := Vector2(float(cell.x + dx) + 0.5, float(cell.y + dz) + 0.5)
			var span := at.distance_to(center)
			if span < 1.35 or span > 2.5:
				continue
			if float(crystal.get_depth_at(cell.x + dx, cell.y + dz)) >= _Hazard.BURN_DEPTH:
				continue
			var walk := at.distance_to(pos)
			if walk < best_d:
				best_d = walk
				best = at
	return best


func _deep_stand(crystal: Node, origin: Vector2i, pos: Vector2) -> Vector2:
	var best := Vector2(float(origin.x) + 0.5, float(origin.y) + 0.5)
	var best_d := 1.0e9
	for dz in range(-10, 11):
		for dx in range(-10, 11):
			var cell := Vector2i(origin.x + dx, origin.y + dz)
			if float(crystal.get_depth_at(cell.x, cell.y)) < _Hazard.BURN_DEPTH:
				continue
			var at := Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5)
			var dist := pos.distance_to(at)
			if dist < best_d:
				best_d = dist
				best = at
	return best


func _corrupt_near(origin: Vector2i, radius: int) -> int:
	var count := 0
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var feat: Dictionary = _Features.get_feature(origin.x + dx, origin.y + dz)
			if bool(feat.get("corrupt", false)):
				count += 1
	return count


func _mite_telegraph_columns(tree: SceneTree, pos: Vector2, job: Dictionary) -> float:
	var aim := Vector2(float(floori(pos.x)), float(floori(pos.y)))
	var best := 99.0
	for node in tree.get_nodes_in_group("crystal_enemy"):
		if not is_instance_valid(node) or str(node.get("enemy_id")) != "crystal_mite":
			continue
		var disc := node.get_node_or_null("StrikeTelegraph")
		if disc == null or not disc.visible:
			continue
		var body := node as Node3D
		if body == null:
			continue
		_watch_mite_hit(node, job)
		var col: Vector2i = _Move.column_pos(body.global_position)
		var dist := Vector2(float(col.x), float(col.y)).distance_to(aim)
		if dist < best:
			best = dist
	return best


func _watch_mite_hit(node: Node, job: Dictionary) -> void:
	var seen: Array = job.get("watched_mites", [])
	var id := node.get_instance_id()
	if id in seen:
		return
	if not node.has_signal("attacked_player"):
		return
	seen.append(id)
	job["watched_mites"] = seen
	node.attacked_player.connect(_on_mite_attacked.bind(node))


func _on_mite_attacked(_damage: float, node: Node) -> void:
	if _combat_job.is_empty() or bool(_combat_job.get("struck", false)):
		return
	if not bool(_combat_job.get("warned", false)):
		return
	if _combat_tree == null or _combat_player == null or not is_instance_valid(node):
		return
	var pos := _xz(_combat_player)
	var aim := Vector2(float(floori(pos.x)), float(floori(pos.y)))
	var body := node as Node3D
	if body == null:
		return
	var col: Vector2i = _Move.column_pos(body.global_position)
	var cols := Vector2(float(col.x), float(col.y)).distance_to(aim)
	_combat_job["mite_cols"] = cols
	var hp := float(_combat_player.health)
	print("HARNESS mite hit %.2f columns %.1f to %.1f" % [cols, float(_combat_job.get("warn_hp", hp)), hp])
	if cols > 1.45:
		_combat_job["mite_far"] = cols
		return
	_combat_job["struck"] = true


func _attack_warn(tree: SceneTree) -> bool:
	for node in tree.get_nodes_in_group("crystal_enemy"):
		if not is_instance_valid(node):
			continue
		var disc := node.get_node_or_null("StrikeTelegraph")
		if disc != null and disc.visible:
			return true
		var ring := node.get_node_or_null("TelegraphRing")
		if ring != null and ring.visible:
			return true
	return false


func _foe_rows(tree: SceneTree) -> Array:
	var rows: Array = []
	_collect_foes(rows, tree.get_nodes_in_group("crystal_enemy"), "enemy_id")
	_collect_foes(rows, tree.get_nodes_in_group("world_entity"), "entity_kind")
	return rows


func _collect_foes(rows: Array, nodes: Array, kind_field: String) -> void:
	for node in nodes:
		if not is_instance_valid(node) or float(node.get("health")) <= 0.0:
			continue
		var kind := str(node.get(kind_field))
		if kind == "town_villager" or kind == "town_militia":
			continue
		var body := node as Node3D
		if body == null:
			continue
		var col: Vector2i = _Move.column_pos(body.global_position)
		rows.append({
			"id": str(node.get_instance_id()),
			"kind": kind,
			"xz": Vector2(float(col.x) + 0.5, float(col.y) + 0.5),
		})


func _near_foes(tree: SceneTree, pos: Vector2) -> Array:
	var close: Array = []
	for row in _foe_rows(tree):
		if str(row.get("kind", "")) == "origin_warden":
			continue
		var at: Vector2 = row["xz"]
		if pos.distance_to(at) > 28.0:
			continue
		close.append(row)
	return close


func _nearest_foe_xz(tree: SceneTree, pos: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := 1.0e9
	for row in _foe_rows(tree):
		var at: Vector2 = row["xz"]
		var dist := pos.distance_to(at)
		if dist < best_d:
			best_d = dist
			best = at
	return best


func _foe_alive(tree: SceneTree, foe_id: String) -> bool:
	return _foe_health(tree, foe_id) > 0.0


func _foe_health(tree: SceneTree, foe_id: String) -> float:
	if foe_id == "":
		return -1.0
	for node in tree.get_nodes_in_group("crystal_enemy"):
		if str(node.get_instance_id()) != foe_id:
			continue
		if not is_instance_valid(node):
			return -1.0
		return float(node.get("health"))
	return -1.0


func _heart_hp(crystal: Node) -> float:
	if crystal == null or not crystal.has_method("get_spawn_progress"):
		return -1.0
	var prog: Dictionary = crystal.get_spawn_progress()
	return float(prog.get("crystal_health", -1.0))


func _count(player: Node, item_id: String) -> int:
	var inv = player.get("inventory")
	if inv == null or not inv.has_method("count_item"):
		return 0
	return int(inv.count_item(item_id))


func _points(tree: SceneTree) -> int:
	var svc := tree.get_first_node_in_group("progression_service")
	if svc == null:
		return 0
	return int(svc.get("skill_points"))


func _unlocked(tree: SceneTree, skill_id: String) -> bool:
	var skills := tree.get_first_node_in_group("skill_service")
	if skills == null or not skills.has_method("is_unlocked"):
		return false
	return bool(skills.is_unlocked(StringName(skill_id)))


func _expect_feature(name: String, before: Dictionary, after: Dictionary, seen: PackedStringArray, job: Dictionary) -> String:
	if not bool(after.get("hp_panel", false)):
		return "hp bar hidden"
	var want_hp := "%d / %d" % [int(round(float(after.get("hp", 0.0)))), int(round(float(after.get("max", 0.0))))]
	if str(after.get("hp_label", "")) != want_hp:
		return "hp label %s want %s" % [str(after.get("hp_label", "")), want_hp]
	if not _saw(seen, OPENING_BANNER):
		return "opening banner missing"
	for line in seen:
		if not _banner_allowed(line):
			return "unexpected banner %s" % line
	if name == "crystals":
		if absf(float(after.get("hp", -1.0)) - float(before.get("hp", -2.0))) > 0.01:
			return "hp changed"
		if int(after.get("shards", 0)) <= int(before.get("shards", 0)):
			return "shards did not increase"
		if float(after.get("heart", -1.0)) >= float(before.get("heart", -2.0)) - 0.05:
			return "crystal hp did not fall"
		return ""
	if float(after.get("hp", 1.0)) >= float(before.get("hp", 0.0)) - 0.05 and not _foes_cleared():
		return "no damage taken and foes remain"
	if name == "corruption":
		if not bool(job.get("spread", false)):
			return "corruption did not spread"
		if not bool(job.get("cleansed", false)):
			return "scar did not start"
		if not bool(job["burn_seen"]):
			return "burn warning missing"
		return ""
	if not bool(job["warned"]):
		return "attack warning missing"
	if float(job.get("mite_cols", 99.0)) > 1.45:
		return "mite hit %.2f columns" % float(job.get("mite_cols", 99.0))
	if not bool(job["melee"]):
		return "melee missed"
	if float(job.get("blank_cols", 99.0)) > POINT_BLANK_COLUMNS:
		return "point blank %.2f" % float(job.get("blank_cols", 99.0))
	if not bool(job.get("feedback", false)):
		return "hit feedback missing"
	if not bool(job["skilled"]):
		return "dash missing"
	return ""


func _foes_cleared() -> bool:
	if _combat_tree == null or _combat_player == null or not is_instance_valid(_combat_player):
		return false
	return _near_foes(_combat_tree, _xz(_combat_player)).is_empty()


func _banner_allowed(line: String) -> bool:
	if line == OPENING_BANNER or line == WALL_BANNER:
		return true
	var prefixes: PackedStringArray = PackedStringArray([
		"First steps ",
		"Trench ",
		"Gate ",
		"Bridge ",
		"Bank to water",
		"Enemy unlocked:",
		"Boss warning",
		"Crystal coverage",
		"Crystal pressure",
		"Crystal hostiles",
		"Crystal cracked",
		"ASSAULT ",
		"Maze again",
		"Level up ",
		"Skill unlocked",
		"New brush unlocked",
		"crystal_mite down",
		"Can't dig here",
		"Relic ",
		"Discovered ",
		"Landmark ",
		"You rallied ",
		"Origin Warden",
		"Shard Tyrant",
		"Used herb",
	])
	for prefix in prefixes:
		if line.begins_with(prefix):
			return true
	if " fell " in line or line.ends_with(" fell."):
		return true
	if " is under " in line or " calls " in line:
		return true
	return false


func _print_feature(name: String, before: Dictionary, after: Dictionary, seen: PackedStringArray, job: Dictionary) -> void:
	var corrupt_now := int(after.get("corrupt", 0))
	var scars_now := int(after.get("scars", 0))
	var corrupt_peak := maxi(corrupt_now, int(job.get("corrupt_seen", corrupt_now)))
	var scars_peak := maxi(scars_now, int(job.get("scars_seen", scars_now)))
	print("HARNESS see %s shards %d to %d heart %.1f to %.1f corrupt %d to %d now %d scars %d to %d now %d hp %s banners %s" % [
		name,
		int(before.get("shards", 0)),
		int(after.get("shards", 0)),
		float(before.get("heart", -1.0)),
		float(after.get("heart", -1.0)),
		int(before.get("corrupt", 0)),
		corrupt_peak,
		corrupt_now,
		int(before.get("scars", 0)),
		scars_peak,
		scars_now,
		str(after.get("hp_label", "")),
		"|".join(seen),
	])


const MITE_LIMIT := 150.0
const MITE_CLEAR := 16.0
const MITE_BOSS_HEART := 4.0


func _play_mite(tree: SceneTree) -> int:
	var seeds: Array = _mite_seeds()
	var lived := 0
	var killed_runs := 0
	var boss_near := 0
	for seed_value in seeds:
		var seed := int(seed_value)
		var row: Dictionary = await _mite_attempt(tree, seed)
		var survived: bool = bool(row.get("survive", false))
		var kills := int(row.get("kills", 0))
		var sprints := int(row.get("burn_sprint", 0))
		var near := int(row.get("boss_near", 0))
		var off_film := int(row.get("off_film", 0))
		boss_near += near
		if survived:
			lived += 1
		if kills > 0:
			killed_runs += 1
		var elite_amt := float(row.get("elite", 0.0))
		var boss_src := float(row.get("boss_src", 0.0))
		print("HARNESS mite seed %d survive %s kill %d burn_sprint %d boss_near %d off_film %d spawn_elite %.1f boss_src %.1f" % [
			seed, "yes" if survived else "no", kills, sprints, near, off_film, elite_amt, boss_src,
		])
		if not survived or kills < 1 or sprints > 0 or near > 0 or off_film < 1 or elite_amt <= 0.0 or boss_src > 0.0:
			var why := str(row.get("why", "mite fight failed"))
			print("FAIL harness assertion %s" % why)
			var bot = row.get("bot", null)
			if bot != null:
				var at: Vector2 = row.get("pos", Vector2.ZERO)
				bot.home = at
				bot.fail_closed(at, why)
			return 1
	print("HARNESS mite %d/%d survive %d/%d kill" % [lived, seeds.size(), killed_runs, seeds.size()])
	print("HARNESS mite boss_hits_near_heart %d" % boss_near)
	return 0


func _elite_stand(tree: SceneTree) -> Vector2:
	if tree == null:
		return Vector2.INF
	for node in tree.get_nodes_in_group("crystal_enemy"):
		if not is_instance_valid(node) or str(node.get("enemy_id")) != "spawn_elite":
			continue
		if float(node.get("health")) <= 0.0:
			continue
		if node.has_method("holds_station") and node.has_method("station_cell") and bool(node.holds_station()):
			var cell: Vector2i = node.station_cell()
			return Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5)
		var body := node as Node3D
		if body == null:
			continue
		var col := _Move.column_pos(body.global_position)
		return Vector2(float(col.x) + 0.5, float(col.y) + 0.5)
	return Vector2.INF


func _approach_elite(tree: SceneTree, fight, player: Node, delta: float) -> bool:
	var stand := _elite_stand(tree)
	if stand == Vector2.INF:
		return false
	var pos := _xz(player)
	if pos.distance_to(stand) > 28.0:
		return false
	fight.trace_branch = "elite"
	fight.trace_hunt = "elite"
	fight.bot.chapter = "mite_fight"
	fight.bot.objective = "stand in the shard tyrant slam"
	if pos.distance_to(stand) <= 2.05:
		fight.bot.gave_up = false
		fight.bot.extra_held = PackedStringArray()
		fight.bot.release()
		return true
	var step: Vector2 = fight._clear_step_toward(tree, pos, stand)
	if step.distance_to(stand) + 0.05 >= pos.distance_to(stand):
		var gap := stand - pos
		if gap.length() > 0.2:
			step = pos + gap.normalized() * minf(1.4, gap.length())
	fight._step_clear(delta, tree, player, step, stand, false)
	return true


func _damage_taken_from(tree: SceneTree, source: String) -> float:
	var tele = tree.root.get_node_or_null("DifficultyTelemetry")
	if tele == null or not ("events" in tele):
		return 0.0
	var total := 0.0
	for row in tele.events:
		if str(row.get("kind", "")) != "damage_taken":
			continue
		if str(row.get("source", "")) != source:
			continue
		total += float(row.get("amount", 0.0))
	return total


func _boss_hits_near_heart(tree: SceneTree, limit: float) -> int:
	var tele = tree.root.get_node_or_null("DifficultyTelemetry")
	if tele == null or not ("events" in tele):
		return 0
	var hits := 0
	for row in tele.events:
		if str(row.get("kind", "")) != "damage_taken":
			continue
		if str(row.get("source", "")) != "boss":
			continue
		if not row.has("heart_columns"):
			continue
		if float(row.get("heart_columns", 999.0)) <= limit:
			hits += 1
	return hits


func _bind_film_watch(tree: SceneTree) -> void:
	if tree == null:
		return
	for node in tree.get_nodes_in_group("crystal_enemy"):
		if not is_instance_valid(node):
			continue
		if str(node.get("enemy_id")) != "crystal_mite":
			continue
		var iid := node.get_instance_id()
		if _film_bound.has(iid):
			continue
		_film_bound[iid] = true
		if node.has_signal("killed"):
			node.killed.connect(_on_film_kill)
		if node.has_signal("attacked_player"):
			node.attacked_player.connect(_on_film_contact.bind(node))


func _on_film_kill(enemy_id: StringName, cell: Vector2i, _player_killed: bool) -> void:
	if str(enemy_id) != "crystal_mite":
		return
	_count_off_film("kill", cell)


func _on_film_contact(_damage: float, node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var body := node as Node3D
	if body == null:
		return
	_count_off_film("contact", _Move.column_pos(body.global_position))


func _count_off_film(kind: String, cell: Vector2i) -> void:
	var depth := _Hazard.depth_at(_film_tree, Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5))
	if depth >= _Hazard.CLEAR_DEPTH:
		return
	_off_film += 1
	print("HARNESS mite off_film %s depth %.3f cell %d,%d" % [kind, depth, cell.x, cell.y])


func _mite_seeds() -> Array:
	var one := OS.get_environment("CRYSTALSTORM_HARNESS_SEED").strip_edges()
	if one != "":
		return [int(one)]
	var many := OS.get_environment("CRYSTALSTORM_HARNESS_SEEDS").strip_edges()
	if many != "":
		var picked: Array = []
		for part in many.split(","):
			var bit := part.strip_edges()
			if bit != "":
				picked.append(int(bit))
		if not picked.is_empty():
			return picked
	return [12349, 12350, 12351, 12352, 12353]


func _mite_attempt(tree: SceneTree, seed_value: int) -> Dictionary:
	print("HARNESS seed %d" % seed_value)
	print("HARNESS setup pending_launch harness-mite_fight seed %d resume off" % seed_value)
	var seen: PackedStringArray = PackedStringArray()
	var player = await _boot(tree, "mite_fight", seen, seed_value)
	if player == null:
		return {"survive": false, "kills": 0, "burn_sprint": 0, "why": "boot failed"}
	var crystal = tree.get_first_node_in_group("crystal_manager")
	if crystal == null or not crystal.has_method("get_origin_cell"):
		await _drop_game(tree, player)
		return {"survive": false, "kills": 0, "burn_sprint": 0, "why": "no crystal"}
	var origin: Vector2i = crystal.get_origin_cell()
	var origin_xz := Vector2(float(origin.x), float(origin.y))
	var fight = _Fight.new()
	fight._phase = "hunt"
	fight._home_arrived = true
	fight._home_logged = true
	fight.finish_bow()
	var tele = tree.root.get_node_or_null("DifficultyTelemetry")
	if tele != null and tele.has_method("begin_session"):
		tele.begin_session()
	fight.film_clear = true
	fight.bot.chapter = "mite_fight"
	fight.bot.objective = "kill the crystal mites from the clear rim"
	fight.bot.stuck_limit = 24
	_off_film = 0
	_film_bound = {}
	_film_tree = tree
	fight.bot.input.pace_presses = true
	var elapsed := 0.0
	var seeking_elite := true
	var elite_hit := 0.0
	var elite_logged := false
	var clear := 0.0
	var burn_sprint := 0
	var why := ""
	var last_pos := Vector2.ZERO
	var trace_key := ""
	while elapsed < MITE_LIMIT:
		var delta := _delta(tree)
		elapsed += delta
		fight.bot.input.advance_pace(delta)
		_note_banner(tree, seen)
		if float(player.health) <= 0.0:
			var died_at := _xz(player)
			why = "player died seed %d depth %.2f dist %.1f" % [
				seed_value, _Hazard.depth_at(tree, died_at), died_at.distance_to(origin_xz),
			]
			break
		fight.trace_branch = "none"
		fight.trace_hunt = "none"
		fight.trace_strike = ""
		_bind_film_watch(tree)
		var result := ""
		if seeking_elite and _approach_elite(tree, fight, player, delta):
			if fight.bot.gave_up:
				why = "could not reach the shard tyrant seed %d" % seed_value
				break
			elite_hit = _damage_taken_from(tree, "spawn_elite")
			if elite_hit > 0.0:
				if not elite_logged:
					elite_logged = true
					print("HARNESS mite spawn_elite %.1f" % elite_hit)
				seeking_elite = false
				fight.bot.extra_held = PackedStringArray()
				fight.bot.release()
				fight.bot.has_target = false
				fight.bot.arrived = false
				fight.bot.gave_up = false
		else:
			result = fight.tick(delta, tree, player, origin_xz)
		var pos := _xz(player)
		var near_row: Dictionary = fight._nearest_mite(tree, pos)
		var near_d := -1.0
		if not near_row.is_empty():
			near_d = pos.distance_to(near_row.get("xz", pos))
		var trace_now := "%s|%s|%d" % [fight.trace_branch, fight.trace_foe, int(elapsed)]
		if trace_now != trace_key:
			trace_key = trace_now
			print("HARNESS mite frame t %.3f branch %s strike %s heal %s foe_id %s mite %.2f reach %.2f aim %s wait %.2f gap %.2f swing_left %.2f sword %s pace %s pace_ok %s hp %.1f herbs %d depth %.2f" % [
				elapsed, fight.trace_branch, fight.trace_strike, fight.trace_heal, fight.trace_foe, near_d, _Hazard.sword_reach(),
				str(fight._aim_on_foe(player, near_row.get("xz", pos))) if not near_row.is_empty() else "na",
				fight._attack_wait, fight._sword_gap(), fight._swing_left, str(fight._sword), str(fight.bot.input.pace_presses),
				"%.2f" % float(fight.bot.input._since_press),
				float(player.health), fight._herbs(player), _Hazard.depth_at(tree, pos),
			])
			fight.trace_heal = ""
			var live_node: Node3D = null
			var live_best := 1.0e9
			for live in tree.get_nodes_in_group("crystal_enemy"):
				if not is_instance_valid(live) or str(live.get("enemy_id")) != "crystal_mite" or float(live.get("health")) <= 0.0:
					continue
				var live_d := (live as Node3D).global_position.distance_to((player as Node3D).global_position)
				if live_d < live_best:
					live_best = live_d
					live_node = live
			if live_node != null:
				var ws = _WorldSettings.get_active()
				var lg := live_node.global_position
				var pg := (player as Node3D).global_position
				var live_xz := Vector2(ws.world_to_column(lg.x), ws.world_to_column(lg.z))
				var self_cell := _Move.column_pos(lg)
				var aim_cell: Vector2i = live_node.call("_player_column")
				print("HARNESS mite live t %.3f hunt %s branch %s live %.2f,%.2f bot %.2f,%.2f live_d %.2f bot_d %.2f self_cell %d,%d aim_cell %d,%d cell_d %.2f world_d %.2f world_xz_d %.2f dy %.2f windup %.2f hp %.1f" % [
					elapsed, fight.trace_hunt, fight.trace_branch, live_xz.x, live_xz.y, pos.x, pos.y,
					live_xz.distance_to(pos), near_d, self_cell.x, self_cell.y, aim_cell.x, aim_cell.y,
					Vector2(self_cell).distance_to(Vector2(aim_cell)), lg.distance_to(live_node.call("_player_world_pos")),
					Vector2(lg.x, lg.z).distance_to(Vector2(pg.x, pg.z)), lg.y - pg.y, float(live_node.get("_contact_left")), float(player.health),
				])
		else:
			fight.trace_heal = ""
		last_pos = pos
		if _burn_sprint(tree, fight, player, pos):
			burn_sprint += 1
		var mark := int(elapsed)
		if mark > 0 and mark % 5 == 0 and int(elapsed - delta) != mark:
			var mite_row: Dictionary = fight._nearest_mite(tree, pos)
			var mite_d := -1.0
			if not mite_row.is_empty():
				var mite_at: Vector2 = mite_row.get("xz", pos)
				mite_d = pos.distance_to(mite_at)
			print("HARNESS mite trace t %d dist %.1f foe %.1f depth %.2f hp %.0f burn_sprint %d" % [
				mark, pos.distance_to(origin_xz), mite_d, _Hazard.depth_at(tree, pos), float(player.health), burn_sprint,
			])
		if result == "fail":
			why = "fight returned fail seed %d" % seed_value
			break
		var kills := int(fight.killed.get("crystal_mite", 0))
		var near := _mites_near(tree, origin_xz, MITE_CLEAR)
		if kills >= 1 and near == 0 and not _Hazard.burning(tree, pos) and not _Hazard.must_leave(tree, pos):
			clear += delta
		else:
			clear = 0.0
		if clear >= 1.0 and not seeking_elite:
			break
		await tree.process_frame
	var survived := player != null and float(player.health) > 0.0 and why == ""
	var total := int(fight.killed.get("crystal_mite", 0))
	if why == "" and not _saw(seen, OPENING_BANNER):
		why = "opening banner missing"
		survived = false
	if why == "" and total < 1:
		why = "no mite kill seed %d" % seed_value
	if why == "" and burn_sprint > 0:
		why = "burn sprint %d seed %d" % [burn_sprint, seed_value]
	var boss_near := _boss_hits_near_heart(tree, MITE_BOSS_HEART)
	print("HARNESS mite boss_near %d" % boss_near)
	if why == "" and boss_near > 0:
		why = "boss hits within 4 columns %d seed %d" % [boss_near, seed_value]
		survived = false
	if why == "" and _off_film < 1:
		why = "no mite contact or kill off the 0.12 film seed %d" % seed_value
		survived = false
	elite_hit = _damage_taken_from(tree, "spawn_elite")
	var boss_src := _damage_taken_from(tree, "boss")
	var tele_path := ""
	if tele != null and tele.has_method("flush"):
		tele_path = str(tele.flush())
	print("HARNESS mite telemetry %s spawn_elite %.1f boss %.1f" % [tele_path, elite_hit, boss_src])
	if why == "" and elite_hit <= 0.0:
		why = "no spawn_elite damage seed %d" % seed_value
		survived = false
	if why == "" and boss_src > 0.0:
		why = "boss source %.1f is not separate from the tyrant seed %d" % [boss_src, seed_value]
		survived = false
	var after := _snap(tree, player)
	if survived:
		var want_hp := "%d / %d" % [int(round(float(after.get("hp", 0.0)))), int(round(float(after.get("max", 0.0))))]
		if str(after.get("hp_label", "")) != want_hp:
			why = "hp label %s want %s" % [str(after.get("hp_label", "")), want_hp]
			survived = false
	print("HARNESS see mite_fight seed %d kills %d burn_sprint %d hp %s" % [
		seed_value, total, burn_sprint, str(after.get("hp_label", "")),
	])
	var shot := ""
	if survived and why == "":
		shot = fight.bot.save_view("mite_fight", _xz(player))
		if shot == "":
			why = "screenshot was not saved"
			survived = false
	fight.bot.release()
	var kept = fight.bot
	await _drop_game(tree, player)
	return {
		"survive": survived and why == "",
		"kills": total,
		"burn_sprint": burn_sprint,
		"boss_near": boss_near,
		"off_film": _off_film,
		"elite": elite_hit,
		"boss_src": boss_src,
		"why": why,
		"bot": kept,
		"pos": last_pos,
	}


func _burn_sprint(tree: SceneTree, fight, player: Node, pos: Vector2) -> bool:
	var names: PackedStringArray = fight.bot.input.held_names()
	var sprinting := false
	var dashing := false
	for action in names:
		if String(action) == "sprint":
			sprinting = true
		if String(action) == "skill_1" or String(action) == "dash":
			dashing = true
	var goal: Vector2 = fight.bot.home
	var through := _Hazard.burning(tree, pos) or _Hazard.burning(tree, goal) or _Hazard.crosses_burn(tree, pos, goal)
	if sprinting and through:
		return true
	return dashing and _Hazard.dash_lands_in_burn(tree, pos, _yaw(player))


func _mites_near(tree: SceneTree, origin: Vector2, radius: float) -> int:
	var count := 0
	if tree == null:
		return 0
	for node in tree.get_nodes_in_group("crystal_enemy"):
		if not is_instance_valid(node) or str(node.get("enemy_id")) != "crystal_mite":
			continue
		if float(node.get("health")) <= 0.0:
			continue
		var body := node as Node3D
		if body == null:
			continue
		var col := _Move.column_pos(body.global_position)
		var at := Vector2(float(col.x) + 0.5, float(col.y) + 0.5)
		if at.distance_to(origin) <= radius:
			count += 1
	return count


func _drop_game(tree: SceneTree, player: Node) -> void:
	var game := player
	while game != null and game.name != "Game":
		game = game.get_parent()
	if game != null and game != tree.root:
		game.queue_free()
	for _i in 30:
		await tree.process_frame
		if tree.get_first_node_in_group("player") == null:
			break


func _yaw(player: Node) -> float:
	var cam = player.get("camera")
	if cam != null and "yaw_degrees" in cam:
		return float(cam.yaw_degrees)
	if cam != null and "yaw_target_degrees" in cam:
		return float(cam.yaw_target_degrees)
	return 0.0
