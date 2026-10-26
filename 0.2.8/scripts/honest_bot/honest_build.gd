extends RefCounted

const _Nav = preload("res://scripts/honest_bot/honest_nav.gd")
const _Edits = preload("res://world/terrain_edits.gd")
const _Features = preload("res://world/feature_registry.gd")
const _Blueprints = preload("res://helpers/structure_blueprints.gd")
const _Pace = preload("res://scripts/honest_bot/honest_pace.gd")
const _Bot = preload("res://scripts/honest_bot/honest_play_bot.gd")
const _Channels = preload("res://world/channel_registry.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _WorldBorder = preload("res://helpers/world_border.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const OFFSETS: Array[Vector2i] = [
	Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2),
	Vector2i(3, 1), Vector2i(-3, 1), Vector2i(1, 3), Vector2i(1, -3),
	Vector2i(4, 0), Vector2i(0, 4), Vector2i(-4, 2), Vector2i(2, -4),
]
const DIG_LIMIT := 48.0
const PLACE_LIMIT := 130.0
const BRUSH_LIMIT := 110.0
const WATER_LIMIT := 520.0
const WALL_AT := 4
const STEP_AT := 8
const WATER_SCAN := 260
const WATER_PROBES := 60
const WATER_FILL_WAIT := 8.0
const WATER_QUIET := 1.2
const BRUSH_MASTERY := 5
const BRUSH_MIN_BLOCKS := 3
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
var blocked_cells: Array[Vector2i] = []
var stone_pre := 0
var stone_post := 0
var stroke_count := 0
var trench_len := 10
var trench_i := 1
var lake: Dictionary = {}
var fill_quiet := 0.0
var fill_last := -1
var water_ticks_before := 0
var pre_signature := ""
var shift_signature := ""
var t_signature := ""
var t_opened_chat := false
var swim_far := Vector2i(999999, 999999)
var swim_width := 0
var swam := false
var climbed_out := false
var fill_levels: Array = []
var step_levels: Array = []
var step_before := 0.0
var wall_levels: Array = []
var walker
var walking := false
var walk_failed := false


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
	blocked_cells = []
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
	if mode == "multi_dig" or mode == "multi_build" or mode == "mouse_build":
		return _brush()
	if mode == "water_dig" or mode == "water_trench":
		return _water_dig()
	if mode == "dev_keys":
		return _dev_keys()
	if mode == "swim":
		return _swim()
	if mode == "camera":
		return _camera()
	if mode == "hotbar":
		return _hotbar()
	if mode == "controls_tour":
		return _tour()
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
		var got := _cursor_cell()
		if got != aim and _cursor_usable(got):
			aim = got
			_look_at(aim)
		if not _column_aimed(aim):
			if show_age < _Pace.PRE_PAUSE + 1.4:
				return ""
			print("SHOWCASE dig aim miss want %s cursor %s" % [aim, _cursor_cell()])
			blocked_cells.append(aim)
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
			blocked_cells.append(aim)
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
		var before := float(heights.get(dug_hold, _Edits.get_height_delta(dug_hold.x, dug_hold.y)))
		var drop := before - _Edits.get_height_delta(dug_hold.x, dug_hold.y)
		print("SHOWCASE dig column %d %d drop %.3f" % [dug_hold.x, dug_hold.y, drop])
		show_age = 0.0
		beat = 6
		return ""
	_look_at(aim)
	show_age += step_dt
	if show_age < _Pace.SETTLE:
		return ""
	return "pass"


func _stone() -> int:
	var inv = player.get("inventory")
	if inv == null or not inv.has_method("count_item"):
		return 0
	return int(inv.count_item("stone"))


func _mastery() -> int:
	var weapon := _weapon()
	if weapon == null:
		return 0
	return int(weapon.brush_mastery())


func _brush_ready() -> bool:
	var weapon := _weapon()
	return weapon != null and int(weapon.brush_index) >= 1


func _dropped_count() -> int:
	var n := 0
	for key in heights.keys():
		var cell: Vector2i = key
		if _Edits.get_height_delta(cell.x, cell.y) < float(heights[cell]) - 0.01:
			n += 1
	return n


func _brush_hits() -> int:
	if mode == "multi_dig":
		return _dropped_count()
	return _new_tiles()


