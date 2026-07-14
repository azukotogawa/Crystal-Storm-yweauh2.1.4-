extends SceneTree
## Regression: DeveloperAssistant local commands + response file bridge.


const _DeveloperAssistant = preload("res://systems/developer_assistant.gd")
const _DevChatOverlay = preload("res://ui/dev_chat_overlay.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var assistant := _DeveloperAssistant.new()
	root.add_child(assistant)
	await process_frame

	var help := assistant.send_message("/help")
	if "Slash commands" not in help and "slash cheats" not in help:
		push_error("slash /help failed")
		failed = true
	else:
		print("OK slash help")

	var req := assistant.send_message("probe ping from verify_dev_chat")
	if "Sent to AI assistant" not in req:
		push_error("forward to assistant failed")
		failed = true
	else:
		print("OK forward request")

	var req_path := assistant.get_assistant_dir().path_join(_DeveloperAssistant.REQUEST_LOG)
	if not FileAccess.file_exists(req_path):
		push_error("request log missing")
		failed = true
	else:
		print("OK request log exists")

	var req_id := ""
	for line in FileAccess.get_file_as_string(req_path).split("\n"):
		if "probe ping" in line:
			var parsed: Variant = JSON.parse_string(line.strip_edges())
			if parsed is Dictionary:
				req_id = str(parsed.get("id", ""))
	if req_id.is_empty():
		push_error("could not find request id")
		failed = true
	else:
		assistant.write_external_response(req_id, "verify pong")
		await process_frame
		await process_frame
		print("OK external response bridge")

	var shift_t := InputEventKey.new()
	shift_t.physical_keycode = KEY_T
	shift_t.keycode = KEY_T
	shift_t.shift_pressed = true
	shift_t.pressed = true
	if not shift_t.is_action_pressed("channel_water", true):
		push_error("Shift+T should match channel_water exactly")
		failed = true
	else:
		print("OK Shift+T matches channel_water")

	var plain_t := InputEventKey.new()
	plain_t.physical_keycode = KEY_T
	plain_t.keycode = KEY_T
	plain_t.pressed = true
	if plain_t.is_action_pressed("channel_water", true):
		push_error("plain T must not match channel_water (Shift+T only)")
		failed = true
	elif not plain_t.is_action_pressed("dev_chat_toggle", true):
		push_error("plain T should match dev_chat_toggle exactly")
		failed = true
	else:
		print("OK plain T matches dev_chat_toggle only")

	var overlay := _DevChatOverlay.new()
	root.add_child(overlay)
	await process_frame
	overlay._unhandled_input(shift_t)
	await process_frame
	if overlay.is_chat_open():
		push_error("Shift+T must not open dev chat overlay")
		failed = true
	elif _GameplayInput.blocks_actions():
		push_error("Shift+T must not block gameplay input via dev chat")
		failed = true
	else:
		print("OK Shift+T does not open dev chat")

	overlay._unhandled_input(plain_t)
	await process_frame
	if not overlay.is_chat_open():
		push_error("plain T should open dev chat overlay")
		failed = true
	else:
		print("OK plain T opens dev chat")

	if not overlay.visible:
		push_error("dev chat overlay should be visible after plain T")
		failed = true

	if not _GameplayInput.blocks_actions():
		push_error("dev chat open must block gameplay input")
		failed = true
	else:
		print("OK gameplay input blocked while chat open")

	overlay.call("_close_chat")
	await process_frame
	if _GameplayInput.blocks_actions():
		push_error("dev chat close must unblock gameplay input")
		failed = true
	else:
		print("OK gameplay input unblocked after close")

	var malformed := '{"id":"req_mal_1","response":"a"}{"id":"req_mal_2","response":"b"}'
	var salvaged: Array = _DeveloperAssistant._parse_jsonl_fragments(malformed)
	if salvaged.size() != 2:
		push_error("jsonl salvage expected 2 entries, got %d" % salvaged.size())
		failed = true
	else:
		print("OK jsonl salvage count=%d" % salvaged.size())

	if failed:
		print("Dev chat tests FAILED")
		quit(1)
		return
	print("All dev chat tests OK")
	quit(0)