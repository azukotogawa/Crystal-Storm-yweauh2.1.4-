extends CanvasLayer

var clock_text := "0:00.00"
var chapter_text := ""

var _clock: Label
var _chapter: Label


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_clock = _corner_label(false)
	_chapter = _corner_label(true)
	_apply()


func set_readout(clock: String, chapter: String) -> void:
	clock_text = clock
	chapter_text = chapter
	if is_node_ready():
		_apply()


func _apply() -> void:
	if _clock != null:
		_clock.text = clock_text
	if _chapter != null:
		_chapter.text = chapter_text


func _corner_label(on_right: bool) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 8)
	if on_right:
		label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		label.offset_left = -520.0
		label.offset_right = -16.0
		label.offset_top = 16.0
		label.offset_bottom = 56.0
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	else:
		label.set_position(Vector2(16.0, 184.0))
	add_child(label)
	return label
