extends RefCounted

const _Pad = preload("res://scripts/honest_bot/honest_progress.gd")
const _Edits = preload("res://world/terrain_edits.gd")
const _Pace = preload("res://scripts/honest_bot/honest_pace.gd")

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
var _heal := 0
var _heal_wait := 0.0
var _cast_seen := false
var _gallery := ""
var _spend := false


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
	_heal = 0
	_heal_wait = 0.0
	_cast_seen = false
	_gallery = ""
	_spend = false


func tick(step: float, tree: SceneTree, player: Node, hands: RefCounted, bot: RefCounted, origin: Vector2) -> String:
	var dt := step
	if dt <= 0.0:
		dt = 1.0 / 60.0
	if mode == "xp_level":
		return _xp_beat(dt, tree)
	if mode == "multiblock_break":
		return _multi_beat(dt, hands)
	if mode == "skill_passives":
		return _gallery_tick(dt, tree, hands, "miner_passive", _points(tree) >= 1 and not _unlocked(tree, "miner_passive"))
	if mode == "skill_quick_wall" and _points(tree) < 1 and not _unlocked(tree, "quick_wall"):
		return _gallery_tick(dt, tree, hands, "quick_wall", false)
	if phase == "boot":
		return _boot(tree)
	if phase == "press":
		return _press(dt, hands)
	if phase == "settle":
		return _settle(dt, tree)
	if phase == "pause":
		return _pause(dt, hands)
	if phase == "hold":
		return _hold(dt, player, hands)
	if phase == "clear":
		return _clear(dt, player, hands, bot, origin)
	if phase == "fire":
		return _fire(tree, player, hands)
	if phase == "watch":
		return _watch(dt, tree, player, hands, origin)
	if phase == "linger":
		return _linger(dt)
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
	phase = _armed_phase()
	watch = 0.0
	return ""


func _armed_phase() -> String:
	if mode == "skill_dash" or mode == "skill_ground_slam":
		return "clear"
	return "fire"


func _press(dt: float, hands: RefCounted) -> String:
	hands.begin_tick()
	if step_i >= steps.size():
		phase = "settle"
		watch = 0.0
		return ""
	var action := String(steps[step_i])
	if action == "ui_accept" and watch < _Pace.PRE_PAUSE:
		hands.set_held(PackedStringArray())
		watch += dt
		return ""
	if not hands.pulse(action):
		return ""
	step_i += 1
	if action == "ui_accept":
		watch = 0.0
	return ""


func _settle(dt: float, tree: SceneTree) -> String:
	watch += dt
	if watch < 0.12:
		return ""
	if not _unlocked(tree, skill_id):
		print("FAIL skill %s did not unlock" % skill_id)
		return "fail"
	print("SKILL %s" % skill_id)
	phase = "pause"
	watch = 0.0
	return ""


func _pause(dt: float, hands: RefCounted) -> String:
	hands.begin_tick()
	hands.set_held(PackedStringArray())
	watch += dt
	if watch < _Pace.PRE_PAUSE:
		return ""
	phase = _armed_phase()
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
	if not hands.pulse("skill_%d" % [slot + 1]):
		return ""
	phase = "watch"
	watch = 0.0
	_cast_seen = false
	return ""


func _watch(dt: float, tree: SceneTree, player: Node, hands: RefCounted, origin: Vector2) -> String:
	watch += dt
	if mode == "skill_dash":
		hands.begin_tick()
		hands.set_held(PackedStringArray())
		var moved := _xz(player).distance_to(mark)
		if moved >= 3.2 and _cooled(tree, skill_id):
			_cast_seen = true
		if watch < _Pace.RESULT_HOLD:
			return ""
		if _cast_seen:
			print("OK dash slide %.2f" % moved)
			return _begin_linger()
		if tries < 1:
			tries += 1
			walk_armed = false
			phase = "clear"
			watch = 0.0
			return ""
		print("FAIL dash slide %.2f" % moved)
		return "fail"
	if mode == "skill_ground_slam":
		slam_drops = _drops(heights)
		if slam_drops >= 2:
			_cast_seen = true
		if watch < _Pace.RESULT_HOLD:
			return ""
		if _cast_seen:
			print("OK ground_slam cells %d" % slam_drops)
			return _begin_linger()
		if tries < 1:
			tries += 1
			phase = "walk"
			watch = 0.0
			walk_armed = false
			return ""
		print("FAIL ground_slam cells %d" % slam_drops)
		return "fail"
	if _cooled(tree, skill_id):
		_cast_seen = true
	if watch < _Pace.RESULT_HOLD:
		return ""
	if _cast_seen:
		print("OK %s cast" % skill_id)
		return _begin_linger()
	print("FAIL %s cast" % skill_id)
	return "fail"


func _begin_linger() -> String:
	phase = "linger"
	watch = 0.0
	return ""


func _linger(dt: float) -> String:
	watch += dt
	if watch < _Pace.SETTLE:
		return ""
	return "pass"


