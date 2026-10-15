extends SceneTree

const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _Tutorial = preload("res://ui/tutorial_overlay.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL %s" % msg)


func _ok(msg: String) -> void:
	print("OK %s" % msg)


func _run() -> void:
	_GameplayInput.pause_open = false
	_GameplayInput.world_loading = false
	_GameplayInput.dev_chat_open = false
	var pause := CanvasLayer.new()
	pause.set_script(load("res://ui/pause_menu.gd"))
	root.add_child(pause)
	await process_frame
	var menu = pause.get("_settings")
	var tabs := menu.find_child("SettingsTabs", true, false) as TabContainer
	if tabs == null or tabs.get_tab_count() < 5:
		_fail("settings tabs missing")
		_finish()
		return
	var titles: PackedStringArray = PackedStringArray()
	for i in tabs.get_tab_count():
		titles.append(tabs.get_tab_title(i))
	for need in ["Graphics", "Audio", "Display", "Accessibility", "Controls"]:
		if need not in titles:
			_fail("missing settings tab %s" % need)

	for i in tabs.get_tab_count():
		_open_settings(pause, menu, tabs, i)
		if tabs.get_tab_title(i) == "Controls":
			_Tutorial.open_controls(self)
			if _Tutorial._inst == null or not is_instance_valid(_Tutorial._inst) or not _Tutorial._inst.visible:
				_fail("controls overlay did not open")
		var preset: Control = menu.find_child("QualityPreset", true, false) as Control
		if preset:
			preset.grab_focus()
		if i % 2 == 0:
			_press_esc(pause, menu)
			_ok("Esc closed tab %s" % tabs.get_tab_title(i))
		else:
			var close_btn := menu.find_child("SettingsClose", true, false) as Button
			if close_btn == null:
				_fail("no Close button")
			else:
				close_btn.pressed.emit()
				_ok("Close button hid tab %s" % tabs.get_tab_title(i))
		_assert_closed(pause, menu, "tab %s" % tabs.get_tab_title(i))

	_open_settings(pause, menu, tabs, titles.find("Controls"))
	menu._begin_listen("jump")
	if not menu.is_rebind_listening():
		_fail("rebind listen did not start")
	_press_esc(pause, menu)
	if menu.is_rebind_listening():
		_fail("Esc did not cancel the key rebind")
	elif not pause.visible or not _GameplayInput.pause_open:
		_fail("Esc during rebind closed Settings")
	else:
		_ok("Esc cancels rebind and leaves Settings open")
	_press_esc(pause, menu)
	_assert_closed(pause, menu, "second Esc")

	_open_settings(pause, menu, tabs, 0)
	var resume := pause.find_child("Resume", true, false) as Button
	if resume == null:
		_fail("Resume button missing")
	else:
		resume.pressed.emit()
		_assert_closed(pause, menu, "Resume")
		_ok("Resume closes settings")

	Input.action_press("move_forward")
	if _GameplayInput.blocks_actions():
		_fail("gameplay input still blocked after close")
	elif not Input.is_action_pressed("move_forward"):
		_fail("move_forward was not seen after close")
	else:
		_ok("gameplay input is processed again")
	Input.action_release("move_forward")
	_finish()


func _open_settings(pause: CanvasLayer, menu, tabs: TabContainer, index: int) -> void:
	pause.open()
	var box: CanvasItem = pause.get("_settings_box")
	if box:
		box.visible = true
	if menu and menu.has_method("sync_from_settings"):
		menu.sync_from_settings()
	tabs.current_tab = index


func _press_esc(pause: Node, menu) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.echo = false
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	var listening: bool = menu != null and menu.has_method("is_rebind_listening") and menu.is_rebind_listening()
	if menu and menu.has_method("_input"):
		menu._input(ev)
	if listening:
		return
	var overlay = _Tutorial._inst
	if overlay != null and is_instance_valid(overlay) and overlay.visible and overlay.has_method("_unhandled_input"):
		overlay._unhandled_input(ev)
		return
	if pause.has_method("_unhandled_input"):
		pause._unhandled_input(ev)


func _assert_closed(pause: Node, menu, tag: String) -> void:
	if pause.visible:
		_fail("%s: pause still visible" % tag)
	if _GameplayInput.pause_open or _GameplayInput.blocks_actions():
		_fail("%s: gameplay still blocked" % tag)
	var focus := root.gui_get_focus_owner()
	if focus != null:
		_fail("%s: focus still on %s" % [tag, focus])
	if menu and menu.has_method("is_rebind_listening") and menu.is_rebind_listening():
		_fail("%s: rebind still listening" % tag)
	var tabs: TabContainer = null
	if menu:
		tabs = menu.find_child("SettingsTabs", true, false) as TabContainer
	if tabs:
		for i in tabs.get_tab_count():
			var page := tabs.get_tab_control(i)
			if page and page.is_visible_in_tree():
				_fail("%s: tab %s still visible" % [tag, page.name])
	if _Tutorial._inst != null and is_instance_valid(_Tutorial._inst) and _Tutorial._inst.visible:
		_fail("%s: controls overlay still visible" % tag)


func _finish() -> void:
	_GameplayInput.pause_open = false
	_GameplayInput.world_loading = false
	paused = false
	if _failed > 0:
		quit(1)
		return
	print("All settings close tests OK")
	quit(0)