func _brush() -> String:
	var building := mode == "multi_build" or mode == "mouse_build"
	if age > BRUSH_LIMIT:
		print("FAIL %s timed out at beat %d" % [mode, beat])
		return "fail"
	chapter_label = mode
	if beat == 0:
		if not hands.pulse("hotbar_2"):
			return ""
		beat = 1
		return ""
	if beat == 1:
		if _mastery() >= BRUSH_MASTERY:
			_stop_move()
			beat = 5
			return ""
		aim = _dry_near()
		if aim.x > 900000:
			hands.set_held(_exit_crystal_held())
			show_age += step_dt
			if show_age > 1.4:
				show_age = 0.0
				tries += 1
				if tries > 6:
					print("FAIL %s no dry cell" % mode)
					return "fail"
			return ""
		_look_at(aim)
		show_age = 0.0
		beat = 2
		return ""
	if beat == 2:
		if _spinning(aim) and show_age < 2.4:
			show_age += step_dt
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
		show_age = 0.0
		beat = 4
		return ""
	if beat == 4:
		_look_at(aim, PackedStringArray(["attack"]))
		show_age += step_dt
		if _mastery() >= BRUSH_MASTERY:
			_stop_move()
			show_age = 0.0
			beat = 5
			return ""
		if show_age > 3.0:
			_stop_move()
			blocked_cells.append(aim)
			tries += 1
			if tries > 10:
				print("FAIL %s warmup dig missed" % mode)
				return "fail"
			show_age = 0.0
			beat = 1
		return ""
	if beat == 5:
		if building and not hands.pulse("hotbar_5"):
			return ""
		show_age = 0.0
		tries = 0
		beat = 6
		return ""
	if beat == 6:
		show_age += step_dt
		if _brush_ready():
			print("SHOWCASE brush ready index %d mastery %d" % [int(_weapon().brush_index), _mastery()])
			beat = 8
			return ""
		if show_age < _Pace.PRE_PAUSE:
			return ""
		if not hands.pulse("brush_grow"):
			return ""
		tries += 1
		if tries > 6:
			print("FAIL %s brush did not unlock" % mode)
			return "fail"
		show_age = 0.0
		return ""
	if beat == 8:
		blocked_cells = []
		aim = _free_cell(tries) if building else _dry_near()
		if aim.x > 900000:
			print("FAIL %s no stroke cell" % mode)
			return "fail"
		_look_at(aim)
		show_age = 0.0
		beat = 9
		return ""
	if beat == 9:
		if _spinning(aim) and show_age < 2.4:
			show_age += step_dt
			_look_at(aim)
			return ""
		_stop_move()
		_look_at(aim)
		show_age += step_dt
		if show_age < _Pace.PRE_PAUSE:
			return ""
		heights = _height_snap()
		tiles = _tile_snap()
		stone_pre = _stone()
		show_age = 0.0
		beat = 10
		return ""
	if beat == 10:
		if building:
			if mode == "mouse_build":
				if not hands.click_at(player, hands.last_aim, true, MOUSE_BUTTON_RIGHT):
					return ""
			elif not hands.pulse("build_place"):
				return ""
			_look_at(aim)
		else:
			_look_at(aim, PackedStringArray(["attack"]))
		show_age = 0.0
		beat = 11
		return ""
	if beat == 11:
		if mode == "mouse_build" and show_age == 0.0:
			hands.click_at(player, hands.last_aim, false, MOUSE_BUTTON_RIGHT)
		_look_at(aim, PackedStringArray(["attack"]) if not building else PackedStringArray())
		show_age += step_dt
		stroke_count = _brush_hits()
		if stroke_count >= BRUSH_MIN_BLOCKS:
			_stop_move()
			stone_post = _stone()
			show_age = 0.0
			beat = 12
			return ""
		if show_age > _Pace.action_span("multi_block_break") + 1.2:
			_stop_move()
			tries += 1
			if tries > 8:
				print("FAIL %s stroke hit %d of %d" % [mode, stroke_count, BRUSH_MIN_BLOCKS])
				return "fail"
			beat = 8
		return ""
	if beat == 12:
		_look_at(aim)
		show_age += step_dt
		if show_age < _Pace.RESULT_HOLD:
			return ""
		print("SHOWCASE %s blocks %d stone %d to %d" % [mode, stroke_count, stone_pre, stone_post])
		show_age = 0.0
		beat = 13
		return ""
	_look_at(aim)
	show_age += step_dt
	if show_age < _Pace.SETTLE:
		return ""
	return "pass"


