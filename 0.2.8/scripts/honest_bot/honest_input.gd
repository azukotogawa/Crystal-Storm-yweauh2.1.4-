extends RefCounted

var _held: Dictionary = {}
var _pulse := ""


func begin_tick() -> void:
	if _pulse == "":
		return
	_send(_pulse, false)
	if Input.is_action_pressed(_pulse):
		Input.action_release(_pulse)
	_pulse = ""


func pulse(action: StringName) -> void:
	_pulse = String(action)
	_send(_pulse, true)


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
	return bool(_held.get(action, false)) or _pulse == action


func _send(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
