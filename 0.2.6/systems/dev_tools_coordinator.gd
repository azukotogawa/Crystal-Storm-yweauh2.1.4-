class_name DevToolsCoordinator
extends Node

const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _BugReporter = preload("res://systems/bug_reporter.gd")

signal bug_report_written(report_dir: String)


func _enter_tree() -> void:
	add_to_group("dev_tools_coordinator")
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_overlay_toggle"):
		if not _GameplayInput.blocks_actions():
			_toggle_debug_overlay()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("bug_report"):
		if not _GameplayInput.blocks_actions():
			_write_bug_report()
		get_viewport().set_input_as_handled()


func toggle_debug_overlay() -> bool:
	if _GameplayInput.blocks_actions():
		return is_debug_overlay_visible()
	var panel: Node = get_tree().get_first_node_in_group("debug_panel")
	if panel and panel.has_method("toggle_overlay"):
		return bool(panel.toggle_overlay())
	return false


func is_debug_overlay_visible() -> bool:
	var panel: Node = get_tree().get_first_node_in_group("debug_panel")
	if panel and panel.has_method("is_overlay_visible"):
		return bool(panel.is_overlay_visible())
	return false


func write_bug_report() -> Dictionary:
	if _GameplayInput.blocks_actions():
		return {"dir": "", "state_path": "", "manifest_path": "", "blocked": true}
	return _write_bug_report()


func _toggle_debug_overlay() -> void:
	var now_visible := toggle_debug_overlay()
	print("[DevTools] debug overlay %s" % ("ON" if now_visible else "OFF"))


func _write_bug_report() -> Dictionary:
	var result: Dictionary = _BugReporter.capture(get_tree(), true)
	print("[DevTools] bug report -> %s" % result.get("dir", "?"))
	bug_report_written.emit(str(result.get("dir", "")))
	return result