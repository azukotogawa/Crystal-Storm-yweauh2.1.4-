class_name InputBindings
extends RefCounted
## Gameplay actions from project.godot, plus pause (Escape).
## Defaults are captured once from the InputMap before any saved rebind is applied,
## so Reset restores the input contract (WASD, Space jump, Q/E yaw).

const ACTIONS: PackedStringArray = [
	"move_forward", "move_back", "move_left", "move_right",
	"jump", "rotate_left", "rotate_right",
	"attack", "build_place", "interact", "inventory_toggle",
	"plant", "channel_water", "place_cycle",
	"hotbar_1", "hotbar_2", "hotbar_3", "hotbar_4",
	"hotbar_5", "hotbar_6", "hotbar_7", "hotbar_8",
	"toggle_map", "quick_save", "quick_load",
	"pause",
	"dev_chat_toggle", "debug_overlay_toggle", "bug_report",
]

const LABELS := {
	"move_forward": "Move forward",
	"move_back": "Move back",
	"move_left": "Move left",
	"move_right": "Move right",
	"jump": "Jump",
	"rotate_left": "Rotate left",
	"rotate_right": "Rotate right",
	"attack": "Attack / use",
	"build_place": "Place / alt use",
	"interact": "Interact",
	"inventory_toggle": "Inventory",
	"plant": "Plant",
	"channel_water": "Channel water",
	"place_cycle": "Cycle place",
	"hotbar_1": "Hotbar 1",
	"hotbar_2": "Hotbar 2",
	"hotbar_3": "Hotbar 3",
	"hotbar_4": "Hotbar 4",
	"hotbar_5": "Hotbar 5",
	"hotbar_6": "Hotbar 6",
	"hotbar_7": "Hotbar 7",
	"hotbar_8": "Hotbar 8",
	"toggle_map": "Map",
	"quick_save": "Quick save",
	"quick_load": "Quick load",
	"pause": "Pause",
	"dev_chat_toggle": "Dev chat",
	"debug_overlay_toggle": "Debug overlay",
	"bug_report": "Bug report",
}

static var _captured: bool = false
static var _defaults: Dictionary = {}
## Times `apply_saved` was entered, including installs that rewrite the InputMap.
static var apply_saved_count: int = 0


static func label_of(action: String) -> String:
	return str(LABELS.get(action, action))


static func capture_defaults() -> void:
	if _captured:
		return
	_captured = true
	for action in ACTIONS:
		if not InputMap.has_action(action):
			continue
		var copy: Array[InputEvent] = []
		for ev in InputMap.action_get_events(action):
			if ev is InputEvent:
				copy.append((ev as InputEvent).duplicate())
		_defaults[action] = copy


static func apply_saved(saved: Dictionary) -> void:
	apply_saved_count += 1
	capture_defaults()
	if saved.is_empty():
		_install_defaults()
		return
	for action in ACTIONS:
		if not saved.has(action):
			_install_one(action)
			continue
		var packed = saved[action]
		if not packed is Array or (packed as Array).is_empty():
			_install_one(action)
			continue
		_ensure_action(action)
		InputMap.action_erase_events(action)
		for entry in packed:
			if entry is Dictionary:
				var ev := _unpack(entry)
				if ev != null:
					InputMap.action_add_event(action, ev)
		if InputMap.action_get_events(action).is_empty():
			_install_one(action)


static func export_current() -> Dictionary:
	capture_defaults()
	var out := {}
	for action in ACTIONS:
		var packed: Array = []
		if InputMap.has_action(action):
			for ev in InputMap.action_get_events(action):
				if ev is InputEvent:
					var row := _pack(ev)
					if not row.is_empty():
						packed.append(row)
		out[action] = packed
	return out


static func replace_action(action: String, event: InputEvent) -> void:
	capture_defaults()
	_ensure_action(action)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event.duplicate())


static func reset_events() -> void:
	capture_defaults()
	_install_defaults()


static func conflict_for(action: String, event: InputEvent) -> String:
	for other in ACTIONS:
		if other == action:
			continue
		if not InputMap.has_action(other):
			continue
		for bound in InputMap.action_get_events(other):
			if bound is InputEvent and _same_bind(bound, event):
				return label_of(other)
	return ""


static func binding_text(action: String) -> String:
	if not InputMap.has_action(action):
		return "Unbound"
	var parts: PackedStringArray = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEvent:
			var text := event_label(ev)
			if text != "":
				parts.append(text)
	if parts.is_empty():
		return "Unbound"
	return ", ".join(parts)


static func matches(action: String, event: InputEvent) -> bool:
	if event == null:
		return false
	if event.is_action_pressed(action):
		return true
	if not InputMap.has_action(action):
		return false
	for bound in InputMap.action_get_events(action):
		if bound is InputEvent and event.is_match(bound, true):
			return true
	return false


static func event_label(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		var name := OS.get_keycode_string(code)
		if name == "":
			name = "Key %d" % code
		var mods := ""
		if key.ctrl_pressed:
			mods += "Ctrl+"
		if key.alt_pressed:
			mods += "Alt+"
		if key.shift_pressed:
			mods += "Shift+"
		if key.meta_pressed:
			mods += "Meta+"
		return mods + name
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				return "Mouse left"
			MOUSE_BUTTON_RIGHT:
				return "Mouse right"
			MOUSE_BUTTON_MIDDLE:
				return "Mouse middle"
			_:
				return "Mouse %d" % button.button_index
	return ""


static func _install_defaults() -> void:
	for action in ACTIONS:
		_install_one(action)


static func _install_one(action: String) -> void:
	if not _defaults.has(action):
		return
	_ensure_action(action)
	InputMap.action_erase_events(action)
	var events: Array = _defaults[action]
	for ev in events:
		if ev is InputEvent:
			InputMap.action_add_event(action, (ev as InputEvent).duplicate())


static func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)


static func _same_bind(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		var ka := a as InputEventKey
		var kb := b as InputEventKey
		var ca := ka.physical_keycode if ka.physical_keycode != 0 else ka.keycode
		var cb := kb.physical_keycode if kb.physical_keycode != 0 else kb.keycode
		return ca == cb and ca != 0 \
			and ka.shift_pressed == kb.shift_pressed \
			and ka.ctrl_pressed == kb.ctrl_pressed \
			and ka.alt_pressed == kb.alt_pressed \
			and ka.meta_pressed == kb.meta_pressed
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	return false


static func _pack(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key := event as InputEventKey
		return {
			"kind": "key",
			"physical_keycode": int(key.physical_keycode),
			"keycode": int(key.keycode),
			"shift": key.shift_pressed,
			"ctrl": key.ctrl_pressed,
			"alt": key.alt_pressed,
			"meta": key.meta_pressed,
		}
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		return {
			"kind": "mouse",
			"button_index": int(button.button_index),
		}
	return {}


static func _unpack(data: Dictionary) -> InputEvent:
	var kind := str(data.get("kind", ""))
	if kind == "key":
		var key := InputEventKey.new()
		key.physical_keycode = int(data.get("physical_keycode", 0)) as Key
		key.keycode = int(data.get("keycode", 0)) as Key
		key.shift_pressed = bool(data.get("shift", false))
		key.ctrl_pressed = bool(data.get("ctrl", false))
		key.alt_pressed = bool(data.get("alt", false))
		key.meta_pressed = bool(data.get("meta", false))
		return key
	if kind == "mouse":
		var button := InputEventMouseButton.new()
		button.button_index = int(data.get("button_index", MOUSE_BUTTON_LEFT)) as MouseButton
		return button
	return null
