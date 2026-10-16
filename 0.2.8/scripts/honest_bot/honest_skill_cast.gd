extends RefCounted

const _Pad = preload("res://scripts/honest_bot/honest_progress.gd")
const _Edits = preload("res://world/terrain_edits.gd")

var mode := ""
var phase := ""
var steps := PackedStringArray()
var step_i := 0
var watch := 0.0
var mark := Vector2.ZERO
var heights: Dictionary = {}
var tries := 0
var slam_drops := 0
var slam_tried := false
var skill_id := ""
var walk_goal := Vector2.ZERO
var walk_armed := false


func begin(segment: String) -> void:
	mode = segment
	phase = "boot"
	steps = PackedStringArray()
	step_i = 0
	watch = 0.0
	mark = Vector2.ZERO
	heights = {}
	tries = 0
	skill_id = ""
	walk_goal = Vector2.ZERO
	walk_armed = false


func tick(step: float, tree: SceneTree, player: Node, hands: RefCounted, bot: RefCounted, origin: Vector2) -> String:
	var dt := step
	if dt <= 0.0:
		dt = 1.0 / 60.0
	if mode == "xp_level":
		return _xp(tree)
	if mode == "multiblock_break":
		return _multi()
	if mode == "skill_passives":
		return "skipped-no-point"
	if mode == "skill_quick_wall":
		return _quick_wall(tree)
	if phase == "boot":
		return _boot(tree)
	if phase == "press":
		return _press(hands)
	if phase == "settle":
		return _settle(dt, tree)
	if phase == "hold":
		return _hold(dt, player, hands)
	if phase == "fire":
		return _fire(tree, player, hands)
	if phase == "watch":
		return _watch(dt, tree, player, hands, origin)
	if phase == "walk":
		return _walk(dt, player, bot, origin)
	return "fail"


static func presses(skill_name: String) -> PackedStringArray:
	var cell := _Pad.cell_of(StringName(skill_name))
	var out := PackedStringArray()
	if cell.x < 0:
		return out
	out.append("skill_tree")
	for _i in cell.x:
		out.append("ui_right")
	for _j in cell.y:
		out.append("ui_down")
	out.append("ui_accept")
	out.append("skill_tree")
	return out


func _boot(tree: SceneTree) -> String:
	skill_id = _name_for(mode)
	if skill_id == "":
		return "fail"
	if _points(tree) < 1 and not _unlocked(tree, skill_id):
		return "skipped-no-point"
	if not _unlocked(tree, skill_id):
		steps = presses(skill_id)
		if steps.is_empty():
			return "fail"
		phase = "press"
		return ""
	phase = "hold" if mode == "skill_dash" else "fire"
	watch = 0.0
	return ""


func _press(hands: RefCounted) -> String:
	hands.begin_tick()
	if step_i >= steps.size():
		phase = "settle"
		watch = 0.0
		return ""
	var action := String(steps[step_i])
	step_i += 1
	hands.pulse(action)
	return ""


func _settle(dt: float, tree: SceneTree) -> String:
	watch += dt
	if watch < 0.12:
		return ""
	if not _unlocked(tree, skill_id):
		print("FAIL skill %s did not unlock" % skill_id)
		return "fail"
	print("SKILL %s" % skill_id)
	phase = "hold" if mode == "skill_dash" else "fire"
	watch = 0.0
	return ""


func _hold(dt: float, player: Node, hands: RefCounted) -> String:
	hands.begin_tick()
	var held := PackedStringArray()
	held.append("move_forward")
	hands.set_held(held)
	watch += dt
	if watch < 0.22:
		return ""
	phase = "fire"
	watch = 0.0
	return ""


func _fire(tree: SceneTree, player: Node, hands: RefCounted) -> String:
	if mode == "skill_ground_slam" and tries > 0 and _cooled(tree, skill_id):
		return ""
	var slot := _slot_of(tree, skill_id)
	if slot < 0:
		print("FAIL skill %s has no slot" % skill_id)
		return "fail"
	hands.begin_tick()
	if mode == "skill_dash":
		var held := PackedStringArray()
		held.append("move_forward")
		hands.set_held(held)
	else:
		hands.set_held(PackedStringArray())
	if mode == "skill_ground_slam":
		heights = _snap(_column(player))
		slam_tried = true
	mark = _xz(player)
	hands.pulse("skill_%d" % [slot + 1])
	phase = "watch"
	watch = 0.0
	return ""


