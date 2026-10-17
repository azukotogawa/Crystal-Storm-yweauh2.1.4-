extends RefCounted

const _Nav = preload("res://scripts/honest_bot/honest_nav.gd")
const _Edits = preload("res://world/terrain_edits.gd")
const _Features = preload("res://world/feature_registry.gd")
const _Blueprints = preload("res://helpers/structure_blueprints.gd")
const _Pace = preload("res://scripts/honest_bot/honest_pace.gd")

const OFFSETS: Array[Vector2i] = [
	Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2),
	Vector2i(3, 1), Vector2i(-3, 1), Vector2i(1, 3), Vector2i(1, -3),
	Vector2i(4, 0), Vector2i(0, 4), Vector2i(-4, 2), Vector2i(2, -4),
]
const DIG_LIMIT := 48.0
const PLACE_LIMIT := 130.0
const CRYSTAL_SKIP := 0.05

var chapter_label := ""
var hands: RefCounted
var player: Node
var chapters: RefCounted
var tree: SceneTree
var mode := ""
var beat := 0
var age := 0.0
var tries := 0
var aim := Vector2i(999999, 999999)
var heights: Dictionary = {}
var tiles: Dictionary = {}
var shown: Dictionary = {}
var show_id := ""
var show_age := 0.0
var piece_before := 0
var marked := ""
var spin := 0
var step_dt := 0.0
var miss_age := 0.0


func reset(segment: String) -> void:
	mode = segment
	beat = 0
	age = 0.0
	tries = 0
	aim = Vector2i(999999, 999999)
	heights = {}
	tiles = {}
	shown = {}
	show_id = ""
	show_age = 0.0
	miss_age = 0.0
	piece_before = 0
	marked = ""
	spin = 0
	chapter_label = segment


func tick(step: float, host: SceneTree, body: Node, pad: RefCounted, log: RefCounted) -> String:
	tree = host
	player = body
	hands = pad
	chapters = log
	if hands != null and hands.has_method("begin_tick"):
		hands.begin_tick()
	var dt := step
	if dt <= 0.0:
		dt = 1.0 / 60.0
	age += dt
	step_dt = dt
	if player == null or hands == null:
		print("FAIL %s missing player" % mode)
		return "fail"
	if mode == "dig_tool":
		return _dig()
	if mode == "structure_place":
		return _place(dt)
	return "fail"


func _dig() -> String:
	if age > DIG_LIMIT:
		print("FAIL dig_tool no height drop")
		return "fail"
	chapter_label = "dig_tool"
	if beat == 0:
		if not hands.pulse("hotbar_2"):
			return ""
		beat = 1
		return ""
	if beat == 1:
		aim = _dry_near()
		if aim.x > 900000:
			hands.set_held(_exit_crystal_held())
			show_age += step_dt
			if show_age < 1.4:
				return ""
			show_age = 0.0
			tries += 1
			if tries > 6:
				print("FAIL dig_tool no dry cell")
				return "fail"
			return ""
		tries = 0
		_look_at(aim)
		beat = 2
		show_age = 0.0
		return ""
	if beat == 2:
		if _spinning(aim) and age < 2.4:
			_look_at(aim)
			return ""
		_stop_move()
		_look_at(aim)
		show_age = 0.0
		beat = 3
		return ""
	if beat == 3:
		_look_at(aim)
		show_age += step_dt
		if show_age < _Pace.PRE_PAUSE:
			return ""
		if not _column_aimed(aim):
			if show_age < _Pace.PRE_PAUSE + 1.4:
				return ""
			tries += 1
			if tries >= 8:
				print("FAIL dig_tool cursor %s aim %s" % [_cursor_cell(), aim])
				return "fail"
			beat = 1
			show_age = 0.0
			return ""
		heights = _height_snap()
		_look_at(aim, PackedStringArray(["attack"]))
		show_age = 0.0
		beat = 4
		return ""
	if beat == 4:
		_look_at(aim, PackedStringArray(["attack"]))
		show_age += step_dt
		var dug := _dropped()
		if dug.x >= 900000:
			if show_age < maxf(0.5, _Pace.action_span("multi_block_break") + 0.15):
				return ""
			_stop_move()
			tries += 1
			if tries >= OFFSETS.size():
				print("FAIL dig_tool swings missed")
				return "fail"
			aim = _dry_near()
			age = minf(age, DIG_LIMIT - 1.0)
			beat = 1
			show_age = 0.0
			return ""
		_stop_move()
		show_age = 0.0
		beat = 5
		return ""
	if beat == 5:
		_look_at(aim)
		var dug_hold := _dropped()
		show_age += step_dt
		if show_age < _Pace.RESULT_HOLD:
			return ""
		print("SHOWCASE dig column %d %d" % [dug_hold.x, dug_hold.y])
		show_age = 0.0
		beat = 6
		return ""
	_look_at(aim)
	show_age += step_dt
	if show_age < _Pace.SETTLE:
		return ""
	return "pass"