func _world():
	return player.get("world") if player != null else null


func _is_lake(cell: Vector2i) -> bool:
	var world = _world()
	if world == null:
		return false
	var tile := int(world.get_tile_type(float(cell.x) + 0.5, float(cell.y) + 0.5))
	if _WorldBorder.is_ocean_tile(tile):
		return false
	return _CrystalTypes.is_water_tile(tile)


func _is_wet(cell: Vector2i) -> bool:
	var world = _world()
	return _CrystalTypes.is_water_tile(int(world.get_tile_type(float(cell.x) + 0.5, float(cell.y) + 0.5)))


func _ground_h(cell: Vector2i) -> float:
	return float(_world().get_surface_height(float(cell.x) + 0.5, float(cell.y) + 0.5))


func _trench_ok(source: Vector2i, axis: Vector2i, length: int) -> bool:
	var perp := Vector2i(-axis.y, axis.x)
	var layer: float = _WorldSettings.get_active().layer_height()
	var h1 := _ground_h(source + axis)
	for i in range(1, length + 1):
		var cell := source + axis * i
		if _is_wet(cell) or not _open_ground(cell):
			return false
		if absf(_ground_h(cell) - h1) > 0.01:
			return false
		for side in [perp, -perp]:
			var lateral: Vector2i = cell + side
			if _is_wet(lateral) or _ground_h(lateral) < h1 - 0.01:
				return false
		var stand := cell + perp * 2
		if _is_wet(stand) or not _open_ground(stand) or absf(_ground_h(stand) - h1) > layer * 0.6:
			return false
	var past := source + axis * (length + 1)
	return not _is_wet(past) and _ground_h(past) >= h1 - 0.01


func _find_lake(length: int) -> Dictionary:
	var origin := _column()
	var coarse: Array = []
	for dz in range(-WATER_SCAN, WATER_SCAN + 1, 4):
		for dx in range(-WATER_SCAN, WATER_SCAN + 1, 4):
			var cell := origin + Vector2i(dx, dz)
			if _is_lake(cell):
				coarse.append([float(dx * dx + dz * dz), cell])
	coarse.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var best := {}
	var best_d := 1.0e9
	var tried := 0
	for entry in coarse:
		if tried >= WATER_PROBES or float(entry[0]) > best_d + 400.0:
			break
		tried += 1
		var hub: Vector2i = entry[1]
		for dz in range(-6, 7):
			for dx in range(-6, 7):
				var source := hub + Vector2i(dx, dz)
				var d := float((source - origin).length_squared())
				if d >= best_d or not _is_lake(source):
					continue
				for axis in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if _trench_ok(source, axis, length):
						best = {"source": source, "axis": axis}
						best_d = d
						break
	return best


func _trench_cell(i: int) -> Vector2i:
	return (lake["source"] as Vector2i) + (lake["axis"] as Vector2i) * i


func _trench_stand(i: int) -> Vector2i:
	var axis: Vector2i = lake["axis"]
	return _trench_cell(i) + Vector2i(-axis.y, axis.x) * 2


func _walk_to(cell: Vector2i) -> bool:
	if walker == null:
		walker = _Bot.new()
		walker.stuck_limit = 6
	walker.input = hands
	if not walking:
		walker.has_target = false
		walker.set_target(Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5))
		walking = true
	walker.tick(_xz(), _yaw(), step_dt)
	if walker.gave_up:
		print("FAIL water_dig walker stuck: %s" % "|".join(walker.stuck_lines))
		walking = false
		walk_failed = true
		return true
	if walker.arrived:
		walking = false
		_stop_move()
		return true
	return false


func water_levels() -> Array:
	var out: Array = []
	if lake.is_empty():
		return out
	for i in range(1, trench_len + 1):
		var c := _trench_cell(i)
		out.append(snappedf(_Channels.get_water_level(c.x, c.y), 0.001) if _Channels.has_fluid(c.x, c.y, _Channels.FLUID_WATER) else 0.0)
	return out


func _water_count() -> int:
	return _Channels.all_fluid_positions(_Channels.FLUID_WATER).size()


func _swimming_now() -> bool:
	return bool(player._water_here().get("submerged", false))