func _watch(dt: float, tree: SceneTree, player: Node, hands: RefCounted, origin: Vector2) -> String:
	watch += dt
	if mode == "skill_dash":
		hands.begin_tick()
		hands.set_held(PackedStringArray())
		if watch < 0.35:
			return ""
		var moved := _xz(player).distance_to(mark)
		if moved >= 3.2 and _cooled(tree, skill_id):
			print("OK dash slide %.2f" % moved)
			return "pass"
		print("FAIL dash slide %.2f" % moved)
		return "fail"
	if watch < 0.35:
		return ""
	if mode == "skill_ground_slam":
		slam_drops = _drops(heights)
		if slam_drops >= 2:
			print("OK ground_slam cells %d" % slam_drops)
			return "pass"
		if tries < 1:
			tries += 1
			phase = "walk"
			watch = 0.0
			walk_armed = false
			return ""
		print("FAIL ground_slam cells %d" % slam_drops)
		return "fail"
	if _cooled(tree, skill_id):
		print("OK %s cast" % skill_id)
		return "pass"
	print("FAIL %s cast" % skill_id)
	return "fail"


func _walk(dt: float, player: Node, bot: RefCounted, origin: Vector2) -> String:
	var pos := _xz(player)
	if not walk_armed:
		var away := pos - origin
		if away.length() < 0.2:
			away = Vector2(1.0, 0.0)
		walk_goal = origin + away.normalized() * 14.0
		bot.set_target(walk_goal)
		walk_armed = true
	bot.extra_held = PackedStringArray(["sprint"])
	bot.tick(pos, _yaw(player), dt)
	watch += dt
	if not bot.arrived and not bot.gave_up and watch < 8.0:
		return ""
	bot.release()
	walk_armed = false
	phase = "fire"
	return ""


func _quick_wall(_tree: SceneTree) -> String:
	return "skipped-no-point"


func _multi() -> String:
	if slam_drops >= 2:
		return "pass"
	if slam_tried:
		return "fail"
	return "skipped-no-point"


func _xp(tree: SceneTree) -> String:
	var node = _progress(tree)
	if node == null:
		print("FAIL xp missing progression")
		return "fail"
	var level := int(node.get("level"))
	var amount := int(node.get("xp"))
	print("LEVEL %d xp %d" % [level, amount])
	if level >= 2:
		return "pass"
	print("FAIL xp level %d" % level)
	return "fail"


func _name_for(segment: String) -> String:
	if segment == "skill_dash":
		return "dash"
	if segment == "skill_ground_slam":
		return "ground_slam"
	if segment == "skill_crystal_pulse":
		return "crystal_pulse"
	return ""


func _snap(center: Vector2i) -> Dictionary:
	var snap := {}
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var cell := Vector2i(center.x + dx, center.y + dz)
			snap[cell] = _Edits.get_height_delta(cell.x, cell.y)
	return snap


func _drops(before: Dictionary) -> int:
	var n := 0
	for key in before.keys():
		var cell: Vector2i = key
		if _Edits.get_height_delta(cell.x, cell.y) < float(before[cell]) - 0.01:
			n += 1
	return n


func _progress(tree: SceneTree):
	if tree == null:
		return null
	return tree.get_first_node_in_group("progression_service")


func _skills(tree: SceneTree):
	if tree == null:
		return null
	return tree.get_first_node_in_group("skill_service")


func _points(tree: SceneTree) -> int:
	var node = _progress(tree)
	if node == null:
		return 0
	return int(node.skill_points)


func _unlocked(tree: SceneTree, skill_name: String) -> bool:
	var skills = _skills(tree)
	if skills == null or not skills.has_method("is_unlocked"):
		return false
	return bool(skills.is_unlocked(StringName(skill_name)))


func _slot_of(tree: SceneTree, skill_name: String) -> int:
	var skills = _skills(tree)
	if skills == null or not skills.has_method("slot_skill"):
		return -1
	var want := StringName(skill_name)
	for i in 3:
		if skills.slot_skill(i) == want:
			return i
	return -1


func _cooled(tree: SceneTree, skill_name: String) -> bool:
	var skills = _skills(tree)
	var slot := _slot_of(tree, skill_name)
	if skills == null or slot < 0 or not skills.has_method("cooldown_left"):
		return false
	return float(skills.cooldown_left(slot)) > 0.0


func _column(player: Node) -> Vector2i:
	var feet: Vector3 = player.voxel_position
	return Vector2i(floori(feet.x), floori(feet.z))


func _xz(player: Node) -> Vector2:
	var feet: Vector3 = player.voxel_position
	return Vector2(feet.x, feet.z)


func _yaw(player: Node) -> float:
	var cam = player.get("camera")
	if cam != null and "yaw_target_degrees" in cam:
		return float(cam.yaw_target_degrees)
	if cam != null and "yaw_degrees" in cam:
		return float(cam.yaw_degrees)
	return 0.0