func _column_aimed(cell: Vector2i) -> bool:
	if player == null:
		return false
	var hl = player.get_node_or_null("TargetHighlight")
	if hl == null or not hl.has_method("get_action_column"):
		return true
	var shared: Vector3 = hl.get_action_column()
	if shared == Vector3.ZERO:
		return true
	return floori(shared.x) == cell.x and floori(shared.z) == cell.y


func _place(dt: float) -> String:
	if age > PLACE_LIMIT:
		print("FAIL structure_place timed out at beat %d" % beat)
		return "fail"
	if beat < 10:
		return _single_wall()
	if beat < 20:
		return _show_types(dt)
	return _craft_segment()


func _single_wall() -> String:
	chapter_label = "structure_stone_wall"
	if not _mark("structure_stone_wall"):
		return ""
	if beat == 0:
		if not hands.pulse("hotbar_5"):
			return ""
		beat = 1
		return ""
	if beat == 1:
		var weapon := _weapon()
		if weapon != null and str(weapon.get_place_id()) == "stone_wall":
			beat = 2
			show_age = 0.0
			return ""
		if tries > 8:
			print("FAIL structure place cycle missed stone_wall")
			return "fail"
		if not hands.pulse("place_cycle"):
			return ""
		tries += 1
		return ""
	if beat == 2:
		tries = 0
		spin = 0
		aim = _free_cell(0)
		_look_at(aim)
		beat = 3
		show_age = 0.0
		return ""
	if beat == 3:
		if _spinning(aim) and spin < 120:
			_look_at(aim)
			spin += 1
			return ""
		_stop_move()
		_look_at(aim)
		show_age += step_dt
		if show_age < _Pace.PRE_PAUSE:
			return ""
		tiles = _tile_snap()
		if not hands.pulse("build_place"):
			return ""
		show_age = 0.0
		beat = 4
		return ""
	if beat == 4:
		_look_at(aim)
		if _new_tiles() != 1:
			miss_age += step_dt
			if miss_age < _place_wind():
				return ""
			miss_age = 0.0
			tries += 1
			if tries > OFFSETS.size():
				print("FAIL structure stone_wall did not place")
				return "fail"
			aim = _free_cell(tries)
			tiles = _tile_snap()
			spin = 0
			show_age = _Pace.PRE_PAUSE
			beat = 3
			return ""
		miss_age = 0.0
		show_age += step_dt
		if show_age < _Pace.RESULT_HOLD:
			return ""
		print("SHOWCASE structure stone_wall placed")
		show_age = 0.0
		beat = 5
		return ""
	_look_at(aim)
	show_age += step_dt
	if show_age < _Pace.SETTLE:
		return ""
	beat = 10
	tries = 0
	show_id = ""
	show_age = 0.0
	return ""


