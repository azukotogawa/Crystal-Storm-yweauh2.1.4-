class_name ThemeBuilder
extends RefCounted
## Crystal Storm UI theme. Built in code from Pixelify Sans (see assets/fonts/README.md).
## UI scale is Window.content_scale_factor, so these sizes stay the 100% design size.

const FONT_PATH := "res://assets/fonts/PixelifySans.ttf"

const COL_TEXT := Color(0.93, 0.95, 0.98, 1.0)
const COL_MUTED := Color(0.62, 0.74, 0.86, 1.0)
const COL_ACCENT := Color(0.78, 0.62, 1.0, 1.0)
const COL_PANEL := Color(0.07, 0.08, 0.14, 0.96)
const COL_PANEL_BORDER := Color(0.48, 0.32, 0.78, 0.85)
const COL_BUTTON := Color(0.12, 0.14, 0.22, 1.0)
const COL_BUTTON_HOVER := Color(0.22, 0.16, 0.36, 1.0)
const COL_BUTTON_PRESS := Color(0.36, 0.22, 0.55, 1.0)
const COL_BUTTON_DISABLED := Color(0.10, 0.10, 0.14, 0.8)
const COL_SLIDER := Color(0.16, 0.14, 0.24, 1.0)
const COL_LINE := Color(0.10, 0.11, 0.16, 1.0)

static var _theme: Theme
static var _font: Font


static func font() -> Font:
	if _font != null:
		return _font
	var loaded := load(FONT_PATH) as Font
	if loaded == null:
		_font = ThemeDB.fallback_font
		return _font
	var variation := FontVariation.new()
	variation.base_font = loaded
	variation.variation_opentype = {"wght": 520}
	_font = variation
	return _font


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var built := Theme.new()
	var face := font()
	built.default_font = face
	built.default_font_size = 16
	_style_label(built)
	_style_button(built, "Button")
	_style_button(built, "CheckBox")
	_style_button(built, "OptionButton")
	_style_panel(built)
	_style_slider(built)
	_style_line(built)
	_style_progress(built)
	_style_tooltip(built)
	_theme = built
	return _theme


static func apply(node: Node) -> void:
	if node == null:
		return
	if node is Control:
		(node as Control).theme = theme()
		return
	if node is CanvasLayer:
		for child in node.get_children():
			apply(child)


static func _flat(bg: Color, border: Color, radius: int, margin: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin
	box.content_margin_bottom = margin
	return box


static func _style_label(built: Theme) -> void:
	built.set_color("font_color", "Label", COL_TEXT)
	built.set_color("font_shadow_color", "Label", Color(0.05, 0.04, 0.1, 0.8))
	built.set_font_size("font_size", "Label", 16)


static func _style_button(built: Theme, type_name: String) -> void:
	built.set_font_size("font_size", type_name, 16)
	built.set_color("font_color", type_name, COL_TEXT)
	built.set_color("font_hover_color", type_name, COL_ACCENT)
	built.set_color("font_pressed_color", type_name, Color(1, 1, 1, 1))
	built.set_color("font_disabled_color", type_name, Color(0.55, 0.55, 0.62, 1))
	built.set_color("font_focus_color", type_name, COL_ACCENT)
	built.set_stylebox("normal", type_name, _flat(COL_BUTTON, COL_PANEL_BORDER, 4, 6))
	built.set_stylebox("hover", type_name, _flat(COL_BUTTON_HOVER, COL_ACCENT, 4, 6))
	built.set_stylebox("pressed", type_name, _flat(COL_BUTTON_PRESS, Color(0.9, 0.8, 1.0, 1), 4, 6))
	built.set_stylebox("disabled", type_name, _flat(COL_BUTTON_DISABLED, Color(0.25, 0.25, 0.3, 0.6), 4, 6))
	built.set_stylebox("focus", type_name, _flat(COL_BUTTON_HOVER, COL_ACCENT, 4, 6))


static func _style_panel(built: Theme) -> void:
	built.set_stylebox("panel", "PanelContainer", _flat(COL_PANEL, COL_PANEL_BORDER, 8, 10))


static func _style_slider(built: Theme) -> void:
	var track := _flat(COL_SLIDER, Color(0.35, 0.28, 0.5, 0.8), 3, 0)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	var fill := _flat(Color(0.55, 0.36, 0.85, 1), Color(0, 0, 0, 0), 3, 0)
	var grab := _flat(COL_ACCENT, Color(0.95, 0.9, 1.0, 1), 5, 2)
	built.set_stylebox("slider", "HSlider", track)
	built.set_stylebox("grabber_area", "HSlider", fill)
	built.set_stylebox("grabber_area_highlight", "HSlider", fill)
	built.set_stylebox("grabber", "HSlider", grab)


static func _style_line(built: Theme) -> void:
	built.set_color("font_color", "LineEdit", COL_TEXT)
	built.set_color("font_placeholder_color", "LineEdit", COL_MUTED)
	built.set_stylebox("normal", "LineEdit", _flat(COL_LINE, COL_PANEL_BORDER, 4, 6))
	built.set_stylebox("focus", "LineEdit", _flat(Color(0.14, 0.12, 0.22, 1), COL_ACCENT, 4, 6))


static func _style_progress(built: Theme) -> void:
	built.set_stylebox("background", "ProgressBar", _flat(Color(0.08, 0.06, 0.12, 1), Color(0.3, 0.2, 0.4, 0.8), 3, 1))
	built.set_stylebox("fill", "ProgressBar", _flat(Color(0.72, 0.28, 1.0, 1), Color(0, 0, 0, 0), 3, 1))


static func _style_tooltip(built: Theme) -> void:
	var tip := _flat(Color(0.06, 0.05, 0.1, 0.96), Color(0.72, 0.5, 1.0, 0.95), 6, 8)
	built.set_stylebox("panel", "TooltipPanel", tip)
	built.set_color("font_color", "TooltipPanel", COL_TEXT)
	built.set_font_size("font_size", "TooltipPanel", 15)
