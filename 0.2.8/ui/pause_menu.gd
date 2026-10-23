extends CanvasLayer

const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _InputBindings = preload("res://systems/input_bindings.gd")
const _ThemeBuilder = preload("res://ui/theme/theme_builder.gd")
const _SettingsMenu = preload("res://ui/settings_menu.gd")
const _TutorialOverlay = preload("res://ui/tutorial_overlay.gd")

var _root: Control
var _settings_box: VBoxContainer
var _settings: _SettingsMenu


func _ready() -> void:
	add_to_group("pause_menu")
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if _GameplayInput.modal_takes_escape(event):
		get_viewport().set_input_as_handled()
		return
	if not _is_pause_event(event):
		return
	if _GameplayInput.dev_chat_open:
		return
	toggle()
	get_viewport().set_input_as_handled()


func _is_pause_event(event: InputEvent) -> bool:
	if event == null:
		return false
	if _InputBindings.matches("pause", event):
		if event is InputEventKey:
			var key := event as InputEventKey
			return key.pressed and not key.echo
		return event.is_pressed()
	if event is InputEventKey:
		var key := event as InputEventKey
		return key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE and _escape_still_pauses()
	return false


func _escape_still_pauses() -> bool:
	if not InputMap.has_action("pause"):
		return true
	for ev in InputMap.action_get_events("pause"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_ESCAPE:
			return true
	return false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	visible = true
	_GameplayInput.pause_open = true
	var skills = get_tree().get_first_node_in_group("skill_tree") if get_tree() else null
	if skills and skills.has_method("close"):
		skills.close()
	get_tree().paused = true
	_sync_settings_widgets()
	_refresh_debug_overlay()
	_ui("ui_open")


func close() -> void:
	if _settings_box:
		_settings_box.visible = false
	if _settings and _settings.has_method("cancel_rebind"):
		_settings.cancel_rebind()
	_TutorialOverlay.dismiss()
	visible = false
	_GameplayInput.pause_open = false
	if get_tree():
		get_tree().paused = false
	var vp := get_viewport()
	if vp:
		vp.gui_release_focus()
	_refresh_debug_overlay()
	_ui("ui_close")


func _refresh_debug_overlay() -> void:
	var panel = get_tree().get_first_node_in_group("debug_panel") if get_tree() else null
	if panel and panel.has_method("refresh_now"):
		panel.refresh_now()


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.06, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_root = CenterContainer.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_ThemeBuilder.apply(_root)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 480)
	_root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	v.add_child(title)
	_btn(v, "Resume", close)
	_btn(v, "Settings", _toggle_settings)
	_settings_box = VBoxContainer.new()
	_settings_box.visible = false
	_settings_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_settings_box)
	_settings = _SettingsMenu.new()
	_settings.custom_minimum_size = Vector2(380, 320)
	_settings_box.add_child(_settings)
	_btn(v, "How to play", func(): _TutorialOverlay.open(get_tree(), true))
	_btn(v, "Controls", func(): _TutorialOverlay.open_controls(get_tree()))
	_btn(v, "Return to World Select", _leave)
	_btn(v, "Quit", _quit)


func _btn(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.name = text
	b.text = text
	b.custom_minimum_size = Vector2(0, 32)
	b.pressed.connect(func(): _ui("ui_click"))
	b.pressed.connect(cb)
	b.mouse_entered.connect(func(): _ui("ui_hover"))
	parent.add_child(b)


func _ui(id: String) -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_ui"):
		audio.play_ui(id)


func _toggle_settings() -> void:
	_settings_box.visible = not _settings_box.visible
	if not _settings_box.visible:
		if _settings and _settings.has_method("cancel_rebind"):
			_settings.cancel_rebind()
		_TutorialOverlay.dismiss()
		var vp := get_viewport()
		if vp:
			vp.gui_release_focus()
	_sync_settings_widgets()


func _sync_settings_widgets() -> void:
	if _settings and _settings.has_method("sync_from_settings"):
		_settings.sync_from_settings()


func _leave() -> void:
	close()
	var game = get_tree().get_first_node_in_group("game")
	if game and game.has_method("return_to_world_select"):
		game.return_to_world_select()
	else:
		get_tree().change_scene_to_file("res://scenes/frontend.tscn")


func _quit() -> void:
	var save = get_tree().get_first_node_in_group("save_game_service")
	if save and save.has_method("save_or_drop_continue"):
		save.save_or_drop_continue()
	get_tree().quit()