func _swim() -> String:
	if age > WATER_LIMIT:
		print("FAIL swim timed out at beat %d" % beat)
		return "fail"
	chapter_label = "swim"
	if beat == 0:
		lake = _find_lake(1)
		if lake.is_empty():
			print("FAIL swim found no lake within %d" % WATER_SCAN)
			return "fail"
		var source: Vector2i = lake["source"]
		var back: Vector2i = -(lake["axis"] as Vector2i)
		swim_far = Vector2i(999999, 999999)
		for k in range(1, 60):
			var cell := source + back * k
			if not _is_wet(cell):
				if k >= 3 and _open_ground(cell):
					swim_far = cell
					swim_width = k
				break
		if swim_far.x > 900000:
			print("FAIL swim lake at %s is not crossable along %s" % [source, back])
			return "fail"
		print("SHOWCASE swim lake %s crossing %d cells to %s" % [source, swim_width, swim_far])
		beat = 1
		return ""
	if beat == 1:
		if not _walk_to((lake["source"] as Vector2i) + (lake["axis"] as Vector2i)):
			return ""
		if walk_failed:
			return "fail"
		_stop_move()
		show_age = 0.0
		beat = 2
		return ""
	if beat == 2:
		var mid := (lake["source"] as Vector2i) - (lake["axis"] as Vector2i) * (swim_width / 2)
		if not _walk_to(mid):
			swam = swam or _swimming_now()
			return ""
		if walk_failed:
			return "fail"
		swam = swam or _swimming_now()
		_stop_move()
		show_age = 0.0
		beat = 3
		return ""
	if beat == 3:
		if not _walk_to(swim_far - (lake["axis"] as Vector2i)):
			swam = swam or _swimming_now()
			return ""
		if walk_failed:
			return "fail"
		_stop_move()
		show_age = 0.0
		beat = 4
		return ""
	show_age += step_dt
	if show_age < _Pace.RESULT_HOLD:
		return ""
	climbed_out = not _swimming_now() and not _is_wet(_column())
	return "pass"


func _terrain_signature() -> String:
	return "%s|%d" % [str(_height_snap()), _water_count()]


func chat_open() -> bool:
	var chat = tree.get_first_node_in_group("dev_chat_overlay")
	return chat != null and chat.is_chat_open()


var cam_log: Dictionary = {}


func _camera() -> String:
	if age > 60.0:
		print("FAIL camera timed out at beat %d" % beat)
		return "fail"
	chapter_label = "camera"
	show_age += step_dt
	var cam = player.get("camera")
	if cam == null:
		return "fail"
	if beat == 0:
		cam_log["yaw0"] = cam.yaw_degrees
		cam_log["pitch0"] = cam.pitch_degrees
		cam_log["zoom0"] = cam.zoom_level
		show_age = 0.0
		beat = 1
		return ""
	if beat == 1:
		if show_age < 0.5 or not hands.pulse_key(KEY_E):
			return ""
		show_age = 0.0
		beat = 2
		return ""
	if beat == 2:
		if show_age < 1.5:
			return ""
		cam_log["yaw1"] = cam.yaw_degrees
		show_age = 0.0
		beat = 3
		return ""
	if beat == 3:
		hands.motion(_alt_look_rel(cam), true)
		if show_age < 0.2:
			return ""
		show_age = 0.0
		beat = 4
		return ""
	if beat == 4:
		if show_age < 1.0:
			return ""
		cam_log["pitch1"] = cam.pitch_degrees
		show_age = 0.0
		beat = 5
		return ""
	if beat == 5:
		if not hands.pulse_key(KEY_EQUAL):
			return ""
		show_age = 0.0
		beat = 6
		return ""
	if beat == 6:
		if show_age < 0.3:
			return ""
		cam_log["zoom1"] = cam.zoom_level
		show_age = 0.0
		beat = 7
		return ""
	if beat == 7:
		if not hands.pulse_key(KEY_HOME):
			return ""
		show_age = 0.0
		beat = 8
		return ""
	if beat == 8:
		if show_age < 1.5:
			return ""
		cam_log["zoom2"] = cam.zoom_level
		cam_log["yaw2"] = cam.yaw_degrees
		cam_log["pitch2"] = cam.pitch_degrees
		beat = 9
		show_age = 0.0
		return ""
	if show_age < _Pace.RESULT_HOLD:
		return ""
	return "pass"


var tour: Array = []
var tour_checks: Dictionary = {}


func _alt_look_rel(cam) -> Vector2:
	return Vector2(0, 40 if cam.pitch_target_degrees > -48.0 else -40)


