extends Control

const _Skills = preload("res://systems/skill_service.gd")
const _InputBindings = preload("res://systems/input_bindings.gd")
const _ThemeBuilder = preload("res://ui/theme/theme_builder.gd")

const SLOT_W := 104
const SLOT_H := 40
const SLOT_GAP := 8
const ABOVE_HOTBAR := 96

var _panels: Array[Panel] = []
var _sweeps: Array[ColorRect] = []
var _names: Array[Label] = []
var _keys: Array[Label] = []
var _cooldowns: Array[Label] = []


func _ready() -> void:
	_ThemeBuilder.apply(self)
	var total_w := _Skills.ACTIVE_SLOTS * SLOT_W + (_Skills.ACTIVE_SLOTS - 1) * SLOT_GAP
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -total_w * 0.5
	offset_right = total_w * 0.5
	offset_top = -ABOVE_HOTBAR - SLOT_H
	offset_bottom = -ABOVE_HOTBAR
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in _Skills.ACTIVE_SLOTS:
		_add_slot(i)


func _add_slot(i: int) -> void:
	var panel := Panel.new()
	panel.position = Vector2(i * (SLOT_W + SLOT_GAP), 0)
	panel.size = Vector2(SLOT_W, SLOT_H)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.85)
	style.border_color = Color(0.35, 0.35, 0.45, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var sweep := ColorRect.new()
	sweep.color = Color(0.0, 0.0, 0.0, 0.55)
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(sweep)

	var name_label := _label(panel, Vector2(6, 2), Vector2(SLOT_W - 12, 18), 13)
	var key_label := _label(panel, Vector2(6, SLOT_H - 18), Vector2(SLOT_W - 12, 16), 11)
	var cd_label := _label(panel, Vector2(0, 0), Vector2(SLOT_W - 6, SLOT_H), 18)
	cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_panels.append(panel)
	_sweeps.append(sweep)
	_names.append(name_label)
	_keys.append(key_label)
	_cooldowns.append(cd_label)


func _label(parent: Control, at: Vector2, label_size: Vector2, font: int) -> Label:
	var label := Label.new()
	label.position = at
	label.size = label_size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font)
	parent.add_child(label)
	return label


func slot_text(i: int) -> Dictionary:
	return {
		"name": _names[i].text,
		"key": _keys[i].text,
		"cooldown": _cooldowns[i].text,
	}


func _process(_delta: float) -> void:
	var svc = _Skills.get_active()
	for i in _panels.size():
		var skill: StringName = svc.slot_skill(i) if svc != null else &""
		var left: float = svc.cooldown_left(i) if svc != null else 0.0
		_keys[i].text = _InputBindings.binding_text(_Skills.HOTKEY_ACTIONS[i])
		_names[i].text = String(skill).replace("_", " ").capitalize() if skill != &"" else "Empty"
		_cooldowns[i].text = "%.1f" % left if left > 0.0 else ""
		var total := float(svc.def_for(skill).get("cooldown", 1.0)) if svc != null and skill != &"" else 1.0
		var frac := clampf(left / maxf(total, 0.01), 0.0, 1.0)
		_sweeps[i].position = Vector2(0, 0)
		_sweeps[i].size = Vector2(SLOT_W, SLOT_H * frac)
		_panels[i].modulate.a = 0.45 if skill == &"" or left > 0.0 else 1.0
