class_name GameplayInput
extends RefCounted


static var dev_chat_open := false
static var world_loading := false
static var pause_open := false
static var map_open := false
static var skill_tree_open := false
static var modal_open := false


static func blocks_menus() -> bool:
	return dev_chat_open or world_loading or pause_open or modal_open


static func blocks_actions() -> bool:
	return blocks_menus() or map_open or skill_tree_open


static func modal_takes_escape(event: InputEvent) -> bool:
	if not modal_open or event == null or not event.is_pressed() or event.is_echo():
		return false
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		return true
	if event is InputEventKey:
		var key := event as InputEventKey
		return key.physical_keycode == KEY_ESCAPE or key.keycode == KEY_ESCAPE
	return false


static func set_world_loading(loading: bool) -> void:
	world_loading = loading
	if loading:
		_release_mapped_actions()


static func set_dev_chat_open(open: bool) -> void:
	dev_chat_open = open
	if open:
		_release_mapped_actions()


static func _release_mapped_actions() -> void:
	for action in InputMap.get_actions():
		if Input.is_action_pressed(action):
			Input.action_release(action)