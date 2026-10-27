class_name ModalPanel
extends Control

signal close_requested

const _ThemeBuilder = preload("res://ui/theme/theme_builder.gd")
const _HudLayout = preload("res://config/hud_layout.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")

const HEIGHT_RATIO := 0.8
const BAR_GAP := 8.0
const FRAME_PAD := 28.0

static var stack: Array = []
static var _last_event: InputEvent

var content: VBoxContainer
var panel: PanelContainer
var scroll: ScrollContainer
var backdrop: ColorRect
var title_label: Label
var close_button: Button
var bar: HBoxContainer
var panel_width: float = 440.0
var _fit_queued := false


func _init(title: String = "", width: float = 440.0) -> void:
	panel_width = width
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ThemeBuilder.apply(self)
	backdrop = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.02, 0.03, 0.06, 0.62)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	panel = PanelContainer.new()
	panel.name = "Frame"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", int(BAR_GAP))
	panel.add_child(box)
	bar = HBoxContainer.new()
	bar.name = "TitleBar"
	title_label = Label.new()
	title_label.name = "Title"
	title_label.text = title
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", 22)
	bar.add_child(title_label)
	var hint := Label.new()
	hint.name = "CloseHint"
	hint.text = "Esc"
	hint.modulate = Color(1, 1, 1, 0.6)
	bar.add_child(hint)
	close_button = Button.new()
	close_button.name = "Close"
	close_button.text = "X"
	close_button.pressed.connect(func(): close_requested.emit())
	bar.add_child(close_button)
	box.add_child(bar)
	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	box.add_child(scroll)
	content = VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	visibility_changed.connect(_on_visibility_changed)
	content.minimum_size_changed.connect(queue_fit)


func _ready() -> void:
	get_viewport().size_changed.connect(queue_fit)
	_on_visibility_changed()


func _exit_tree() -> void:
	stack.erase(self)


static func consumed(event: InputEvent) -> bool:
	return event != null and _last_event == event


func queue_fit() -> void:
	if _fit_queued:
		return
	_fit_queued = true
	call_deferred("fit")


func fit() -> void:
	_fit_queued = false
	if not is_inside_tree():
		return
	var layout := _HudLayout.load_active()
	var view := _HudLayout.view_of(self)
	var safe := layout.safe_area(view)
	var width := minf(panel_width, safe.size.x)
	var chrome := bar.get_combined_minimum_size().y + BAR_GAP + FRAME_PAD
	var cap := minf(view.y * HEIGHT_RATIO, safe.size.y) - chrome
	var want := content.get_combined_minimum_size().y
	scroll.custom_minimum_size = Vector2(width - FRAME_PAD, minf(want, cap))
	panel.custom_minimum_size = Vector2(width, 0.0)
	panel.reset_size()
	var size := panel.get_combined_minimum_size()
	size.x = maxf(size.x, width)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -size.x * 0.5
	panel.offset_right = size.x * 0.5
	panel.offset_top = -size.y * 0.5
	panel.offset_bottom = size.y * 0.5


func open() -> void:
	visible = true
	_on_visibility_changed()


func frame_rect() -> Rect2:
	return panel.get_global_rect()


func is_top() -> bool:
	return not stack.is_empty() and stack.back() == self


func focus_first() -> void:
	var target := _first_focusable(content)
	if target == null:
		target = close_button
	target.grab_focus()


func _first_focusable(node: Node) -> Control:
	for child in node.get_children():
		var c := child as Control
		if c != null and c.visible:
			if c.focus_mode == Control.FOCUS_ALL and not (c is BaseButton and (c as BaseButton).disabled):
				return c
			var inner := _first_focusable(c)
			if inner != null:
				return inner
	return null


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		if not stack.has(self):
			stack.append(self)
		queue_fit()
		call_deferred("focus_first")
	else:
		stack.erase(self)
		var vp := get_viewport() if is_inside_tree() else null
		if vp != null:
			var owner_control := vp.gui_get_focus_owner()
			if owner_control != null and is_ancestor_of(owner_control):
				owner_control.release_focus()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not is_top() or _GameplayInput.dev_chat_open:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and (key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE):
			if _last_event == event:
				return
			_last_event = event
			get_viewport().set_input_as_handled()
			close_requested.emit()
			return
		if key.pressed and (key.keycode == KEY_PAGEDOWN or key.keycode == KEY_PAGEUP):
			var step := scroll.size.y * 0.9
			scroll.scroll_vertical += int(step) if key.keycode == KEY_PAGEDOWN else -int(step)
			get_viewport().set_input_as_handled()
