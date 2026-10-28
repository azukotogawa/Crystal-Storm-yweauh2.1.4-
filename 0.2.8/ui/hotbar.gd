extends Control

const _Inventory = preload("res://inventory/inventory.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _GameVisualRegistry = preload("res://systems/game_visual_registry.gd")
const _ThemeBuilder = preload("res://ui/theme/theme_builder.gd")
const _TooltipPanel = preload("res://ui/tooltip_panel.gd")
const _SlotDrag = preload("res://ui/slot_drag.gd")
const _HudLayout = preload("res://config/hud_layout.gd")

const SLOT_SIZE := 52
const SLOT_GAP := 6

var _player: Node
const _WeaponController = preload("res://weapons/weapon_controller.gd")

var _weapon: _WeaponController
var _slot_nodes: Array[PanelContainer] = []
var _icon_nodes: Array[TextureRect] = []
var _label_nodes: Array[Label] = []
var _registry: _GameVisualRegistry
var _name_label: Label
var _name_age := 0.0
var _last_active := -1

const NAME_SHOW_SEC := 1.4


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		_weapon = _player.get_node_or_null("WeaponController") as _WeaponController
		if _player.inventory:
			_player.inventory.changed.connect(_refresh)
			_player.inventory.hotbar_changed.connect(_on_hotbar_changed)
	_ThemeBuilder.apply(self)
	_build_slots()
	call_deferred("_bind_registry")
	call_deferred("_refresh")


func _bind_registry() -> void:
	_registry = get_tree().get_first_node_in_group("game_visual_registry")
	if _registry and _registry.has_method("ensure_textures_ready"):
		await _registry.ensure_textures_ready()
	_refresh()


func _place_in_layout() -> void:
	var layout := _HudLayout.load_active()
	var rect := layout.region(_HudLayout.view_of(self), "hotbar")
	var pad := layout.backing_pad
	_HudLayout.place(self, Rect2(rect.position + Vector2(pad, pad), rect.size - Vector2(pad, pad) * 2.0))


func _build_slots() -> void:
	var total_w := _Inventory.HOTBAR_SIZE * SLOT_SIZE + (_Inventory.HOTBAR_SIZE - 1) * SLOT_GAP
	custom_minimum_size = Vector2(total_w, SLOT_SIZE + 8)
	_place_in_layout()
	if not get_viewport().size_changed.is_connected(_place_in_layout):
		get_viewport().size_changed.connect(_place_in_layout)

	# Drawn above the inventory dimmer. Picking ignores z_index, so the bag
	# also moves this bar to the front of the canvas while it is open.
	z_index = 2
	z_as_relative = false
	_add_backing(total_w)
	_build_name_label()
	for i in _Inventory.HOTBAR_SIZE:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		panel.size = Vector2(SLOT_SIZE, SLOT_SIZE)
		panel.position = Vector2(i * (SLOT_SIZE + SLOT_GAP), 0)

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.08, 0.07, 0.88)
		style.border_color = Color(0.22, 0.16, 0.1, 1.0)
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		panel.add_theme_stylebox_override("panel", style)

		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(SLOT_SIZE - 8, SLOT_SIZE - 8)
		icon.size = Vector2(SLOT_SIZE - 8, SLOT_SIZE - 8)
		icon.position = Vector2(4, 2)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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

		panel.mouse_entered.connect(_on_slot_hover.bind(i))
		panel.mouse_exited.connect(_on_slot_unhover)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(panel)
		_SlotDrag.register_slot(get_tree(), panel, i, _on_slot_click.bind(i))
		_slot_nodes.append(panel)
		_icon_nodes.append(icon)
		_label_nodes.append(label)


func _build_name_label() -> void:
	_name_label = Label.new()
	_name_label.name = "HotbarItemName"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.size = Vector2(size.x if size.x > 0.0 else custom_minimum_size.x, 20)
	_name_label.position = Vector2(0, -_HudLayout.load_active().hotbar_name_h - _HudLayout.load_active().backing_pad)
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.modulate.a = 0.0
	add_child(_name_label)


func name_text() -> String:
	return _name_label.text if _name_label != null else ""


func _process(delta: float) -> void:
	if _name_label == null:
		return
	_name_age += delta
	_name_label.modulate.a = clampf((NAME_SHOW_SEC - _name_age) * 2.0, 0.0, 1.0)


func _add_backing(total_w: float) -> void:
	var layout := _HudLayout.load_active()
	var pad := layout.backing_pad
	var plate := Panel.new()
	plate.name = "HotbarBacking"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.position = Vector2(-pad, -pad)
	plate.size = Vector2(total_w + pad * 2.0, SLOT_SIZE + pad * 2.0)
	var style := StyleBoxFlat.new()
	style.bg_color = layout.backing
	style.set_corner_radius_all(8)
	plate.add_theme_stylebox_override("panel", style)
	add_child(plate)


func _on_slot_click(index: int) -> void:
	if _player == null or _player.inventory == null:
		return
	var slot = _player.inventory.get_hotbar_item(index)
	if slot == null or not _ItemTypes.is_armor(str(slot.id)):
		return
	_player.inventory.equip_armor(str(slot.id))
	_ui("ui_click")


func _ui(id: String) -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_ui"):
		audio.play_ui(id)


func _on_slot_hover(index: int) -> void:
	if _player == null or _player.inventory == null:
		return
	var slot = _player.inventory.get_hotbar_item(index)
	if slot == null:
		_TooltipPanel.hide_tip()
		return
	_TooltipPanel.show_item(get_tree(), str(slot.id))


func _on_slot_unhover() -> void:
	_TooltipPanel.hide_tip()


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

	if active != _last_active:
		_last_active = active
		var picked = _player.inventory.get_hotbar_item(active)
		_name_label.text = _ItemTypes.display_name(str(picked.id)) if picked != null else ""
		_name_age = 0.0
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
			label.text = str((i + 1) % 10)
		else:
			var tex: Texture2D = null
			if _registry and _registry.has_method("get_item_texture"):
				tex = _registry.get_item_texture(_ItemTypes.visual_key(str(slot.id)))
			icon.texture = tex
			if int(slot.count) > 1:
				label.text = "x%d" % int(slot.count)
			else:
				label.text = ""