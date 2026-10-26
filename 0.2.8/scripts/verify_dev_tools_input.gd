extends SceneTree


const _DevChatOverlay = preload("res://ui/dev_chat_overlay.gd")
const _DevToolsCoordinator = preload("res://systems/dev_tools_coordinator.gd")
const _DebugPanel = preload("res://ui/debug_panel.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false

	var panel := _DebugPanel.new()
	var label := Label.new()
	panel.add_child(label)
	panel.name = "DebugLabel"
	label.name = "DebugLabel"
	root.add_child(panel)
	await process_frame

	var coordinator := _DevToolsCoordinator.new()
	root.add_child(coordinator)
	await process_frame

	var overlay := _DevChatOverlay.new()
	root.add_child(overlay)
	await process_frame

	var visible_before := panel.is_overlay_visible()
	coordinator.toggle_debug_overlay()
	await process_frame
	if panel.is_overlay_visible() == visible_before:
		push_error("F3 should toggle overlay when chat closed")
		failed = true
	else:
		print("OK F3 toggles overlay when chat closed")

	var bundle: Dictionary = coordinator.write_bug_report()
	if bundle.get("state_path", "").is_empty():
		push_error("F11 path should write state when chat closed")
		failed = true
	else:
		print("OK F11 writes bug report when chat closed")

	var plain_t := InputEventKey.new()
	plain_t.physical_keycode = KEY_T
	plain_t.keycode = KEY_T
	plain_t.pressed = true
	overlay._unhandled_input(plain_t)
	await process_frame
	if not overlay.is_chat_open() or not _GameplayInput.blocks_actions():
		push_error("plain T should open chat and block gameplay")
		failed = true
	else:
		print("OK chat open blocks gameplay")

	var vis_before_chat := panel.is_overlay_visible()
	var f3_blocked := InputEventKey.new()
	f3_blocked.physical_keycode = KEY_F3
	f3_blocked.keycode = KEY_F3
	f3_blocked.pressed = true
	coordinator._unhandled_input(f3_blocked)
	await process_frame
	if panel.is_overlay_visible() != vis_before_chat:
		push_error("F3 must not toggle overlay while chat open")
		failed = true
	else:
		print("OK F3 blocked while chat open")

	var blocked_bundle: Dictionary = coordinator.write_bug_report()
	if not blocked_bundle.get("blocked", false):
		push_error("bug report must be blocked while chat open")
		failed = true
	else:
		print("OK F11 blocked while chat open")

	overlay.call("_close_chat")
	await process_frame
	if _GameplayInput.blocks_actions():
		push_error("chat close must unblock gameplay")
		failed = true
	else:
		print("OK chat close unblocks gameplay")

	overlay._unhandled_input(plain_t)
	await process_frame
	var f3 := InputEventKey.new()
	f3.physical_keycode = KEY_F3
	f3.keycode = KEY_F3
	f3.pressed = true
	coordinator._unhandled_input(f3)
	await process_frame
	if not overlay.is_chat_open():
		push_error("F3 event should not close chat")
		failed = true
	var vis_locked := panel.is_overlay_visible()
	coordinator._unhandled_input(f3)
	await process_frame
	if panel.is_overlay_visible() != vis_locked:
		push_error("coordinator F3 must not toggle while blocks_actions")
		failed = true
	else:
		print("OK coordinator F3 respects blocks_actions")

	overlay.call("_close_chat")
	await process_frame

	if InputMap.has_action("channel_water"):
		push_error("channel_water action must not exist")
		failed = true
	else:
		print("OK no channel_water action")

	var leaked: Array = []
	for dir in ["world", "weapons", "systems", "ui", "player", "helpers", "fluids", "scripts"]:
		_scan_for_channel_tool("res://" + dir, leaked)
	if not leaked.is_empty():
		push_error("try_channel_water still referenced in %s" % str(leaked))
		failed = true
	else:
		print("OK no try_channel_water in game code")

	var seen: Dictionary = {}
	var clashes: Array = []
	for action in InputMap.get_actions():
		if str(action).begins_with("ui_"):
			continue
		for ev in InputMap.action_get_events(action):
			if not ev is InputEventKey:
				continue
			var key := "%d|%s|%s|%s|%s" % [ev.physical_keycode, ev.shift_pressed, ev.ctrl_pressed, ev.alt_pressed, ev.meta_pressed]
			if seen.has(key) and seen[key] != action:
				clashes.append("%s/%s" % [seen[key], action])
			seen[key] = action
	if not clashes.is_empty():
		push_error("duplicate key plus modifier actions %s" % str(clashes))
		failed = true
	else:
		print("OK no duplicate key plus modifier actions")

	if failed:
		print("Dev tools input tests FAILED")
		quit(1)
		return
	print("All dev tools input tests OK")
	quit(0)

func _scan_for_channel_tool(path: String, leaked: Array) -> void:
	for file in DirAccess.get_files_at(path):
		if not file.ends_with(".gd") or file == "verify_dev_tools_input.gd" or file == "verify_water_body.gd":
			continue
		if "try_channel_water" in FileAccess.get_file_as_string(path + "/" + file):
			leaked.append(path + "/" + file)
	for sub in DirAccess.get_directories_at(path):
		_scan_for_channel_tool(path + "/" + sub, leaked)
