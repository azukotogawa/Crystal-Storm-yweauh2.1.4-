extends RefCounted

var _held: Dictionary = {}
var _pulses: PackedStringArray = PackedStringArray()


func begin_tick() -> void:
	for action in _pulses:
		_send(action, false)
		if Input.is_action_pressed(action):
			Input.action_release(action)
	_pulses = PackedStringArray()


func pulse(action: StringName) -> void:
	var name := String(action)
	if name == "":
		return
	for existing in _pulses:
		if existing == name:
			return
	_pulses.append(name)
	_send(name, true)


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


func _send(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