func _clear(dt: float, player: Node, hands: RefCounted, bot: RefCounted, origin: Vector2) -> String:
	_heal_wait = maxf(_heal_wait - dt, 0.0)
	var pos := _xz(player)
	if not walk_armed and pos.distance_to(origin) >= 18.0 and tries == 0:
		bot.release()
		phase = "pause"
		watch = 0.0
		return ""
	if _heal_wait <= 0.0 and _ratio(player) < 0.82 and _herbs(player) > 0:
		_heal_cast(hands)
		return ""
	if not walk_armed:
		var away := pos - origin
		if away.length() < 0.4:
			away = Vector2(1.0, 1.0)
		away = away.normalized()
		if tries > 0:
			away = Vector2(-away.y, away.x)
			walk_goal = pos + away * 10.0
		else:
			walk_goal = origin + away * 24.0
		bot.set_target(walk_goal)
		walk_armed = true
		watch = 0.0
	bot.extra_held = PackedStringArray(["sprint"])
	bot.tick(pos, _yaw(player), dt)
	watch += dt
	if not bot.arrived and not bot.gave_up and watch < 12.0:
		return ""
	bot.release()
	walk_armed = false
	phase = "pause"
	watch = 0.0
	return ""


func _heal_cast(hands: RefCounted) -> void:
	hands.begin_tick()
	if _heal == 0:
		if hands.pulse("hotbar_6"):
			_heal = 1
		return
	if not hands.pulse("build_place"):
		return
	_heal = 0
	_heal_wait = 0.5
	print("SHOWCASE herb")


func _ratio(player: Node) -> float:
	if player == null:
		return 1.0
	return clampf(float(player.health) / maxf(float(player.max_health), 1.0), 0.0, 1.0)


func _herbs(player: Node) -> int:
	if player == null:
		return 0
	var inv = player.get("inventory")
	if inv == null or not inv.has_method("count_item"):
		return 0
	return int(inv.count_item("herb"))


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
	phase = "pause"
	watch = 0.0
	return ""


func _xp_beat(dt: float, tree: SceneTree) -> String:
	if phase == "boot":
		var result := _xp(tree)
		if result != "pass":
			return result
		phase = "result"
		watch = 0.0
		return ""
	watch += dt
	if phase == "result":
		if watch < _Pace.RESULT_HOLD:
			return ""
		phase = "linger"
		watch = 0.0
		return ""
	return _linger(dt)


func _multi_beat(dt: float, hands: RefCounted) -> String:
	hands.begin_tick()
	hands.set_held(PackedStringArray())
	if phase == "boot":
		if slam_drops < 2:
			if slam_tried:
				return "fail"
			return "skipped-no-point"
		phase = "pause"
		watch = 0.0
		return ""
	watch += dt
	if phase == "pause":
		if watch < _Pace.PRE_PAUSE:
			return ""
		phase = "result"
		watch = 0.0
		return ""
	if phase == "result":
		if watch < _Pace.RESULT_HOLD:
			return ""
		print("OK multiblock cells %d" % slam_drops)
		return _begin_linger()
	return _linger(dt)


func _gallery_tick(dt: float, tree: SceneTree, hands: RefCounted, skill_name: String, spend: bool) -> String:
	if _gallery == "":
		_gallery = skill_name
		_spend = spend
		skill_id = skill_name
		steps = _tour(skill_name, spend)
		step_i = 0
		phase = "press"
		watch = 0.0
		if steps.is_empty():
			return "fail"
	if phase == "press":
		var pressed := _press(dt, hands)
		if pressed != "":
			return pressed
		if phase == "settle":
			phase = "pause"
			watch = 0.0
		return ""
	hands.begin_tick()
	hands.set_held(PackedStringArray())
	watch += dt
	if phase == "pause":
		if watch < _Pace.PRE_PAUSE:
			return ""
		phase = "result"
		watch = 0.0
		return ""
	if phase == "result":
		if watch < _Pace.RESULT_HOLD:
			return ""
		if step_i >= steps.size():
			phase = "close"
			watch = 0.0
		return ""
	if phase == "close":
		if not hands.pulse("skill_tree"):
			return ""
		phase = "linger"
		watch = 0.0
		return ""
	if phase == "linger":
		if watch < _Pace.SETTLE:
			return ""
		if _spend:
			if not _unlocked(tree, skill_id):
				print("FAIL skill %s did not unlock" % skill_id)
				return "fail"
			print("SKILL %s" % skill_id)
			return "pass"
		return "skipped-no-point"
	return "fail"


func _tour(skill_name: String, spend: bool) -> PackedStringArray:
	var raw := presses(skill_name)
	var out := PackedStringArray()
	for action in raw:
		if not spend and action == "ui_accept":
			continue
		out.append(action)
	if out.size() >= 2 and out[out.size() - 1] == "skill_tree":
		out.remove_at(out.size() - 1)
	return out


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
	if segment == "skill_quick_wall":
		return "quick_wall"
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
