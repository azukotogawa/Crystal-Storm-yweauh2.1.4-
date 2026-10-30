extends Control
class_name DevChatOverlay

const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _HudLayout = preload("res://config/hud_layout.gd")
const _DevCommandGate = preload("res://helpers/dev_command_gate.gd")

const MIN_PANEL_HEIGHT := 72.0
const MAX_PANEL_HEIGHT := 280.0

var _assistant: Node
var _panel: PanelContainer
var _spacer: Control
var _history: Label
var _line_edit: LineEdit
var _open := false
var _history_lines: PackedStringArray = []


func _enter_tree() -> void:
	add_to_group("dev_chat_overlay")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_unhandled_input(true)
	_ensure_slash_binding()


func _ready() -> void:
	visible = false
	_build_ui()
	call_deferred("_bind_assistant")


func is_chat_open() -> bool:
	return _open


func _bind_assistant() -> void:
	_assistant = get_tree().get_first_node_in_group("developer_assistant")
	if _assistant and not _assistant.response_ready.is_connected(_on_assistant_response):
		_assistant.response_ready.connect(_on_assistant_response)


func _place_in_layout() -> void:
	var rect := _HudLayout.load_active().region(_HudLayout.view_of(self), "chat")
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_left = rect.position.x
	offset_right = rect.end.x
	offset_top = rect.end.y - MIN_PANEL_HEIGHT
	offset_bottom = rect.end.y


func _build_ui() -> void:
	_place_in_layout()
	if not get_viewport().size_changed.is_connected(_place_in_layout):
		get_viewport().size_changed.connect(_place_in_layout)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.1, 0.88)
	style.border_color = Color(0.35, 0.55, 0.85, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 8.0
	vbox.offset_top = 6.0
	vbox.offset_right = -8.0
	vbox.offset_bottom = -6.0
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	var hint := Label.new()
	hint.text = "Dev commands — / opens, Enter sends, Esc closes"
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(0.75, 0.82, 0.95)
	vbox.add_child(hint)

	_spacer = Control.new()
	_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_spacer)

	_history = Label.new()
	_history.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_history.custom_minimum_size = Vector2(0, 28)
	_history.size_flags_vertical = Control.SIZE_SHRINK_END
	_history.add_theme_font_size_override("font_size", 12)
	_history.text = ""
	vbox.add_child(_history)

	_line_edit = LineEdit.new()
	_line_edit.size_flags_vertical = Control.SIZE_SHRINK_END
	_line_edit.placeholder_text = "Ask the AI assistant or type /help ..."
	_line_edit.clear_button_enabled = true
	_line_edit.text_submitted.connect(_on_text_submitted)
	vbox.add_child(_line_edit)


func _input(event: InputEvent) -> void:
	if not _open or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and (key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE):
		_close_chat()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not _DevCommandGate.allowed():
		return
	if event.is_action_pressed("dev_chat_toggle"):
		if _open:
			get_viewport().set_input_as_handled()
			return
		var slash := _is_slash_key(event)
		_open_chat()
		if slash and _line_edit != null:
			_line_edit.text = "/"
			_line_edit.caret_column = 1
		get_viewport().set_input_as_handled()
	elif _open and event.is_action_pressed("ui_cancel"):
		_close_chat()
		get_viewport().set_input_as_handled()


func _toggle_chat() -> void:
	if _open:
		_close_chat()
	else:
		_open_chat()


func _open_chat() -> void:
	if not _DevCommandGate.allowed():
		return
	_open = true
	_GameplayInput.set_dev_chat_open(true)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _assistant == null:
		_bind_assistant()
	_sync_panel_height()
	_line_edit.grab_focus()
	_line_edit.caret_column = _line_edit.text.length()


func _close_chat() -> void:
	_open = false
	_GameplayInput.set_dev_chat_open(false)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line_edit.release_focus()


func _on_text_submitted(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return
	_append_history("You: %s" % trimmed)
	_line_edit.text = ""
	if _assistant == null:
		_bind_assistant()
	if _assistant:
		_assistant.send_message(trimmed)
	else:
		_append_history("Assistant: DeveloperAssistant node missing")


func _on_assistant_response(text: String) -> void:
	if text.is_empty():
		return
	_append_history("Assistant: %s" % text)


func _append_history(line: String) -> void:
	_history_lines.append(line)
	while _history_lines.size() > 6:
		_history_lines.remove_at(0)
	_history.text = "\n".join(_history_lines)
	call_deferred("_sync_panel_height")


func _ensure_slash_binding() -> void:
	if not _DevCommandGate.allowed():
		return
	if not InputMap.has_action("dev_chat_toggle"):
		InputMap.add_action("dev_chat_toggle")
	for ev in InputMap.action_get_events("dev_chat_toggle"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_SLASH:
			return
	var slash := InputEventKey.new()
	slash.physical_keycode = KEY_SLASH
	InputMap.action_add_event("dev_chat_toggle", slash)


func _is_slash_key(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false
	var key := event as InputEventKey
	if key.shift_pressed or key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
		return false
	return key.physical_keycode == KEY_SLASH or key.keycode == KEY_SLASH or key.unicode == 47


func _sync_panel_height() -> void:
	if _panel == null:
		return
	var content_h := _panel.get_combined_minimum_size().y + 12.0
	content_h = clampf(content_h, MIN_PANEL_HEIGHT, MAX_PANEL_HEIGHT)
	offset_top = offset_bottom - content_h
