class_name RelicChoicePanel
extends Control
## Pauses the run and offers three relics. Process mode stays on while time is slowed.

const _RelicRegistry = preload("res://relics/relic_registry.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")

static var _open: RelicChoicePanel
static var _pending: Array = []

var _ids: Array[StringName] = []
var _relic_mgr = null
var _title_text: String = "Choose a relic"
var _saved_scale: float = 1.0
var _paused_here: bool = false


static func open(tree: SceneTree, relic_mgr, ids: Array, title: String) -> void:
	if ids.size() < 3 or tree == null:
		return
	if _open != null and is_instance_valid(_open):
		_pending.append({"mgr": relic_mgr, "ids": ids, "title": title})
		return
	var panel := RelicChoicePanel.new()
	panel._ids = ids
	panel._relic_mgr = relic_mgr
	panel._title_text = title
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var host = tree.get_first_node_in_group("game_overlay")
	if host == null:
		host = tree.root
	host.add_child(panel)
	_open = panel


func _ready() -> void:
	_RelicRegistry.ensure_builtins()
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 40
	_saved_scale = Engine.time_scale
	Engine.time_scale = 0.05
	if not _GameplayInput.pause_open:
		_GameplayInput.pause_open = true
		_paused_here = true
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.0, 0.05, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -240
	panel.offset_right = 240
	panel.offset_top = -160
	panel.offset_bottom = 160
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.12, 0.96)
	style.border_color = Color(0.72, 0.45, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := Label.new()
	title.text = _title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)

	var hint := Label.new()
	hint.text = "Pick one of three. The run is slowed until you choose."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	for relic_id in _ids:
		var def = _RelicRegistry.get_def(relic_id)
		var btn := Button.new()
		var label := str(relic_id)
		var blurb := ""
		if def:
			label = def.display_name
			blurb = def.description
		btn.text = label if blurb == "" else "%s — %s" % [label, blurb]
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.custom_minimum_size = Vector2(0, 48)
		btn.pressed.connect(_pick.bind(relic_id))
		box.add_child(btn)


func _pick(relic_id: StringName) -> void:
	if _relic_mgr and _relic_mgr.has_method("equip"):
		var ok: bool = bool(_relic_mgr.equip(relic_id))
		if not ok:
			var overlay = get_tree().get_first_node_in_group("game_overlay") if is_inside_tree() else null
			if overlay and overlay.has_method("_show_toast"):
				overlay.call("_show_toast", "Relic slots are full")
	_close()


func _close() -> void:
	if _open == self:
		_open = null
	if _pending.is_empty():
		Engine.time_scale = _saved_scale if _saved_scale > 0.0 else 1.0
		if _paused_here:
			_GameplayInput.pause_open = false
	queue_free()
	if not _pending.is_empty() and is_inside_tree():
		var next: Dictionary = _pending.pop_front()
		open(get_tree(), next.get("mgr"), next.get("ids", []), str(next.get("title", "Choose a relic")))