func _show_types(dt: float) -> String:
	var ids := _Blueprints.ids()
	if shown.size() >= ids.size():
		beat = 20
		tries = 0
		show_age = 0.0
		return ""
	var want := String(ids[shown.size()])
	chapter_label = "structure_%s" % want
	if not _mark(chapter_label):
		return ""
	aim = _free_cell(4)
	_look_at(aim)
	if beat == 10:
		show_age += dt
		if show_age < _Pace.PRE_PAUSE:
			return ""
		beat = 11
		return ""
	var id := ""
	var weapon := _weapon()
	if weapon != null and weapon.has_method("selected_blueprint_id"):
		id = String(weapon.selected_blueprint_id())
	if beat == 11:
		if id == want and _ghost_count() > 0:
			show_age = 0.0
			beat = 12
			return ""
		if not hands.pulse_key(KEY_X):
			return ""
		tries += 1
		if tries > ids.size() * 4:
			print("FAIL structure ghost missing %s" % want)
			return "fail"
		return ""
	if beat == 12:
		show_age += dt
		if show_age < _Pace.RESULT_HOLD:
			return ""
		show_age = 0.0
		beat = 13
		return ""
	show_age += dt
	if show_age < _Pace.SETTLE:
		return ""
	shown[want] = true
	print("SHOWCASE structure %s shown" % want)
	beat = 10
	tries = 0
	show_age = 0.0
	return ""


func _craft_segment() -> String:
	chapter_label = "structure_place"
	if not _mark("structure_place"):
		return ""
	if beat == 20:
		var button := _craft_button()
		if button != null and button.is_visible_in_tree():
			beat = 21
			show_age = 0.0
			return ""
		if tries > 90:
			print("FAIL structure craft button missing")
			return "fail"
		if tries % 15 == 0 and not hands.pulse("inventory_toggle"):
			return ""
		tries += 1
		return ""
	if beat == 21:
		var button := _craft_button()
		if button == null or button.disabled:
			print("FAIL structure craft button blocked")
			return "fail"
		var rect := button.get_global_rect()
		if rect.size.x < 4.0:
			tries += 1
			if tries > 120:
				print("FAIL structure craft button has no size")
				return "fail"
			return ""
		if show_age < _Pace.PRE_PAUSE:
			show_age += step_dt
			return ""
		piece_before = _piece_count()
		if not hands.click_at(button, rect.position + rect.size * 0.5, true):
			return ""
		show_age = 0.0
		beat = 22
		return ""
	if beat == 22:
		var button := _craft_button()
		if button != null:
			var rect := button.get_global_rect()
			if not hands.click_at(button, rect.position + rect.size * 0.5, false):
				return ""
		if _piece_count() > piece_before:
			tries = 0
			show_age = 0.0
			beat = 23
			return ""
		tries += 1
		if tries > 4:
			print("FAIL structure craft did not land")
			return "fail"
		beat = 21
		return ""
	if beat == 23:
		var button := _craft_button()
		if show_age < _Pace.RESULT_HOLD:
			show_age += step_dt
			return ""
		if button != null and button.is_visible_in_tree():
			if not hands.pulse("inventory_toggle"):
				return ""
			return ""
		var slot := _piece_slot()
		if slot < 0:
			print("FAIL structure piece not on the hotbar")
			return "fail"
		if not hands.pulse("hotbar_%d" % (slot + 1)):
			return ""
		tries = 0
		spin = 0
		show_age = 0.0
		beat = 24
		return ""
	if beat == 24:
		if not _piece_selected():
			var slot := _piece_slot()
			if slot < 0:
				print("FAIL structure piece left the hotbar")
				return "fail"
			if not hands.pulse("hotbar_%d" % (slot + 1)):
				return ""
			return ""
		if aim.x > 900000 or not _open_ground(aim):
			aim = _free_cell(tries)
			spin = 0
			show_age = 0.0
		_look_at(aim)
		var got := _cursor_cell()
		if got != aim or not _segment_ready(aim):
			spin += 1
			if spin < 90:
				return ""
			spin = 0
			tries += 1
			if tries > 12:
				print("FAIL structure wall_segment cursor %s reason %s" % [got, _place_reason()])
				return "fail"
			aim = _free_cell(tries)
			show_age = 0.0
			return ""
		if show_age < _Pace.PRE_PAUSE:
			show_age += step_dt
			return ""
		tiles = _tile_snap()
		if not hands.pulse("build_place"):
			return ""
		show_age = 0.0
		beat = 25
		return ""
	if _new_tiles() >= 3:
		if show_age < _Pace.RESULT_HOLD + _Pace.SETTLE:
			show_age += step_dt
			_look_at(_cursor_cell())
			return ""
		print("SHOWCASE structure wall_segment placed")
		return "pass"
	if show_age < _place_wind():
		show_age += step_dt
		_look_at(_cursor_cell())
		return ""
	tries += 1
	if tries > 8:
		print("FAIL structure wall_segment tiles %d piece %d reason %s" % [_new_tiles(), _piece_count(), _place_reason()])
		return "fail"
	print("SHOWCASE structure place miss tiles %d reason %s" % [_new_tiles(), _place_reason()])
	aim = _free_cell(tries)
	spin = 0
	beat = 24
	return ""