func _tour_note(key: String, ok: bool) -> void:
	tour_checks[key] = ok
	print("TOUR %s %s" % [key, "ok" if ok else "FAIL"])


func _tour_build(cam, weapon, skills, bar) -> void:
	var hotbar_seq: Array = []
	var s: Dictionary = {}
	tour = [
		[func(): s["yaw"] = cam.yaw_degrees; s["pitch"] = cam.pitch_degrees; s["zoom"] = cam.zoom_level; s["col"] = _column(); s["sig"] = str(_height_snap_at(s.col)); aim = _dry_near(), 0.5, func(): pass],
		[func(): hands.pulse_key(KEY_E), 1.5, func(): _tour_note("snap_yaw", absf(fposmod(cam.yaw_degrees - s.yaw + 180.0, 360.0) - 180.0 - 90.0) <= 1.0)],
		[func(): hands.motion(_alt_look_rel(cam), true), 1.2, func(): _tour_note("alt_look", absf(cam.pitch_degrees - s.pitch) >= 1.0)],
		[func(): hands.pulse_key(KEY_EQUAL), 0.4, func(): _tour_note("zoom_key", cam.zoom_level < s.zoom); s["z1"] = cam.zoom_level],
		[func(): hands.wheel(true, true), 0.4, func(): _tour_note("ctrl_wheel", cam.zoom_level < s.z1)],
		[func(): hands.pulse_key(KEY_HOME), 1.5, func(): _tour_note("home_reset", absf(cam.zoom_level - s.zoom) < 0.01)],
		[func(): hands.pulse_key(KEY_3), 0.5, func(): hotbar_seq.append(weapon.get_active_hotbar_index())],
		[func(): hands.pulse_key(KEY_0), 0.5, func(): hotbar_seq.append(weapon.get_active_hotbar_index())],
		[func(): hands.wheel(false), 0.5, func(): hotbar_seq.append(weapon.get_active_hotbar_index())],
		[func(): hands.wheel(true), 0.5, func(): hotbar_seq.append(weapon.get_active_hotbar_index()); _tour_note("hotbar_cycle", hotbar_seq == [2, 9, 0, 9]); _tour_note("plain_wheel_no_zoom", absf(cam.zoom_level - s.zoom) < 0.01)],
		[func(): hands.pulse_key(KEY_2), 0.5, func(): s["slot"] = weapon.get_active_hotbar_index(); skills._unlocked[&"dash"] = true; skills.equip(0, &"dash")],
		[func(): hands.pulse_key(KEY_1, true), 0.4, func(): _tour_note("skill_shift_1", skills.cooldown_left(0) > 0.0 and weapon.get_active_hotbar_index() == s.slot); _tour_note("skill_hud", bar.slot_text(0).cooldown != "" and bar.slot_text(0).key == "Shift+1")],
		[func(): pass, 3.5, func(): _tour_note("skill_ready", skills.cooldown_left(0) <= 0.0 and bar.slot_text(0).cooldown == "")],
		[func(): hands.pulse_key(KEY_Z), 0.4, func(): _tour_note("rotate", weapon.blueprint_quarter == 1)],
		[func(): hands.pulse("place_cycle"), 0.4, func(): _tour_note("tab_variant", weapon.place_index != 0)],
		[func(): hands.pulse_key(KEY_X), 0.4, func(): _tour_note("x_variant", weapon.build_variant == 1)],
		[func(): hands.pulse_key(KEY_T), 0.8, func(): _tour_note("t_chat", chat_open()); _tour_note("t_terrain", str(_height_snap_at(s.col)) == s.sig)],
		[func(): hands.pulse_key(KEY_ESCAPE), 1.2, func(): _tour_note("esc_closes", not chat_open())],
	]


var tour_step_done := false


func _tour() -> String:
	if age > 120.0:
		print("FAIL controls_tour timed out at beat %d" % beat)
		return "fail"
	chapter_label = "controls_tour"
	show_age += step_dt
	var cam = player.get("camera")
	var weapon = player.get_node_or_null("WeaponController")
	var skills = tree.get_first_node_in_group("skill_service")
	var bar = tree.root.find_child("SkillBar", true, false)
	if cam == null or weapon == null or skills == null or bar == null:
		return "fail"
	if tour.is_empty():
		_tour_build(cam, weapon, skills, bar)
	if beat < tour.size():
		var entry: Array = tour[beat]
		if not tour_step_done:
			entry[0].call()
			tour_step_done = true
			show_age = 0.0
			return ""
		if show_age < float(entry[1]):
			return ""
		entry[2].call()
		tour_step_done = false
		beat += 1
		show_age = 0.0
		return ""
	if show_age < _Pace.RESULT_HOLD:
		return ""
	return "pass"


