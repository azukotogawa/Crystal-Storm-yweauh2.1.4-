extends SceneTree
## Regression: F3 debug overlay toggle + F11 bug-report bundle schema.


const _BugReporter = preload("res://systems/bug_reporter.gd")
const _DevToolsCoordinator = preload("res://systems/dev_tools_coordinator.gd")
const _DeveloperAssistant = preload("res://systems/developer_assistant.gd")
const _DebugPanel = preload("res://ui/debug_panel.gd")
const _ScenarioPresets = preload("res://helpers/scenario_presets.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false

	for path in [
		"res://systems/bug_reporter.gd",
		"res://systems/dev_tools_coordinator.gd",
		"res://helpers/scenario_presets.gd",
	]:
		var scr: GDScript = load(path) as GDScript
		if scr == null or scr.reload() != OK:
			push_error("FAIL compile %s" % path)
			failed = true
		else:
			print("OK compile ", path)

	if not InputMap.has_action("debug_overlay_toggle"):
		push_error("missing debug_overlay_toggle action")
		failed = true
	elif not InputMap.has_action("bug_report"):
		push_error("missing bug_report action")
		failed = true
	else:
		print("OK input actions F3/F11 registered")

	var panel := _DebugPanel.new()
	var label := Label.new()
	panel.add_child(label)
	panel.name = "DebugLabel"
	label.name = "DebugLabel"
	root.add_child(panel)
	await process_frame

	if not panel.is_overlay_visible():
		push_error("debug panel should start visible when enabled")
		failed = true
	else:
		print("OK debug overlay starts visible")

	panel.toggle_overlay()
	if panel.is_overlay_visible():
		push_error("overlay still visible after toggle off")
		failed = true
	else:
		print("OK debug overlay toggle off")

	panel.toggle_overlay()
	if not panel.is_overlay_visible():
		push_error("toggle should restore overlay")
		failed = true
	else:
		print("OK debug overlay toggle on")

	var coordinator := _DevToolsCoordinator.new()
	root.add_child(coordinator)
	await process_frame
	if coordinator.is_debug_overlay_visible() != panel.is_overlay_visible():
		push_error("coordinator overlay state mismatch")
		failed = true
	else:
		print("OK coordinator reads overlay state")

	var bundle: Dictionary = _BugReporter.capture(self, false)
	var state_path: String = str(bundle.get("state_path", ""))
	if state_path.is_empty() or not FileAccess.file_exists(state_path):
		push_error("bug state.json missing at %s" % state_path)
		failed = true
	else:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(state_path))
		if not parsed is Dictionary or not parsed.has("fps"):
			push_error("bug state.json schema invalid")
			failed = true
		else:
			print("OK bug report state.json schema")

	var manifest_path: String = str(bundle.get("manifest_path", ""))
	if manifest_path.is_empty() or not FileAccess.file_exists(manifest_path):
		push_error("bug manifest missing")
		failed = true
	else:
		print("OK bug report manifest.json")

	var assistant := _DeveloperAssistant.new()
	root.add_child(assistant)
	await process_frame

	var scenarios := assistant.send_message("/scenarios")
	if "dig_flat" not in scenarios:
		push_error("/scenarios should list dig_flat")
		failed = true
	else:
		print("OK /scenarios lists presets")

	var give_msg := assistant.send_message("/give stone 3")
	if "inventory" not in give_msg and "stone" not in give_msg:
		push_error("/give should fail gracefully with inventory or item hint")
		failed = true
	else:
		print("OK /give without player (graceful)")

	if _ScenarioPresets.list_ids().size() < 4:
		push_error("scenario preset count too low")
		failed = true
	else:
		print("OK scenario preset count=%d" % _ScenarioPresets.list_ids().size())

	if failed:
		print("Dev tools tests FAILED")
		quit(1)
		return
	print("All dev tools tests OK")
	quit(0)