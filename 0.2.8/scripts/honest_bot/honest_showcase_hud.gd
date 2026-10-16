extends CanvasLayer

var clock_text := "0:00.00"
var chapter_text := ""

var _clock: Label
var _chapter: Label


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_clock = _label(16.0)
	_chapter = _label(52.0)
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


func _label(y: float) -> Label:
	var label := Label.new()
	label.set_position(Vector2(16.0, y))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 8)
	add_child(label)
	return label
