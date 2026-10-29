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
		if not _GameplayInput.world_loading and not _GameplayInput.dev_chat_open:
			_toggle_debug_overlay()
		get_viewport().set_input_as_handled()
	elif InputMap.has_action("debug_panel_toggle") and event.is_action_pressed("debug_panel_toggle"):
		if not _GameplayInput.world_loading and not _GameplayInput.dev_chat_open:
			print("[DevTools] debug view %s" % ("ON" if toggle_debug_view() else "OFF"))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("bug_report"):
		if not _GameplayInput.world_loading and not _GameplayInput.dev_chat_open:
			_write_bug_report()
		get_viewport().set_input_as_handled()


func toggle_debug_overlay() -> bool:
	if _dev_overlay_blocked():
		return is_debug_overlay_visible()
	var compact := _compact_overlay()
	if compact and compact.has_method("toggle_overlay"):
		return bool(compact.toggle_overlay())
	var panel := _debug_panel()
	if panel and panel.has_method("toggle_overlay"):
		return bool(panel.toggle_overlay())
	return false


func is_debug_overlay_visible() -> bool:
	var compact := _compact_overlay()
	if compact and compact.has_method("is_overlay_visible"):
		return bool(compact.is_overlay_visible())
	var panel := _debug_panel()
	if panel and panel.has_method("is_overlay_visible"):
		return bool(panel.is_overlay_visible())
	return false


func toggle_debug_view() -> bool:
	return set_debug_view(not is_debug_view_visible())


func is_debug_view_visible() -> bool:
	var panel := _debug_panel()
	return panel != null and panel.has_method("is_overlay_visible") and bool(panel.is_overlay_visible())


func set_debug_view(on: bool) -> bool:
	var panel := _debug_panel()
	if panel and panel.has_method("set_overlay_visible"):
		panel.set_overlay_visible(on)
		if on and panel.has_method("refresh_now"):
			panel.refresh_now()
	var insp := get_tree().get_first_node_in_group("live_world_inspector") if get_tree() else null
	if insp != null and "panel_open" in insp:
		insp.panel_open = on
	return is_debug_view_visible()


func _compact_overlay() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("f3_overlay")


func _debug_panel() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("debug_panel")


func write_bug_report() -> Dictionary:
	if _dev_overlay_blocked():
		return {"dir": "", "state_path": "", "manifest_path": "", "blocked": true}
	return _write_bug_report()


func _dev_overlay_blocked() -> bool:
	return _GameplayInput.world_loading or _GameplayInput.dev_chat_open


func _toggle_debug_overlay() -> void:
	var now_visible := toggle_debug_overlay()
	print("[DevTools] debug overlay %s" % ("ON" if now_visible else "OFF"))


func _write_bug_report() -> Dictionary:
	var result: Dictionary = _BugReporter.capture(get_tree(), true)
	print("[DevTools] bug report -> %s" % result.get("dir", "?"))
	bug_report_written.emit(str(result.get("dir", "")))
	return result