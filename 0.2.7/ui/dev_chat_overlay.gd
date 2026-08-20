extends Control
class_name DevChatOverlay
## Lightweight dev chat: T toggles bottom LineEdit; Enter sends to DeveloperAssistant.

const _GameplayInput = preload("res://helpers/gameplay_input.gd")

const MIN_PANEL_HEIGHT := 72.0
const MAX_PANEL_HEIGHT := 280.0

var _assistant: Node
var _panel: PanelContainer
var _spacer: Control
var _history: Label
var _input: LineEdit
var _open := false
var _history_lines: PackedStringArray = []


func _enter_tree() -> void:
	add_to_group("dev_chat_overlay")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_unhandled_input(true)


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


func _build_ui() -> void:
	anchor_left = 0.0
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_top = -MIN_PANEL_HEIGHT
	offset_bottom = 0.0

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
	hint.text = "Dev Assistant — Enter send, Esc close (type freely while open)"
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

	_input = LineEdit.new()
	_input.size_flags_vertical = Control.SIZE_SHRINK_END
	_input.placeholder_text = "Ask the AI assistant or type /help ..."
	_input.clear_button_enabled = true
	_input.text_submitted.connect(_on_text_submitted)
	vbox.add_child(_input)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("dev_chat_toggle"):
		if _open:
			# T is a normal typing key while chat is open — only Esc closes.
			get_viewport().set_input_as_handled()
			return
		_open_chat()
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
	_open = true
	_GameplayInput.set_dev_chat_open(true)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _assistant == null:
		_bind_assistant()
	_sync_panel_height()
	_input.grab_focus()
	_input.caret_column = _input.text.length()


func _close_chat() -> void:
	_open = false
	_GameplayInput.set_dev_chat_open(false)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_input.release_focus()


func _on_text_submitted(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return
	_append_history("You: %s" % trimmed)
	_input.text = ""
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


func _sync_panel_height() -> void:
	if _panel == null:
		return
	var content_h := _panel.get_combined_minimum_size().y + 12.0
	content_h = clampf(content_h, MIN_PANEL_HEIGHT, MAX_PANEL_HEIGHT)
	offset_top = -content_h