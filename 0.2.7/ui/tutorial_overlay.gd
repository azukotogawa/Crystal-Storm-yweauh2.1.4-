class_name TutorialOverlay
extends CanvasLayer
## First-run steps. Shown once unless reopened. Headless play does not auto-open it.
## The controls page lists the bindings that are active right now.

const _PlayerSettings = preload("res://systems/player_settings.gd")
const _InputBindings = preload("res://systems/input_bindings.gd")
const _ThemeBuilder = preload("res://ui/theme/theme_builder.gd")

static var _inst: TutorialOverlay

var _title: Label
var _body: Label
var _step_label: Label
var _steps: PackedStringArray = []
var _index: int = 0
var _controls: bool = false
var _next: Button


static func wants_tutorial() -> bool:
	return not _PlayerSettings.tutorial_completed


static func should_show() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return wants_tutorial()


static func open(tree: SceneTree, force: bool = false) -> void:
	if tree == null:
		return
	if not force and not should_show():
		return
	var layer := _ensure(tree)
	if layer:
		layer.show_steps()


static func open_controls(tree: SceneTree) -> void:
	if tree == null:
		return
	var layer := _ensure(tree)
	if layer:
		layer.show_controls()


static func _ensure(tree: SceneTree) -> TutorialOverlay:
	if _inst != null and is_instance_valid(_inst):
		return _inst
	var layer := TutorialOverlay.new()
	layer.layer = 70
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(layer)
	return layer


func _ready() -> void:
	_inst = self
	layer = 70
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 280)
	_ThemeBuilder.apply(panel)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	box.add_child(_title)
	_step_label = Label.new()
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_step_label)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(420, 120)
	box.add_child(_body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_on_back)
	row.add_child(back)
	_next = Button.new()
	_next.text = "Next"
	_next.pressed.connect(_on_next)
	row.add_child(_next)
	var controls := Button.new()
	controls.text = "Controls"
	controls.pressed.connect(show_controls)
	row.add_child(controls)
	var skip := Button.new()
	skip.text = "Skip"
	skip.pressed.connect(_finish)
	row.add_child(skip)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(close_overlay)
	row.add_child(close)


func _exit_tree() -> void:
	if _inst == self:
		_inst = null


func show_steps() -> void:
	_controls = false
	_index = 0
	_steps = _build_steps()
	visible = true
	_render()


func show_controls() -> void:
	_controls = true
	visible = true
	if _title:
		_title.text = "Controls"
	if _step_label:
		_step_label.text = "Current bindings"
	if _body:
		_body.text = _controls_text()
	if _next:
		_next.text = "Done"


func close_overlay() -> void:
	visible = false
	queue_free()


func _build_steps() -> PackedStringArray:
	var move := "%s %s %s %s" % [
		_InputBindings.binding_text("move_forward"),
		_InputBindings.binding_text("move_left"),
		_InputBindings.binding_text("move_back"),
		_InputBindings.binding_text("move_right"),
	]
	var yaw := "%s / %s" % [
		_InputBindings.binding_text("rotate_left"),
		_InputBindings.binding_text("rotate_right"),
	]
	var attack := _InputBindings.binding_text("attack")
	var place := _InputBindings.binding_text("build_place")
	return PackedStringArray([
		"Move with %s. The camera is isometric, so forward follows the view." % move,
		"Rotate the camera with %s. Turn until the path you want is in front of you." % yaw,
		"Attack the crystal with %s. Weapons hit the crystal and creatures. They do not dig." % attack,
		"Dig and build with the pick. %s digs or removes. %s places a wall. Shift places a gate. Ctrl places a bridge." % [attack, place],
		"The spawn arrow on the objective HUD points at the nearest crystal heart. Follow it when you are ready to strike.",
		"Win by defeating the Origin Warden, or by destroying every crystal heart. The origin heart stays sealed until the lesser hearts and the warden are dealt with.",
	])


func _controls_text() -> String:
	var lines: PackedStringArray = []
	for action in _InputBindings.ACTIONS:
		lines.append("%s — %s" % [_InputBindings.label_of(action), _InputBindings.binding_text(action)])
	return "\n".join(lines)


func _render() -> void:
	if _title:
		_title.text = "How to play"
	if _steps.is_empty():
		return
	if _step_label:
		_step_label.text = "Step %d of %d" % [_index + 1, _steps.size()]
	if _body:
		_body.text = _steps[_index]
	if _next:
		_next.text = "Done" if _index >= _steps.size() - 1 else "Next"


func _on_back() -> void:
	if _controls:
		show_steps()
		return
	if _index > 0:
		_index -= 1
		_render()


func _on_next() -> void:
	if _controls:
		_finish()
		return
	if _index >= _steps.size() - 1:
		_finish()
		return
	_index += 1
	_render()


func _finish() -> void:
	_PlayerSettings.set_tutorial_completed(true)
	close_overlay()
