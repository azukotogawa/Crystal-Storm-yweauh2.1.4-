extends RefCounted

const _Pad = preload("res://scripts/honest_bot/honest_progress.gd")
const _Edits = preload("res://world/terrain_edits.gd")
const _Features = preload("res://world/feature_registry.gd")
const _Pace = preload("res://scripts/honest_bot/honest_pace.gd")
const _Farm = preload("res://scripts/honest_bot/honest_farm.gd")
const _Hazard = preload("res://scripts/honest_bot/honest_hazard.gd")
const _Wall = preload("res://player/quick_wall_skill.gd")

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
var shown_drops := 0
var skill_id := ""
var _walls := -1
var walk_goal := Vector2.ZERO
var walk_armed := false
var _heal := 0
var _heal_wait := 0.0
var _cast_seen := false
var _gallery := ""
var _spend := false
var _equip_tries := 0


func begin(segment: String) -> void:
	mode = segment
	phase = "boot"
	steps = PackedStringArray()
	step_i = 0
	watch = 0.0
	mark = Vector2.ZERO
	heights = {}
	tries = 0
	slam_drops = 0
	slam_tried = false
	skill_id = ""
	_walls = -1
	walk_goal = Vector2.ZERO
	walk_armed = false
	_heal = 0
	_heal_wait = 0.0
	_cast_seen = false
	_gallery = ""
	_spend = false
	_equip_tries = 0


func tick(step: float, tree: SceneTree, player: Node, hands: RefCounted, bot: RefCounted, origin: Vector2, chapters = null) -> String:
	var dt := step
	if dt <= 0.0:
		dt = 1.0 / 60.0
	if mode == "xp_level":
		return _xp_beat(dt, tree, hands, chapters)
	if mode == "multiblock_break":
		return _multi_beat(dt, hands, chapters)
	if mode == "skill_passives":
		return _gallery_tick(dt, tree, hands, chapters, "miner_passive", _points(tree) >= 1 and not _unlocked(tree, "miner_passive"))
	if mode == "skill_quick_wall" and _points(tree) < 1 and not _unlocked(tree, "quick_wall"):
		return _gallery_tick(dt, tree, hands, chapters, "quick_wall", false)
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
		return _clear(dt, tree, player, hands, bot, origin)
	if phase == "fire":
		return _fire(tree, player, hands, origin)
	if phase == "watch":
		return _watch(dt, tree, player, hands, origin, chapters)
	if phase == "ring":
		return _ring(dt, tree, player, bot, origin)
	if phase == "turn":
		return _turn(dt, hands)
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
		steps = _wall_steps(tree) if skill_id == "quick_wall" else presses(skill_id)
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
	if mode == "skill_crystal_pulse" or mode == "skill_quick_wall":
		return "ring"
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
	if _slot_of(tree, skill_id) < 0 and _equip_tries < 2:
		_equip_tries += 1
		print("SKILL %s unslotted, pressing again" % skill_id)
		steps = presses(skill_id)
		step_i = 0
		phase = "press"
		watch = 0.0
		return ""
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


func _fire(tree: SceneTree, player: Node, hands: RefCounted, origin: Vector2) -> String:
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
	if mode == "skill_crystal_pulse":
		hands.aim_column(player, origin.x, origin.y)
	if mode == "skill_ground_slam":
		heights = _snap(_column(player))
		slam_tried = true
	if mode == "skill_quick_wall":
		if not _can_pay(player):
			print("FAIL quick_wall materials")
			return "fail"
		_walls = _walls_near(player)
	mark = _xz(player)
	if mode == "skill_dash" and _Hazard.dash_lands_in_burn(tree, mark, _yaw(player)):
		hands.set_held(PackedStringArray(["rotate_right"]))
		return ""
	if not hands.pulse("skill_%d" % [slot + 1]):
		return ""
	phase = "watch"
	watch = 0.0
	_cast_seen = false
	return ""