const HOTBAR_STEPS := [
	["key", KEY_3, 2],
	["key", KEY_0, 9],
	["wheel", false, 0],
	["wheel", true, 9],
]


func _hotbar() -> String:
	if age > 60.0:
		print("FAIL hotbar timed out at beat %d" % beat)
		return "fail"
	chapter_label = "hotbar"
	show_age += step_dt
	var cam = player.get("camera")
	var weapon = player.get_node_or_null("WeaponController")
	if cam == null or weapon == null:
		return "fail"
	if beat == 0:
		cam_log["zoom0"] = cam.zoom_level
		cam_log["hotbar"] = []
		show_age = 0.0
		beat = 1
		return ""
	if beat <= HOTBAR_STEPS.size():
		var step: Array = HOTBAR_STEPS[beat - 1]
		if show_age < 0.6:
			return ""
		if beat > 1 and cam_log["hotbar"].size() < beat - 1:
			cam_log["hotbar"].append(weapon.get_active_hotbar_index())
		if step[0] == "key":
			if not hands.pulse_key(step[1]):
				return ""
		else:
			hands.wheel(step[1])
		show_age = 0.0
		beat += 1
		return ""
	if beat == HOTBAR_STEPS.size() + 1:
		if show_age < 0.6:
			return ""
		cam_log["hotbar"].append(weapon.get_active_hotbar_index())
		cam_log["zoom1"] = cam.zoom_level
		beat += 1
		show_age = 0.0
		return ""
	if show_age < _Pace.RESULT_HOLD:
		return ""
	return "pass"


func _dev_keys() -> String:
	if age > 60.0:
		print("FAIL dev_keys timed out at beat %d" % beat)
		return "fail"
	chapter_label = "dev_keys"
	show_age += step_dt
	if beat == 0:
		if not hands.pulse("hotbar_2"):
			return ""
		aim = _dry_near()
		pre_signature = _terrain_signature()
		show_age = 0.0
		beat = 1
		return ""
	if beat == 1:
		_look_at(aim)
		if show_age < _Pace.PRE_PAUSE or not hands.pulse_key(KEY_T, true):
			return ""
		show_age = 0.0
		beat = 2
		return ""
	if beat == 2:
		if show_age < 0.5:
			return ""
		shift_signature = _terrain_signature()
		beat = 3
		return ""
	if beat == 3:
		if not _esc_chat():
			return ""
		show_age = 0.0
		beat = 4
		return ""
	if beat == 4:
		if show_age < 0.5 or not hands.pulse_key(KEY_T):
			return ""
		show_age = 0.0
		beat = 5
		return ""
	if beat == 5:
		if show_age < 0.5:
			return ""
		t_opened_chat = chat_open()
		t_signature = _terrain_signature()
		beat = 6
		return ""
	if beat == 6:
		if not _esc_chat():
			return ""
		show_age = 0.0
		beat = 7
		return ""
	if show_age < _Pace.RESULT_HOLD:
		return ""
	return "pass"


func _esc_chat() -> bool:
	if not chat_open():
		return true
	if show_age >= 1.0 and hands.pulse_key(KEY_ESCAPE):
		show_age = 0.0
	return false