func _mark(feature: String) -> bool:
	if marked == feature:
		return true
	if chapters != null and chapters.has_method("open"):
		if not bool(chapters.open(feature)):
			return false
	marked = feature
	return true


func _weapon() -> Node:
	if player == null:
		return null
	return player.get_node_or_null("WeaponController")


func _craft_button() -> Button:
	if tree == null:
		return null
	return tree.root.find_child("Craft_wall_segment", true, false) as Button


func _piece_count() -> int:
	if player == null or player.inventory == null:
		return 0
	return int(player.inventory.count_item("wall_segment"))


func _piece_selected() -> bool:
	var weapon := _weapon()
	if weapon == null or not weapon.has_method("active_blueprint_id"):
		return false
	return weapon.active_blueprint_id() == &"wall_segment"


func _segment_ready(cell: Vector2i) -> bool:
	if cell.x > 900000:
		return false
	var weapon := _weapon()
	if weapon == null or not _piece_selected():
		return false
	var world = player.get("world")
	var quarter := int(weapon.get("blueprint_quarter"))
	var column := Vector3(float(cell.x) + 0.5, 0.0, float(cell.y) + 0.5)
	var plan: Dictionary = weapon.ghost_preview(&"wall_segment", column, quarter, world)
	return bool(plan.get("valid", false))


func _cursor_cell() -> Vector2i:
	if player == null:
		return Vector2i(999999, 999999)
	var hl := player.get_node_or_null("TargetHighlight")
	if hl == null or not hl.has_method("get_action_column"):
		return Vector2i(999999, 999999)
	var col: Vector3 = hl.get_action_column()
	if col == Vector3.ZERO:
		return Vector2i(999999, 999999)
	return Vector2i(floori(col.x), floori(col.z))


func _place_reason() -> String:
	if tree == null:
		return ""
	var editor := tree.root.find_child("TerrainEditor", true, false)
	if editor == null:
		editor = tree.get_first_node_in_group("terrain_editor")
	if editor == null:
		return ""
	return str(editor.get("last_fail_reason"))


func _piece_slot() -> int:
	if player == null or player.inventory == null:
		return -1
	for i in 8:
		var slot = player.inventory.get_hotbar_item(i)
		if slot != null and str(slot.id) == "wall_segment":
			return i
	return -1


func _place_wind() -> float:
	return _Pace.action_span("building_placement") + 0.05


func _look_at(cell: Vector2i, extra: PackedStringArray = PackedStringArray()) -> void:
	var at := Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5)
	hands.aim_column(player, at.x, at.y)
	var held := PackedStringArray()
	for action in extra:
		held.append(action)
	var spin := _Nav.face_action(_xz(), at, _yaw())
	if spin != "":
		held.append(spin)
	hands.set_held(held)


func _stop_move() -> void:
	hands.set_held(PackedStringArray())


func _spinning(cell: Vector2i) -> bool:
	var at := Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5)
	return _Nav.face_action(_xz(), at, _yaw()) != ""


func _dry_near() -> Vector2i:
	var origin := _column()
	var best := Vector2i(999999, 999999)
	var best_d := 99
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var cheb := maxi(absi(dx), absi(dz))
			if cheb < 2 or cheb > 3:
				continue
			var cell := origin + Vector2i(dx, dz)
			if not _open_ground(cell):
				continue
			if cheb < best_d:
				best_d = cheb
				best = cell
	return best


