class_name TooltipPanel
extends CanvasLayer
## Hidden tooltips do not run _process.

const _TooltipText = preload("res://ui/tooltip_text.gd")
const _ThemeBuilder = preload("res://ui/theme/theme_builder.gd")

static var _inst: TooltipPanel

var _panel: PanelContainer
var _label: Label


static func show_item(tree: SceneTree, item_id: String) -> void:
	var tip := _ensure(tree)
	if tip:
		tip.present(_TooltipText.for_item(item_id))


static func show_relic(tree: SceneTree, relic_id: String) -> void:
	var tip := _ensure(tree)
	if tip:
		tip.present(_TooltipText.for_relic(relic_id))


static func hide_tip() -> void:
	if _inst != null and is_instance_valid(_inst):
		_inst.dismiss()


static func _ensure(tree: SceneTree) -> TooltipPanel:
	if tree == null:
		return null
	if _inst != null and is_instance_valid(_inst):
		return _inst
	var tip := TooltipPanel.new()
	tip.layer = 90
	tip.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(tip)
	_inst = tip
	return tip


func _ready() -> void:
	_inst = self
	layer = 90
	_panel = PanelContainer.new()
	_panel.name = "Tip"
	_panel.theme_type_variation = "TooltipPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	_ThemeBuilder.apply(_panel)
	var label := Label.new()
	label.name = "Body"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(280, 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.theme_type_variation = "TooltipPanel"
	_panel.add_child(label)
	_label = label
	add_child(_panel)
	set_process(false)


func _exit_tree() -> void:
	if _inst == self:
		_inst = null


func present(text: String) -> void:
	if _label == null:
		return
	_label.text = text
	_panel.visible = true
	_panel.reset_size()
	set_process(true)
	_place()


func dismiss() -> void:
	if _panel:
		_panel.visible = false
	set_process(false)


func current_text() -> String:
	if _label == null:
		return ""
	return _label.text


func _process(_delta: float) -> void:
	if _panel == null or not _panel.visible:
		set_process(false)
		return
	_place()


func _place() -> void:
	if _panel == null:
		return
	var view := get_viewport().get_visible_rect().size
	var size := _panel.get_combined_minimum_size()
	if size.x < 8.0:
		size = _panel.size
	var mouse := get_viewport().get_mouse_position()
	var pos := mouse + Vector2(18, 18)
	if pos.x + size.x > view.x - 4.0:
		pos.x = mouse.x - size.x - 12.0
	if pos.y + size.y > view.y - 4.0:
		pos.y = mouse.y - size.y - 12.0
	pos.x = clampf(pos.x, 4.0, maxf(4.0, view.x - size.x - 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(4.0, view.y - size.y - 4.0))
	_panel.position = pos
	_panel.size = size