func _water_dig() -> String:
	if age > WATER_LIMIT:
		print("FAIL water_dig timed out at beat %d" % beat)
		return "fail"
	chapter_label = "water_dig"
	if mode == "water_trench":
		chapter_label = "water_trench_fill" if beat < 8 else "water_trench_wall"
	if mode == "water_trench" and beat >= 7:
		return _trench_wall()
	if beat == 0:
		if not hands.pulse("hotbar_2"):
			return ""
		beat = 1
		return ""
	if beat == 1:
		lake = _find_lake(trench_len)
		if lake.is_empty():
			print("FAIL water_dig no lake with a %d cell dry strip within %d" % [trench_len, WATER_SCAN])
			return "fail"
		print("SHOWCASE water_dig lake %s axis %s cells %d" % [lake["source"], lake["axis"], trench_len])
		trench_i = 1
		show_age = 0.0
		beat = 2
		return ""
	if beat == 2:
		show_age += step_dt
		if not _walk_to(_trench_stand(trench_i)):
			return ""
		if walk_failed:
			return "fail"
		_stop_move()
		show_age = 0.0
		beat = 3
		return ""
	if beat == 3:
		var cell := _trench_cell(trench_i)
		aim = cell
		_look_at(aim)
		show_age += step_dt
		if _spinning(aim) and show_age < 4.0:
			return ""
		if show_age < _Pace.PRE_PAUSE:
			return ""
		heights = _height_snap()
		show_age = 0.0
		beat = 4
		return ""
	if beat == 4:
		_look_at(aim, PackedStringArray(["attack"]))
		show_age += step_dt
		if _dropped() == aim:
			_stop_move()
			show_age = 0.0
			beat = 5
			return ""
		if show_age > 6.0:
			print("FAIL water_dig could not dig trench cell %s" % aim)
			return "fail"
		return ""
	if beat == 5:
		show_age += step_dt
		if show_age < _Pace.action_span("multi_block_break") + 0.3:
			return ""
		show_age = 0.0
		if trench_i < trench_len:
			trench_i += 1
			beat = 2
			return ""
		fill_quiet = 0.0
		fill_last = -1
		beat = 6
		return ""
	if beat == 6:
		show_age += step_dt
		var count := _water_count()
		if count == fill_last:
			fill_quiet += step_dt
		else:
			fill_quiet = 0.0
			fill_last = count
		var filled: bool = not water_levels().is_empty() and float(water_levels()[0]) >= 0.8
		if (fill_quiet >= WATER_QUIET and filled) or show_age > WATER_FILL_WAIT:
			show_age = 0.0
			beat = 7
		return ""
	show_age += step_dt
	if show_age < _Pace.RESULT_HOLD:
		return ""
	return "pass"


func _trench_step() -> String:
	var cell := _trench_cell(STEP_AT)
	if beat == 30:
		if not _walk_to(_trench_stand(STEP_AT)):
			return ""
		if walk_failed:
			return "fail"
		_stop_move()
		show_age = 0.0
		beat = 31
		return ""
	if beat == 31:
		aim = cell
		_look_at(aim)
		show_age += step_dt
		if (_spinning(aim) and show_age < 4.0) or show_age < _Pace.PRE_PAUSE:
			return ""
		step_before = _Edits.get_height_delta(cell.x, cell.y)
		show_age = 0.0
		beat = 32
		return ""
	if beat == 32:
		_look_at(aim, PackedStringArray(["attack"]))
		show_age += step_dt
		if _Edits.get_height_delta(cell.x, cell.y) < step_before - 0.001:
			_stop_move()
			show_age = 0.0
			fill_quiet = 0.0
			fill_last = -1
			beat = 33
			return ""
		if show_age > 6.0:
			print("FAIL water_trench could not dig the down-step at %s" % cell)
			return "fail"
		return ""
	show_age += step_dt
	var count := _water_count()
	if count == fill_last:
		fill_quiet += step_dt
	else:
		fill_quiet = 0.0
		fill_last = count
	if (fill_quiet >= WATER_QUIET and show_age >= 2.0) or show_age > WATER_FILL_WAIT:
		step_levels = water_levels()
		show_age = 0.0
		beat = 8
	return ""


func _trench_wall() -> String:
	var cell := _trench_cell(WALL_AT)
	if beat == 7:
		fill_levels = water_levels()
		show_age = 0.0
		beat = 30
		return ""
	if beat >= 30:
		return _trench_step()
	if beat == 8:
		if not hands.pulse("hotbar_5"):
			return ""
		beat = 9
		return ""
	if beat == 9:
		var weapon := _weapon()
		if weapon != null and str(weapon.get_place_id()) == "stone_wall":
			beat = 10
			return ""
		if tries > 8:
			print("FAIL water_trench place cycle missed stone_wall")
			return "fail"
		if hands.pulse("place_cycle"):
			tries += 1
		return ""
	if beat == 10:
		if not _walk_to(_trench_stand(WALL_AT)):
			return ""
		if walk_failed:
			return "fail"
		_stop_move()
		show_age = 0.0
		beat = 11
		return ""
	if beat == 11:
		aim = cell
		_look_at(aim)
		show_age += step_dt
		if (_spinning(aim) and show_age < 4.0) or show_age < _Pace.PRE_PAUSE:
			return ""
		if not hands.pulse("build_place"):
			return ""
		show_age = 0.0
		beat = 12
		return ""
	if beat == 12:
		_look_at(aim)
		show_age += step_dt
		if _Edits.get_build_tile(cell.x, cell.y) >= 0:
			show_age = 0.0
			fill_quiet = 0.0
			fill_last = -1
			beat = 13
			return ""
		if show_age > 6.0:
			print("FAIL water_trench wall was not placed across the trench at %s from %s (%s)" % [cell, str(_column()), str(tree.get_first_node_in_group("terrain_editor").last_fail_reason)])
			return "fail"
		return ""
	if beat == 13:
		show_age += step_dt
		var count := _water_count()
		if count == fill_last:
			fill_quiet += step_dt
		else:
			fill_quiet = 0.0
			fill_last = count
		if (fill_quiet >= WATER_QUIET and show_age >= 2.0) or show_age > WATER_FILL_WAIT:
			wall_levels = water_levels()
			show_age = 0.0
			beat = 14
		return ""
	show_age += step_dt
	if show_age < _Pace.RESULT_HOLD:
		return ""
	return "pass"


