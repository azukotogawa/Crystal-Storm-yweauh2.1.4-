extends RefCounted

const _Build = preload("res://scripts/honest_bot/honest_build.gd")
const _Hands = preload("res://scripts/honest_bot/honest_input.gd")
const _Bot = preload("res://scripts/honest_bot/honest_play_bot.gd")
const _GI = preload("res://helpers/gameplay_input.gd")
const _Worlds = preload("res://systems/world_manager.gd")
const _Edits = preload("res://world/terrain_edits.gd")

const MAIN_SCENE := "res://scenes/main.tscn"
const SEED := 12349
const STEP := 1.0 / 60.0
const BOOT_FRAMES := 2400
const DIG_FRAMES := 4200
const BUILD_FRAMES := 7200

const OPENING_BANNER := "Watch the purple front — dig trenches & walls where it advances"
const WALL_BANNER := "Wall raised — crystal slows here; it will find another way"


func play(tree: SceneTree, scenario: String) -> int:
	var name := scenario.strip_edges()
	if name == "break":
		return _break(tree)
	if name != "dig" and name != "build":
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
	bot.objective = "dig one column" if name == "dig" else "place one stone wall"
	var before := _snap(tree, player)
	var build = _Build.new()
	var hands = _Hands.new()
	build.reset("dig_tool" if name == "dig" else "structure_place")
	var cap := DIG_FRAMES if name == "dig" else BUILD_FRAMES
	var result := ""
	var frames := 0
	while frames < cap:
		var delta := _delta(tree)
		result = build.tick(delta, tree, player, hands, null)
		_note_banner(tree, seen)
		if result == "fail":
			return _give_up(bot, player, "play returned fail")
		if name == "dig" and result == "pass":
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


func _boot(tree: SceneTree, scenario: String, seen: PackedStringArray):
	_Worlds.pending_launch = {
		"id": "harness-%s" % scenario,
		"seed": SEED,
		"name": "Harness",
	}
	_Worlds.pending_resume = false
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
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
		print("FAIL harness start region not ready")
		return null
	for _w in 120:
		await tree.process_frame
		_note_banner(tree, seen)
		if not _GI.blocks_actions():
			break
	if _GI.blocks_actions():
		print("FAIL harness actions still blocked")
		return null
	var player = tree.get_first_node_in_group("player")
	if player == null or not bool(player.get("world_ready")):
		print("FAIL harness player not world_ready")
		return null
	var world = game.get_node_or_null("World")
	var seeded := int(world.world_seed) if world != null and "world_seed" in world else -1
	if seeded != SEED:
		print("FAIL harness seed %d want %d" % [seeded, SEED])
		return null
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
	if name == "dig":
		if int(after.get("stone", 0)) <= int(before.get("stone", 0)):
			return "stone did not increase"
		if float(after.get("drop", 0.0)) < 0.01:
			return "height drop missing"
		return ""
	if int(after.get("walls", 0)) < 1:
		return "stone wall missing"
	if int(after.get("stone", 0)) >= int(before.get("stone", 0)):
		return "stone was not spent"
	for line in seen:
		if line == OPENING_BANNER or line == WALL_BANNER:
			continue
		if line.begins_with("Gate ") or line.begins_with("Bridge ") or line.begins_with("Trench "):
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
	if name == "dig":
		var cell: Vector2i = build._dropped()
		if cell.x >= 900000:
			return
		var was := float(build.heights.get(cell, _Edits.get_height_delta(cell.x, cell.y)))
		after["drop"] = was - _Edits.get_height_delta(cell.x, cell.y)
		return
	after["walls"] = int(build._new_tiles())


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
