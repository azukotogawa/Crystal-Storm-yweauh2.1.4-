extends RefCounted

const _Aim = preload("res://player/action_targeting.gd")
const _Hitbox = preload("res://systems/combat_hitbox.gd")
const _Resolver = preload("res://systems/combat_hit_resolver.gd")
const _Pace = preload("res://scripts/honest_bot/honest_pace.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

var pace_presses := false
var _since_press := 1.0
var _held: Dictionary = {}
var _pulses: PackedStringArray = PackedStringArray()
var _keys: Array[int] = []
var _shift_on := false
var last_aim := Vector2(-1.0, -1.0)
var _seat_key := Vector2i(999999, 999999)
var _seat_at := Vector2(-1.0, -1.0)


func advance_pace(delta: float) -> void:
	if delta > 0.0:
		_since_press += delta


func begin_tick() -> void:
	for action in _pulses:
		_send(action, false)
		if Input.is_action_pressed(action):
			Input.action_release(action)
	_pulses = PackedStringArray()
	for code in _keys:
		_send_key(code, false)
	_keys.clear()
	_shift_on = false


func pulse(action: StringName) -> bool:
	var name := String(action)
	if name == "":
		return false
	for existing in _pulses:
		if existing == name:
			return true
	if not _press_slot():
		return false
	_pulses.append(name)
	_send(name, true)
	return true


func set_held(actions: PackedStringArray) -> void:
	var want := {}
	for action in actions:
		var name := String(action)
		if name == "":
			continue
		want[name] = true
		if not Input.is_action_pressed(name):
			Input.action_press(name)
	for action in _held.keys():
		if not want.has(action):
			Input.action_release(String(action))
	_held = want


func release_all() -> void:
	begin_tick()
	for action in _held.keys():
		Input.action_release(String(action))
	_held.clear()


func held_names() -> PackedStringArray:
	var out := PackedStringArray()
	for action in _held.keys():
		out.append(String(action))
	return out


func is_held(action: String) -> bool:
	if bool(_held.get(action, false)):
		return true
	for existing in _pulses:
		if existing == action:
			return true
	return false


func pulse_key(code: int, shift: bool = false) -> bool:
	if code == 0:
		return false
	for existing in _keys:
		if existing == code:
			return true
	if not _press_slot():
		return false
	_keys.append(code)
	_shift_on = shift
	_send_key(code, true)
	return true


func aim_column(body: Node, col_x: float, col_z: float) -> void:
	if body == null:
		return
	var vp := body.get_viewport()
	if vp == null:
		return
	var world = body.get("world")
	var screen := _face_screen(body, world, col_x, col_z)
	var size := vp.get_visible_rect().size
	var key := Vector2i(floori(col_x), floori(col_z))
	var seated := _seat_key == key and _seat_at.x >= 0.0 and _cell_at(body, world, _seat_at, size) == key
	if not seated:
		_seat_key = key
		_seat_at = _seat_on_cell(body, world, key, screen, size)
	var at := screen
	if _seat_at.x >= 0.0:
		at = _seat_at
	elif not _on_view(vp, screen):
		return
	_warp(vp, at, size)


func aim_foe(body: Node, col_x: float, col_z: float) -> void:
	aim_column(body, col_x, col_z)
	if body == null:
		return
	var vp := body.get_viewport()
	var cam := vp.get_camera_3d() if vp else null
	if cam == null:
		return
	var s: float = maxf(_WorldSettings.get_active().voxel_scale, 0.001)
	var at := Vector3(col_x * s, 0.0, col_z * s)
	var best: Node = null
	var best_d := 1.5 * s
	for node in _Resolver._combat_nodes(body, at, 3.0 * s):
		if node == body or not node is Node3D:
			continue
		var c: Vector3 = _Hitbox.sphere_of(node).center
		var d := Vector2(c.x - at.x, c.z - at.z).length()
		if d < best_d:
			best_d = d
			best = node
	if best == null:
		return
	var center: Vector3 = _Hitbox.sphere_of(best).center
	if cam.is_position_behind(center):
		return
	var screen := cam.unproject_position(center)
	if not _on_view(vp, screen):
		return
	_warp(vp, screen, vp.get_visible_rect().size)


func _warp(vp: Viewport, at: Vector2, size: Vector2) -> void:
	last_aim = at
	_Aim.note_event_mouse(at, size)
	vp.warp_mouse(at)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	motion.relative = at - vp.get_mouse_position()
	vp.push_input(motion, true)


func _seat_on_cell(body: Node, world, key: Vector2i, screen: Vector2, size: Vector2) -> Vector2:
	if world == null or not _inside(screen, size):
		return Vector2(-1.0, -1.0)
	var at := screen
	for _step in 10:
		var hit := _cell_at(body, world, at, size)
		if hit == key:
			return at
		if hit.x > 900000:
			break
		var sx := _cell_at(body, world, at + Vector2(36.0, 0.0), size)
		var sy := _cell_at(body, world, at + Vector2(0.0, 36.0), size)
		if sx.x > 900000 or sy.x > 900000:
			break
		var jx := Vector2(float(sx.x - hit.x), float(sx.y - hit.y))
		var jy := Vector2(float(sy.x - hit.x), float(sy.y - hit.y))
		var err := Vector2(float(key.x - hit.x), float(key.y - hit.y))
		var det := jx.x * jy.y - jx.y * jy.x
		var shift := Vector2.ZERO
		if absf(det) < 0.02:
			shift = err * 28.0
		else:
			var px := (jy.y * err.x - jy.x * err.y) / det
			var py := (-jx.y * err.x + jx.x * err.y) / det
			shift = Vector2(px, py) * 36.0
		if shift.length() < 1.5:
			break
		if shift.length() > 220.0:
			shift = shift.normalized() * 220.0
		at += shift
		if size.x >= 8.0 and size.y >= 8.0:
			at.x = clampf(at.x, 4.0, size.x - 4.0)
			at.y = clampf(at.y, 4.0, size.y - 4.0)
	if _cell_at(body, world, at, size) == key:
		return at
	return Vector2(-1.0, -1.0)


func _cell_at(body: Node, world, at: Vector2, size: Vector2) -> Vector2i:
	if not _inside(at, size):
		return Vector2i(999999, 999999)
	_Aim.note_event_mouse(at, size)
	var player := body as Node3D
	if player == null:
		return Vector2i(999999, 999999)
	var chunks: ChunkManager = null
	if player.is_inside_tree():
		chunks = player.get_tree().get_first_node_in_group("chunk_manager") as ChunkManager
	var col: Vector3 = _Aim.pick_hover_column(player, world, chunks, _Aim.reach())
	if col == Vector3.ZERO:
		return Vector2i(999999, 999999)
	return Vector2i(floori(col.x), floori(col.z))


func _inside(at: Vector2, size: Vector2) -> bool:
	if size.x < 8.0 or size.y < 8.0:
		return at.x >= 0.0 and at.y >= 0.0
	return at.x >= 0.0 and at.y >= 0.0 and at.x <= size.x and at.y <= size.y


func click_at(node: Node, at: Vector2, pressed: bool, button: MouseButton = MOUSE_BUTTON_LEFT, ctrl: bool = false) -> bool:
	if node == null:
		return false
	var vp := node.get_viewport()
	if vp == null:
		return false
	if not _on_view(vp, at):
		return false
	if not _press_slot():
		return false
	_Aim.note_event_mouse(at, vp.get_visible_rect().size)
	vp.warp_mouse(at)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.ctrl_pressed = ctrl
	ev.pressed = pressed
	_point(ev, at)
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	return true


func _press_slot() -> bool:
	if not pace_presses:
		return true
	if _since_press + 0.0001 < _Pace.GAP:
		return false
	_since_press = 0.0
	return true


func _send(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _send_key(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code as Key
	ev.keycode = code as Key
	ev.pressed = pressed
	ev.shift_pressed = _shift_on
	ev.echo = false
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


static func window_point(final: Transform2D, at: Vector2) -> Vector2:
	return final * at


func _point(ev: InputEventMouse, at: Vector2) -> void:
	var win := at
	var loop := Engine.get_main_loop() as SceneTree
	if loop != null and loop.root != null:
		win = window_point(loop.root.get_final_transform(), at)
	ev.set("position", win)
	ev.set("global_position", win)


func _on_view(vp: Viewport, at: Vector2) -> bool:
	if at.x < 0.0 or at.y < 0.0:
		return false
	var rect := vp.get_visible_rect()
	if rect.size.x < 8.0 or rect.size.y < 8.0:
		return true
	return at.x <= rect.end.x and at.y <= rect.end.y


func motion(rel: Vector2, alt: bool = false) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = rel
	ev.alt_pressed = alt
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func wheel(up: bool, ctrl: bool = false) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	var released := ev.duplicate() as InputEventMouseButton
	released.pressed = false
	Input.parse_input_event(released)
	Input.flush_buffered_events()


## Screen point of the column's exposed top-face centre, in the same cell units the
## exact-face pick (FacePick) uses: x/z cell centre, y = surface_block_y. The older
## walkable_top projection can land off the face (or off screen), and the exact pick
## has no forward fallback, so the bot would aim at nothing.
func _face_screen(body: Node, world, col_x: float, col_z: float) -> Vector2:
	var cam: Camera3D = body.get("camera") as Camera3D if "camera" in body else null
	if cam == null or world == null:
		return _Aim.screen_pos_for_column(body, world, col_x, col_z)
	var s: float = maxf(_WorldSettings.get_active().voxel_scale, 0.001)
	var cx := floori(col_x)
	var cz := floori(col_z)
	var top := _TerrainEdits.surface_block_y(world, cx, cz)
	var p := Vector3((float(cx) + 0.5) * s, float(top + 1) * s, (float(cz) + 0.5) * s)
	if cam.is_position_behind(p):
		return _Aim.screen_pos_for_column(body, world, col_x, col_z)
	return cam.unproject_position(p)
