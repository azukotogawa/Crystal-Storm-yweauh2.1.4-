extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	if not _f3_bound():
		push_error("F3 is not bound to debug_overlay_toggle")
		failed = true
	else:
		print("OK F3 action")

	var packed := load("res://scenes/f3_overlay.tscn") as PackedScene
	if packed == null:
		push_error("f3 overlay scene missing")
		quit(1)
		return
	var overlay := packed.instantiate()
	root.add_child(overlay)
	await process_frame
	if overlay.is_overlay_visible():
		push_error("overlay should start hidden")
		failed = true
	else:
		print("OK overlay starts hidden")

	var player := Node3D.new()
	player.add_to_group("player")
	player.position = Vector3(20, 4, 36)
	root.add_child(player)
	overlay.set_overlay_visible(true)
	var text: String = overlay.overlay_text()
	if not text.begins_with("FPS "):
		push_error("missing FPS line: %s" % text)
		failed = true
	elif "pos 20.00 4.00 36.00" not in text:
		push_error("missing position: %s" % text)
		failed = true
	elif "chunk 1 2" not in text:
		push_error("missing chunk: %s" % text)
		failed = true
	else:
		print("OK readout")

	var panel_script: GDScript = load("res://ui/debug_panel.gd") as GDScript
	var panel: Node = panel_script.new()
	var heavy_label := Label.new()
	heavy_label.name = "DebugLabel"
	panel.add_child(heavy_label)
	panel.visible = false
	root.add_child(panel)
	var coord_script: GDScript = load("res://systems/dev_tools_coordinator.gd") as GDScript
	var coord: Node = coord_script.new()
	root.add_child(coord)
	await process_frame
	var heavy_before: bool = panel.visible
	coord.toggle_debug_overlay()
	if overlay.is_overlay_visible():
		push_error("F3 should hide the compact overlay")
		failed = true
	elif panel.visible != heavy_before:
		push_error("heavy debug panel changed on F3")
		failed = true
	else:
		print("OK F3 toggles compact overlay only")

	coord.toggle_debug_overlay()
	if not overlay.is_overlay_visible() or panel.visible != heavy_before:
		push_error("second F3 should show only the compact overlay")
		failed = true
	else:
		print("OK second F3 shows compact overlay")

	if failed:
		push_error("F3 OVERLAY FAILED")
		quit(1)
		return
	print("F3 OVERLAY OK")
	quit(0)


func _f3_bound() -> bool:
	if not InputMap.has_action("debug_overlay_toggle"):
		return false
	for ev in InputMap.action_get_events("debug_overlay_toggle"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_F3:
			return true
	return false