func _exit_crystal_held() -> PackedStringArray:
	var origin := _column()
	var best := Vector2i(4, 0)
	var best_depth := 999.0
	for off in [Vector2i(4, 0), Vector2i(-4, 0), Vector2i(0, 4), Vector2i(0, -4)]:
		var depth := _crystal_depth(origin + off)
		if depth < best_depth:
			best_depth = depth
			best = off
	var held := PackedStringArray()
	var face := _Nav.face_action(_xz(), _xz() + Vector2(best), _yaw())
	if face != "":
		held.append(face)
	else:
		held.append("move_forward")
		held.append("sprint")
	return held


func _free_cell(start: int) -> Vector2i:
	var origin := _column()
	var ring: Array[Vector2i] = []
	for dist in range(2, 14):
		for dz in range(-dist, dist + 1):
			for dx in range(-dist, dist + 1):
				if maxi(absi(dx), absi(dz)) != dist:
					continue
				ring.append(Vector2i(dx, dz))
	if ring.is_empty():
		return origin + Vector2i(5, 0)
	var n := ring.size()
	for k in n:
		var off: Vector2i = ring[posmod(start + k, n)]
		var cell := origin + off
		if not _open_ground(cell):
			continue
		return cell
	return origin + Vector2i(8, 0)


func _open_ground(cell: Vector2i) -> bool:
	if not _Edits.can_edit(cell.x, cell.y):
		return false
	if _Edits.get_build_tile(cell.x, cell.y) >= 0:
		return false
	var feat := _Features.get_feature(cell.x, cell.y)
	if str(feat.get("build_id", "")) != "":
		return false
	return _crystal_depth(cell) < CRYSTAL_SKIP


func _crystal_depth(cell: Vector2i) -> float:
	if tree == null:
		return 0.0
	var crystal := tree.get_first_node_in_group("crystal_manager")
	if crystal == null or not crystal.has_method("get_depth_at"):
		return 0.0
	return float(crystal.get_depth_at(cell.x, cell.y))


func _column() -> Vector2i:
	var feet: Vector3 = player.voxel_position
	return Vector2i(floori(feet.x), floori(feet.z))


func _xz() -> Vector2:
	var feet: Vector3 = player.voxel_position
	return Vector2(feet.x, feet.z)


func _yaw() -> float:
	var cam = player.get("camera")
	if cam != null and "yaw_degrees" in cam:
		return float(cam.yaw_degrees)
	if cam != null and "yaw_target_degrees" in cam:
		return float(cam.yaw_target_degrees)
	return 0.0


func _height_snap() -> Dictionary:
	var origin := _column()
	var snap := {}
	for dz in range(-8, 9):
		for dx in range(-8, 9):
			var cell := Vector2i(origin.x + dx, origin.y + dz)
			snap[cell] = _Edits.get_height_delta(cell.x, cell.y)
	return snap


func _dropped() -> Vector2i:
	for key in heights.keys():
		var cell: Vector2i = key
		if _Edits.get_height_delta(cell.x, cell.y) < float(heights[cell]) - 0.01:
			return cell
	return Vector2i(999999, 999999)


func _tile_snap() -> Dictionary:
	var origin := _column()
	var snap := {}
	for dz in range(-8, 9):
		for dx in range(-8, 9):
			var cell := Vector2i(origin.x + dx, origin.y + dz)
			snap[cell] = _Edits.get_build_tile(cell.x, cell.y)
	return snap


func _new_tiles() -> int:
	var added := 0
	for key in tiles.keys():
		var cell: Vector2i = key
		var now := _Edits.get_build_tile(cell.x, cell.y)
		if now >= 0 and int(tiles[cell]) < 0:
			added += 1
	return added


func _ghost_count() -> int:
	if player == null:
		return 0
	var hl := player.get_node_or_null("TargetHighlight")
	if hl == null:
		return 0
	var n := 0
	for child in hl.get_children():
		if str(child.name).begins_with("StructureGhost") and bool(child.visible):
			n += 1
	return n
