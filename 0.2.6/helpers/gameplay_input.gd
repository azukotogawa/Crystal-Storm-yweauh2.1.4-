class_name GameplayInput
extends RefCounted
## Global gate so UI text fields can pause gameplay action polling.


static var dev_chat_open := false


static func blocks_actions() -> bool:
	return dev_chat_open


static func set_dev_chat_open(open: bool) -> void:
	dev_chat_open = open
	if open:
		_release_mapped_actions()


static func _release_mapped_actions() -> void:
	for action in InputMap.get_actions():
		if Input.is_action_pressed(action):
			Input.action_release(action)