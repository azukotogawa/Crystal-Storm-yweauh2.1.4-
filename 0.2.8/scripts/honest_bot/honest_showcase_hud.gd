extends CanvasLayer

const _HudLayout = preload("res://config/hud_layout.gd")

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
	var layout := _HudLayout.load_active()
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 8)
	if on_right:
		var view := _view_size()
		var spot: Rect2 = layout.chapter_rect(view)
		label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		label.offset_right = -layout.chapter_margin_right
		label.offset_left = -layout.chapter_margin_right - spot.size.x
		label.offset_top = spot.position.y
		label.offset_bottom = spot.position.y + spot.size.y
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.clip_text = true
	else:
		label.set_position(layout.clock_position())
	add_child(label)
	return label


func _view_size() -> Vector2:
	var tree := get_tree()
	if tree != null and tree.root != null and tree.root.size.x > 1.0:
		return tree.root.size
	return Vector2(1280, 720)
