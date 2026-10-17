extends RefCounted

const _Aim = preload("res://player/action_targeting.gd")
const _Pace = preload("res://scripts/honest_bot/honest_pace.gd")

var pace_presses := false
var _since_press := 1.0
var _held: Dictionary = {}
var _pulses: PackedStringArray = PackedStringArray()
var _keys: Array[int] = []


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


func is_held(action: String) -> bool:
	if bool(_held.get(action, false)):
		return true
	for existing in _pulses:
		if existing == action:
			return true
	return false


func pulse_key(code: int) -> bool:
	if code == 0:
		return false
	for existing in _keys:
		if existing == code:
			return true
	if not _press_slot():
		return false
	_keys.append(code)
	_send_key(code, true)
	return true


func aim_column(body: Node, col_x: float, col_z: float) -> void:
	if body == null:
		return
	var vp := body.get_viewport()
	if vp == null:
		return
	var world = body.get("world")
	var screen := _Aim.screen_pos_for_column(body, world, col_x, col_z)
	if not _on_view(vp, screen):
		return
	_Aim.note_event_mouse(screen, vp.get_visible_rect().size)
	vp.notification(NOTIFICATION_VP_MOUSE_ENTER)
	vp.warp_mouse(screen)
	var motion := InputEventMouseMotion.new()
	_point(motion, screen)
	motion.relative = screen - vp.get_mouse_position()
	vp.push_input(motion, true)


func click_at(node: Node, at: Vector2, pressed: bool) -> bool:
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
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	_point(ev, at)
	vp.push_input(ev, true)
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
	ev.echo = false
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _point(ev: InputEventMouse, at: Vector2) -> void:
	ev.set("position", at)
	ev.set("global_position", at)


func _on_view(vp: Viewport, at: Vector2) -> bool:
	if at.x < 0.0 or at.y < 0.0:
		return false
	var rect := vp.get_visible_rect()
	if rect.size.x < 8.0 or rect.size.y < 8.0:
		return true
	return at.x <= rect.end.x and at.y <= rect.end.y
