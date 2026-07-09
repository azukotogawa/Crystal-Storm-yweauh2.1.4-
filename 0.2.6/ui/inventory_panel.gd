extends Control

const _Inventory = preload("res://inventory/inventory.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _WeaponController = preload("res://weapons/weapon_controller.gd")
const _GameVisualRegistry = preload("res://systems/game_visual_registry.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")


var _player: Player
var _grid: GridContainer
var _visible_panel := false
var _registry: _GameVisualRegistry


func _ready() -> void:
	visible = false

func _enter_tree() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player and _player.inventory:
		_player.inventory.changed.connect(_refresh)
	_build_ui()
	call_deferred("_bind_registry")


func _bind_registry() -> void:
	_registry = get_tree().get_first_node_in_group("game_visual_registry")
	if _registry and _registry.has_method("ensure_textures_ready"):
		await _registry.ensure_textures_ready()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if _GameplayInput.blocks_actions():
		return
	if event.is_action_pressed("inventory_toggle"):
		_visible_panel = not _visible_panel
		visible = _visible_panel
		if _visible_panel:
			_refresh()


func _build_ui() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.45)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -220
	panel.offset_right = 220
	panel.offset_top = -180
	panel.offset_bottom = 180

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.14, 0.95)
	style.border_color = Color(0.45, 0.45, 0.55)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Inventory"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	_grid = GridContainer.new()
	_grid.columns = 8
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(_grid)

	for i in _Inventory.TOTAL_SLOTS:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(48, 40)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_slot_pressed.bind(i))
		_grid.add_child(btn)

	add_child(panel)


func _on_slot_pressed(index: int) -> void:
	if _player == null or _player.inventory == null:
		return
	# Simple click: move item to first empty hotbar slot
	var slot = _player.inventory.get_slot(index)
	if slot == null:
		return
	for h in _Inventory.HOTBAR_SIZE:
		if _player.inventory.get_hotbar_item(h) == null:
			_player.inventory.swap_slots(index, h)
			var weapon := _player.get_node_or_null("WeaponController") as _WeaponController
			if weapon:
				weapon.set_active_hotbar_index(h)
			return


func _refresh() -> void:
	if _grid == null or _player == null or _player.inventory == null:
		return
	for i in _grid.get_child_count():
		var btn := _grid.get_child(i) as Button
		var slot = _player.inventory.get_slot(i)
		if slot == null:
			btn.text = ""
			btn.icon = null
			btn.tooltip_text = ""
		else:
			var tex: Texture2D = null
			if _registry == null:
				_registry = get_tree().get_first_node_in_group("game_visual_registry")
			if _registry and _registry.has_method("get_item_texture"):
				tex = _registry.get_item_texture(str(slot.id))
			btn.icon = tex
			btn.expand_icon = true
			var count_suffix := ""
			if int(slot.count) > 1:
				count_suffix = "x%d" % int(slot.count)
			btn.text = count_suffix
			btn.tooltip_text = _ItemTypes.display_name(slot.id)