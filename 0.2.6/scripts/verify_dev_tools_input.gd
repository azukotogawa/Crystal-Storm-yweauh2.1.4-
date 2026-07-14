extends SceneTree
## Regression: F3/F11 dev shortcuts respect GameplayInput gate; chat blocks, closed allows.


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

	# Chat closed: F3 toggles overlay.
	var visible_before := panel.is_overlay_visible()
	coordinator.toggle_debug_overlay()
	await process_frame
	if panel.is_overlay_visible() == visible_before:
		push_error("F3 should toggle overlay when chat closed")
		failed = true
	else:
		print("OK F3 toggles overlay when chat closed")

	# Chat closed: bug report writes bundle.
	var bundle: Dictionary = coordinator.write_bug_report()
	if bundle.get("state_path", "").is_empty():
		push_error("F11 path should write state when chat closed")
		failed = true
	else:
		print("OK F11 writes bug report when chat closed")

	# Open chat: gameplay blocked.
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

	# Simulate coordinator _unhandled_input with debug_overlay_toggle while chat open.
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

	if failed:
		print("Dev tools input tests FAILED")
		quit(1)
		return
	print("All dev tools input tests OK")
	quit(0)