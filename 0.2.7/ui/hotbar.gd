extends Control

const _Inventory = preload("res://inventory/inventory.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _GameVisualRegistry = preload("res://systems/game_visual_registry.gd")

const SLOT_SIZE := 52
const SLOT_GAP := 6

var _player: Player
const _WeaponController = preload("res://weapons/weapon_controller.gd")

var _weapon: _WeaponController
var _slot_nodes: Array[PanelContainer] = []
var _icon_nodes: Array[TextureRect] = []
var _label_nodes: Array[Label] = []
var _registry: _GameVisualRegistry


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		_weapon = _player.get_node_or_null("WeaponController") as _WeaponController
		if _player.inventory:
			_player.inventory.changed.connect(_refresh)
			_player.inventory.hotbar_changed.connect(_on_hotbar_changed)
	_build_slots()
	call_deferred("_bind_registry")
	call_deferred("_refresh")


func _bind_registry() -> void:
	_registry = get_tree().get_first_node_in_group("game_visual_registry")
	if _registry and _registry.has_method("ensure_textures_ready"):
		await _registry.ensure_textures_ready()
	_refresh()


func _build_slots() -> void:
	var total_w := _Inventory.HOTBAR_SIZE * SLOT_SIZE + (_Inventory.HOTBAR_SIZE - 1) * SLOT_GAP
	custom_minimum_size = Vector2(total_w, SLOT_SIZE + 8)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -total_w * 0.5
	offset_right = total_w * 0.5
	offset_top = -SLOT_SIZE - 24
	offset_bottom = -16

	for i in _Inventory.HOTBAR_SIZE:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		panel.position = Vector2(i * (SLOT_SIZE + SLOT_GAP), 0)

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.08, 0.12, 0.82)
		style.border_color = Color(0.35, 0.35, 0.45, 1.0)
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		panel.add_theme_stylebox_override("panel", style)

		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(SLOT_SIZE - 8, SLOT_SIZE - 8)
		icon.size = Vector2(SLOT_SIZE - 8, SLOT_SIZE - 8)
		icon.position = Vector2(4, 2)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(icon)

		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		label.position = Vector2(2, SLOT_SIZE - 18)
		label.size = Vector2(SLOT_SIZE - 4, 16)
		label.add_theme_font_size_override("font_size", 9)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(label)

		add_child(panel)
		_slot_nodes.append(panel)
		_icon_nodes.append(icon)
		_label_nodes.append(label)


func _on_hotbar_changed(_index: int) -> void:
	_refresh()


func _refresh() -> void:
	if _player == null or _player.inventory == null:
		return
	if _registry == null:
		_registry = get_tree().get_first_node_in_group("game_visual_registry")
	var active := 0
	if _weapon:
		active = _weapon.get_active_hotbar_index()

	for i in _Inventory.HOTBAR_SIZE:
		var slot = _player.inventory.get_hotbar_item(i)
		var panel := _slot_nodes[i]
		var style: StyleBoxFlat = panel.get_theme_stylebox("panel").duplicate()
		if i == active:
			style.border_color = Color(0.95, 0.78, 0.25, 1.0)
			style.bg_color = Color(0.14, 0.12, 0.08, 0.92)
		else:
			style.border_color = Color(0.35, 0.35, 0.45, 1.0)
			style.bg_color = Color(0.08, 0.08, 0.12, 0.82)
		panel.add_theme_stylebox_override("panel", style)

		var icon := _icon_nodes[i]
		var label := _label_nodes[i]
		if slot == null:
			icon.texture = null
			label.text = str(i + 1)
		else:
			var tex: Texture2D = null
			if _registry and _registry.has_method("get_item_texture"):
				tex = _registry.get_item_texture(str(slot.id))
			icon.texture = tex
			if int(slot.count) > 1:
				label.text = "x%d" % int(slot.count)
			else:
				label.text = ""