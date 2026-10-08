class_name RelicChoicePanel
extends Control
## Pauses the run and offers three relics. Process mode stays on while time is slowed.

const _RelicRegistry = preload("res://relics/relic_registry.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")

const SLOW_SCALE := 0.05

static var _open: RelicChoicePanel
static var _pending: Array = []
## Pre-modal scale, captured only while no panel is open. A queued offer must not save 0.05.
static var _saved_scale: float = 1.0
static var _scale_held: bool = false
## True when this modal is the one that set pause_open.
static var _modal_paused: bool = false

var _ids: Array[StringName] = []
var _relic_mgr = null
var _title_text: String = "Choose a relic"
var _box: VBoxContainer
var _hint: Label
var _buttons: Array[Button] = []
var _replace_id: StringName = &""
var _choosing_replace: bool = false


static func open(tree: SceneTree, relic_mgr, ids: Array, title: String) -> void:
	if ids.size() < 3 or tree == null:
		return
	if _open != null and is_instance_valid(_open):
		_pending.append({"mgr": relic_mgr, "ids": ids, "title": title})
		return
	if not _scale_held:
		_saved_scale = Engine.time_scale
		_scale_held = true
	var panel := RelicChoicePanel.new()
	var typed: Array[StringName] = []
	for entry in ids:
		typed.append(StringName(str(entry)))
	panel._ids = typed
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
	Engine.time_scale = SLOW_SCALE
	if not _GameplayInput.pause_open:
		_GameplayInput.pause_open = true
		_modal_paused = true
	_build()


func _exit_tree() -> void:
	if _open == self:
		_open = null
	# Scene teardown can free the panel without _close. Restore only when none remain.
	if not _scale_held:
		return
	if _open != null and is_instance_valid(_open):
		return
	_pending.clear()
	_restore_run()


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
	panel.offset_top = -180
	panel.offset_bottom = 180
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.12, 0.96)
	style.border_color = Color(0.72, 0.45, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	panel.add_child(_box)

	var title := Label.new()
	title.text = _title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 18)
	_box.add_child(title)

	_hint = Label.new()
	_hint.text = "Pick one of three. The run is slowed until you choose."
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_hint)

	_show_offers()


func _show_offers() -> void:
	_choosing_replace = false
	_clear_buttons()
	if _hint:
		_hint.text = "Pick one of three. The run is slowed until you choose."
	for relic_id in _ids:
		_add_button(relic_id, "offer", _relic_label(relic_id))


func _show_replace(new_id: StringName) -> void:
	_choosing_replace = true
	_replace_id = new_id
	_clear_buttons()
	if _hint:
		_hint.text = "Relic slots are full. Pick one to replace with %s." % _relic_label(new_id)
	for old_id in _equipped_ids():
		var label := "Replace %s" % _relic_label(StringName(str(old_id)))
		_add_button(StringName(str(old_id)), "replace", label)


func _add_button(relic_id: StringName, role: String, text: String) -> void:
	var btn := Button.new()
	btn.text = text
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.custom_minimum_size = Vector2(0, 48)
	btn.set_meta("relic_role", role)
	btn.set_meta("relic_id", str(relic_id))
	btn.pressed.connect(_on_button.bind(relic_id, role))
	_box.add_child(btn)
	_buttons.append(btn)


func _clear_buttons() -> void:
	for btn in _buttons:
		if is_instance_valid(btn):
			btn.queue_free()
	_buttons.clear()


func _relic_label(relic_id: StringName) -> String:
	var def = _RelicRegistry.get_def(relic_id)
	if def == null:
		return str(relic_id)
	var label: String = def.display_name
	if def.description != "":
		return "%s — %s" % [label, def.description]
	return label


func _on_button(relic_id: StringName, role: String) -> void:
	if role == "replace":
		_apply_replace(relic_id)
		return
	_pick(relic_id)


func _pick(relic_id: StringName) -> void:
	if _relic_mgr and _relic_mgr.has_method("equip"):
		if bool(_relic_mgr.equip(relic_id)):
			_close()
			return
		if _slots_are_full():
			_show_replace(relic_id)
			return
		if _hint:
			_hint.text = "Could not equip that relic."
		return
	_close()


func _apply_replace(old_id: StringName) -> void:
	if _relic_mgr and _relic_mgr.has_method("unequip"):
		_relic_mgr.unequip(old_id)
	var ok := false
	if _relic_mgr and _relic_mgr.has_method("equip"):
		ok = bool(_relic_mgr.equip(_replace_id))
	if not ok:
		if _relic_mgr and _relic_mgr.has_method("equip"):
			_relic_mgr.equip(old_id)
		if _hint:
			_hint.text = "Relic slots are full. Pick one to replace."
		return
	_close()


func _equipped_ids() -> Array:
	if _relic_mgr == null:
		return []
	var raw = null
	if "equipped" in _relic_mgr:
		raw = _relic_mgr.equipped
	elif _relic_mgr.has_method("export_equipped"):
		raw = _relic_mgr.export_equipped()
	if raw is Array:
		return raw.duplicate()
	return []


func _slots_are_full() -> bool:
	if _relic_mgr == null:
		return false
	var max_slots := 3
	if "max_slots" in _relic_mgr:
		max_slots = int(_relic_mgr.max_slots)
	return _equipped_ids().size() >= max_slots


func _close() -> void:
	if _open == self:
		_open = null
	var more := not _pending.is_empty()
	if not more:
		_restore_run()
	queue_free()
	if more and is_inside_tree():
		var next: Dictionary = _pending.pop_front()
		open(get_tree(), next.get("mgr"), next.get("ids", []), str(next.get("title", "Choose a relic")))


func _restore_run() -> void:
	var restore := _saved_scale if _saved_scale > 0.0 else 1.0
	Engine.time_scale = restore
	_scale_held = false
	if _modal_paused:
		_GameplayInput.pause_open = false
		_modal_paused = false
