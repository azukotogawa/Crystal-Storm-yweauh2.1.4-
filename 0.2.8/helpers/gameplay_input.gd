class_name GameplayInput
extends RefCounted


static var dev_chat_open := false
static var world_loading := false
static var pause_open := false
static var map_open := false


static func blocks_actions() -> bool:
	return dev_chat_open or world_loading or pause_open or map_open


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