func _cursor_usable(cell: Vector2i) -> bool:
	if cell.x > 900000:
		return false
	var origin := _column()
	if maxi(absi(cell.x - origin.x), absi(cell.y - origin.y)) > 6:
		return false
	return _open_ground(cell)


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
		stone_pre = _stone()
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
		stone_post = _stone()
		print("SHOWCASE structure stone_wall placed stone %d to %d" % [stone_pre, stone_post])
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
		if aim.x > 900000 or _footprint_quarter(aim) < 0:
			var found := _segment_cell(tries)
			if found.x > 900000:
				hands.set_held(_exit_crystal_held())
				show_age += step_dt
				if show_age < 1.2:
					return ""
				show_age = 0.0
				tries += 1
				if tries > 18:
					print("FAIL structure wall_segment no footprint")
					return "fail"
				return ""
			aim = found
			spin = 0
			show_age = 0.0
		var want := _footprint_quarter(aim)
		var weapon := _weapon()
		if weapon != null and int(weapon.get("blueprint_quarter")) != want:
			hands.pulse_key(KEY_Z)
			return ""
		if _spinning(aim):
			_look_at(aim)
			return ""
		_look_at(aim)
		var got := _cursor_cell()
		if got != aim and _footprint_quarter(got) >= 0:
			aim = got
			spin = 0
			show_age = 0.0
			return ""
		if got != aim or not _segment_ready(aim):
			spin += 1
			if spin < 48:
				return ""
			spin = 0
			tries += 1
			if tries > 18:
				print("FAIL structure wall_segment cursor %s reason %s" % [got, _place_reason()])
				return "fail"
			aim = Vector2i(999999, 999999)
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
	aim = Vector2i(999999, 999999)
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


func _footprint_quarter(cell: Vector2i) -> int:
	if cell.x > 900000 or not _open_ground(cell):
		return -1
	var weapon := _weapon()
	if weapon == null or not _piece_selected():
		return -1
	var world = player.get("world")
	var column := Vector3(float(cell.x) + 0.5, 0.0, float(cell.y) + 0.5)
	for quarter in 4:
		var plan: Dictionary = weapon.ghost_preview(&"wall_segment", column, quarter, world)
		if bool(plan.get("valid", false)):
			return quarter
	return -1


func _segment_cell(start: int) -> Vector2i:
	var origin := _column()
	var ring: Array[Vector2i] = []
	for dist in range(2, 14):
		for dz in range(-dist, dist + 1):
			for dx in range(-dist, dist + 1):
				if maxi(absi(dx), absi(dz)) != dist:
					continue
				ring.append(Vector2i(dx, dz))
	if ring.is_empty():
		return Vector2i(999999, 999999)
	var n := ring.size()
	for k in n:
		var cell: Vector2i = origin + ring[posmod(start + k, n)]
		if _footprint_quarter(cell) >= 0:
			return cell
	return Vector2i(999999, 999999)


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
	for dz in range(-5, 6):
		for dx in range(-5, 6):
			var cheb := maxi(absi(dx), absi(dz))
			if cheb < 2 or cheb > 5:
				continue
			var cell := origin + Vector2i(dx, dz)
			if blocked_cells.has(cell) or not _open_ground(cell):
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
	return _height_snap_at(_column())


func _height_snap_at(origin: Vector2i) -> Dictionary:
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