func _watch(dt: float, tree: SceneTree, player: Node, hands: RefCounted, origin: Vector2, chapters) -> String:
	watch += dt
	if mode == "skill_dash":
		hands.begin_tick()
		hands.set_held(PackedStringArray())
		var moved := _xz(player).distance_to(mark)
		if moved >= 3.2 and _cooled(tree, skill_id):
			_cast_seen = true
		if watch < _Pace.beat_hold("skill_unlock"):
			return ""
		if _cast_seen:
			print("OK dash slide %.2f" % moved)
			_stamp(chapters, "skill_dash")
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
		if watch < _Pace.beat_hold("skill_unlock"):
			return ""
		if _cast_seen:
			shown_drops = slam_drops
			print("OK ground_slam cells %d" % slam_drops)
			_stamp(chapters, "skill_ground_slam")
			return _begin_linger()
		if tries < 1:
			tries += 1
			phase = "walk"
			watch = 0.0
			walk_armed = false
			return ""
		print("FAIL ground_slam cells %d" % slam_drops)
		return "fail"
	if mode == "skill_quick_wall":
		var placed := _walls >= 0 and _walls_near(player) > _walls
		if placed:
			_cast_seen = true
		elif _cooled(tree, skill_id) and tries >= 3:
			_cast_seen = false
	elif _cooled(tree, skill_id):
		_cast_seen = true
	if mode == "skill_crystal_pulse":
		hands.begin_tick()
		hands.aim_column(player, origin.x, origin.y)
	if watch < _Pace.beat_hold("skill_unlock"):
		return ""
	if mode == "skill_quick_wall" and not _cast_seen and tries < 3:
		tries += 1
		phase = "turn"
		watch = 0.0
		return ""
	if _cast_seen:
		print("OK %s cast" % skill_id)
		_stamp(chapters, mode)
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


func _ring(dt: float, tree: SceneTree, player: Node, bot: RefCounted, origin: Vector2) -> String:
	var pos := _xz(player)
	if not walk_armed:
		walk_goal = _ring_goal(tree, pos, origin)
		if pos.distance_to(walk_goal) <= 1.2:
			bot.release()
			phase = "pause"
			watch = 0.0
			return ""
		walk_goal = _Hazard.skirt_goal(tree, pos, walk_goal)
		bot.set_target(walk_goal)
		walk_armed = true
		watch = 0.0
	bot.extra_held = _Hazard.with_sprint(tree, pos, walk_goal, _ratio(player), PackedStringArray(), true)
	bot.tick(pos, _yaw(player), dt)
	watch += dt
	if not bot.arrived and not bot.gave_up and watch < 16.0:
		return ""
	bot.release()
	walk_armed = false
	phase = "pause"
	watch = 0.0
	return ""


func _ring_goal(tree: SceneTree, pos: Vector2, origin: Vector2) -> Vector2:
	var away := pos - origin
	if away.length() < 0.4:
		away = Vector2(1.0, 0.0)
	var goal := origin + away.normalized() * 8.0
	if tree != null and _Hazard.burning(tree, goal):
		var safer: Vector2 = _Hazard.leave_goal(tree, goal, origin)
		if safer.distance_to(origin) >= _Farm.HEART_GAP:
			return safer
	return goal


func _turn(dt: float, hands: RefCounted) -> String:
	hands.begin_tick()
	var held := PackedStringArray()
	held.append("rotate_right")
	hands.set_held(held)
	watch += dt
	if watch < 0.4:
		return ""
	hands.set_held(PackedStringArray())
	_walls = -1
	phase = "pause"
	watch = 0.0
	return ""


func _wall_steps(tree: SceneTree) -> PackedStringArray:
	if not _slots_full(tree):
		return presses("quick_wall")
	var dash := _Pad.cell_of(&"dash")
	var wall := _Pad.cell_of(&"quick_wall")
	if dash.x < 0 or wall.x < 0 or _slot_of(tree, "dash") < 0:
		return presses("quick_wall")
	var out := PackedStringArray()
	out.append("skill_tree")
	_append_moves(out, Vector2i.ZERO, dash)
	out.append("ui_accept")
	_append_moves(out, dash, wall)
	out.append("ui_accept")
	out.append("skill_tree")
	return out


func _append_moves(out: PackedStringArray, fro: Vector2i, to: Vector2i) -> void:
	var horizontal := "ui_right" if to.x >= fro.x else "ui_left"
	for _i in absi(to.x - fro.x):
		out.append(horizontal)
	var vertical := "ui_down" if to.y >= fro.y else "ui_up"
	for _j in absi(to.y - fro.y):
		out.append(vertical)


func _slots_full(tree: SceneTree) -> bool:
	var skills = _skills(tree)
	if skills == null or not skills.has_method("slot_skill"):
		return false
	for i in 3:
		if skills.slot_skill(i) == &"":
			return false
	return true


func _can_pay(player: Node) -> bool:
	if player == null:
		return false
	var inv = player.get("inventory")
	if inv == null or not inv.has_method("count_item"):
		return false
	var stone := _Wall.reduced_count(_Wall.full_count())
	var wood := _Wall.reduced_count(_Wall.wood_full())
	return int(inv.count_item(_Wall.material_id())) >= stone or int(inv.count_item("wood")) >= wood


func _walls_near(player: Node) -> int:
	if player == null:
		return 0
	var center := _column(player)
	var count := 0
	for dz in range(-5, 6):
		for dx in range(-5, 6):
			var feat: Dictionary = _Features.get_feature(center.x + dx, center.y + dz)
			if str(feat.get("build_id", "")) == "stone_wall":
				count += 1
	return count


func _stamp(chapters, feature: String) -> void:
	var clock := ""
	if chapters != null and chapters.has_method("format_clock"):
		clock = " " + str(chapters.format_clock())
	print("SHOWCASE STAMP %s%s" % [feature, clock])


func _clear(dt: float, tree: SceneTree, player: Node, hands: RefCounted, bot: RefCounted, origin: Vector2) -> String:
	_heal_wait = maxf(_heal_wait - dt, 0.0)
	var pos := _xz(player)
	if mode == "skill_dash" and pos.distance_to(origin) >= 18.0:
		bot.release()
		walk_armed = false
		phase = "fire"
		watch = 0.0
		return ""
	if not walk_armed and pos.distance_to(origin) >= 18.0 and tries == 0:
		bot.release()
		phase = "fire"
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
		walk_goal = _Hazard.skirt_goal(tree, pos, walk_goal)
		bot.set_target(walk_goal)
		walk_armed = true
		watch = 0.0
	bot.extra_held = _Hazard.with_sprint(tree, pos, walk_goal, _ratio(player), PackedStringArray(), true)
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


func _xp_beat(dt: float, tree: SceneTree, hands: RefCounted, chapters) -> String:
	if phase == "boot":
		var result := _xp(tree)
		if result != "pass":
			return result
		phase = "sheet"
		watch = 0.0
		return ""
	if phase == "sheet":
		hands.begin_tick()
		hands.set_held(PackedStringArray())
		if not hands.pulse("skill_tree"):
			return ""
		_stamp(chapters, "xp_level")
		phase = "sheet_hold"
		watch = 0.0
		return ""
	if phase == "sheet_hold":
		hands.begin_tick()
		hands.set_held(PackedStringArray())
		watch += dt
		if watch < _Pace.beat_hold("level_up"):
			return ""
		phase = "sheet_close"
		watch = 0.0
		return ""
	if phase == "sheet_close":
		hands.begin_tick()
		if not hands.pulse("skill_tree"):
			return ""
		phase = "linger"
		watch = 0.0
		return ""
	return _linger(dt)


func _multi_beat(dt: float, hands: RefCounted, chapters) -> String:
	hands.begin_tick()
	hands.set_held(PackedStringArray())
	if phase == "boot":
		if shown_drops < 2:
			print("FAIL multiblock cells %d" % shown_drops)
			return "fail"
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
		print("OK multiblock cells %d" % shown_drops)
		_stamp(chapters, "multiblock_break")
		return _begin_linger()
	return _linger(dt)


func _gallery_tick(dt: float, tree: SceneTree, hands: RefCounted, chapters, skill_name: String, spend: bool) -> String:
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
		if watch < _Pace.beat_hold("skill_unlock"):
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
			_stamp(chapters, "skill_passives")
			return "pass"
		_stamp(chapters, "skill_passives")
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
	var total := _Farm.earned(level, amount)
	print("LEVEL %d xp %d earned %d" % [level, amount, total])
	if _Farm.ready(level, amount):
		return "pass"
	print("FAIL xp level %d earned %d" % [level, total])
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
