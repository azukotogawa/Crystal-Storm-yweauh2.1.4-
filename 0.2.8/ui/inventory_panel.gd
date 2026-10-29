extends Control

const _Inventory = preload("res://inventory/inventory.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _WeaponController = preload("res://weapons/weapon_controller.gd")
const _GameVisualRegistry = preload("res://systems/game_visual_registry.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _ThemeBuilder = preload("res://ui/theme/theme_builder.gd")
const _TooltipPanel = preload("res://ui/tooltip_panel.gd")
const _SlotDrag = preload("res://ui/slot_drag.gd")
const _Hotbar = preload("res://ui/hotbar.gd")
const _Blueprints = preload("res://helpers/structure_blueprints.gd")
const _ModalPanel = preload("res://ui/modal_panel.gd")
const _Crafting = preload("res://helpers/structure_crafting.gd")


var _player: Node
var _grid: GridContainer
var _armor_button: Button
var _craft_buttons: Dictionary = {}
var _visible_panel := false
var _modal: Control
var _registry: _GameVisualRegistry
var _raised_hotbar: Control
var _hotbar_index := -1


func _ready() -> void:
	visible = false
	_SlotDrag.set_modal_open(false, self)
	_bind_inventory()
	_refresh()

func _enter_tree() -> void:
	_ThemeBuilder.apply(self)
	_player = get_tree().get_first_node_in_group("player")
	_bind_inventory()
	_build_ui()
	call_deferred("_bind_registry")


func _bind_inventory() -> void:
	if _player == null or not is_instance_valid(_player):
		var tree := get_tree()
		if tree:
			_player = tree.get_first_node_in_group("player")
	if _player == null or _player.inventory == null:
		return
	if not _player.inventory.changed.is_connected(_refresh):
		_player.inventory.changed.connect(_refresh)


func _bind_registry() -> void:
	_registry = get_tree().get_first_node_in_group("game_visual_registry")
	if _registry and _registry.has_method("ensure_textures_ready"):
		await _registry.ensure_textures_ready()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if _GameplayInput.blocks_actions():
		return
	if event.is_action_pressed("inventory_toggle"):
		var opening := not _visible_panel
		if not opening:
			_SlotDrag.cancel()
		_visible_panel = opening
		visible = opening
		_SlotDrag.set_modal_open(opening, self)
		_GameplayInput.set_panel_open(&"inventory", opening)
		_ui("ui_open" if opening else "ui_close")
		if opening:
			# Godot picks the later sibling, and z_index does not change that.
			_raise_hotbar()
			_settle_layout()
			_refresh()
		else:
			_restore_hotbar()


func _close_panel() -> void:
	if not _visible_panel:
		return
	_SlotDrag.cancel()
	_visible_panel = false
	visible = false
	_SlotDrag.set_modal_open(false, self)
	_GameplayInput.set_panel_open(&"inventory", false)
	_ui("ui_close")
	_restore_hotbar()


func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_modal = _ModalPanel.new("Inventory", 520.0)
	_SlotDrag.bind_click_shield(_modal.backdrop)
	_SlotDrag.bind_click_shield(_modal.panel)
	_modal.close_requested.connect(_close_panel)
	var vbox: VBoxContainer = _modal.content

	if _Blueprints.LARGE_STRUCTURES:
		var craft_row := HBoxContainer.new()
		craft_row.name = "CraftRow"
		craft_row.add_theme_constant_override("separation", 6)
		for id in _Blueprints.ids():
			var craft := Button.new()
			if id == _Blueprints.WALL_SEGMENT:
				craft.name = "Craft_wall_segment"
			elif id == _Blueprints.WALL_CORNER:
				craft.name = "Craft_wall_corner"
			elif id == _Blueprints.GATE:
				craft.name = "Craft_gate"
			elif id == _Blueprints.STAIRS:
				craft.name = "Craft_stairs"
			elif id == _Blueprints.SMALL_TOWER:
				craft.name = "Craft_small_tower"
			else:
				craft.name = "Craft_%s" % String(id)
			craft.focus_mode = Control.FOCUS_NONE
			craft.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			craft.pressed.connect(_on_craft_pressed.bind(id))
			craft_row.add_child(craft)
			_craft_buttons[id] = craft
		vbox.add_child(craft_row)

	_armor_button = Button.new()
	_armor_button.name = "ArmorSlot"
	_armor_button.custom_minimum_size = Vector2(0, 36)
	_armor_button.focus_mode = Control.FOCUS_NONE
	_armor_button.text = "Armor: none"
	_armor_button.pressed.connect(_on_armor_pressed)
	_armor_button.mouse_entered.connect(_on_armor_hover)
	_armor_button.mouse_exited.connect(_on_slot_unhover)
	vbox.add_child(_armor_button)

	_grid = GridContainer.new()
	_grid.columns = _Inventory.HOTBAR_SIZE
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(_grid)

	for i in _Inventory.TOTAL_SLOTS:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(48, 40)
		btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_entered.connect(_on_slot_hover.bind(i))
		btn.mouse_exited.connect(_on_slot_unhover)
		btn.size = Vector2(48, 40)
		_grid.add_child(btn)

	add_child(_modal)
	_SlotDrag.register_passthrough(_armor_button)
	for i in _grid.get_child_count():
		_SlotDrag.register_slot(get_tree(), _grid.get_child(i), i, _on_slot_pressed.bind(i))


func _on_slot_pressed(index: int) -> void:
	_ui("ui_click")
	if _player == null or _player.inventory == null:
		return
	var slot = _player.inventory.get_slot(index)
	if slot == null:
		return
	if _ItemTypes.is_armor(str(slot.id)):
		_player.inventory.equip_armor(str(slot.id))
		return
	for h in _Inventory.HOTBAR_SIZE:
		if _player.inventory.get_hotbar_item(h) == null:
			_player.inventory.swap_slots(index, h)
			var weapon := _player.get_node_or_null("WeaponController") as _WeaponController
			if weapon:
				weapon.set_active_hotbar_index(h)
			return


func _on_slot_hover(index: int) -> void:
	if _player == null or _player.inventory == null:
		return
	var slot = _player.inventory.get_slot(index)
	if slot == null:
		_TooltipPanel.hide_tip()
		return
	_TooltipPanel.show_item(get_tree(), str(slot.id))


func _on_armor_hover() -> void:
	if _player == null or _player.inventory == null:
		return
	var worn := str(_player.inventory.armor_id)
	if worn == "":
		_TooltipPanel.hide_tip()
		return
	_TooltipPanel.show_item(get_tree(), worn)


func _on_slot_unhover() -> void:
	_TooltipPanel.hide_tip()


func _on_craft_pressed(id: StringName) -> void:
	if _player == null or _player.inventory == null:
		return
	if _Crafting.craft(_player.inventory, id):
		_ui("ui_click")
	_refresh()


func _on_armor_pressed() -> void:
	Input.action_release("attack")
	_ui("ui_click")
	if _player == null or _player.inventory == null:
		return
	_player.inventory.clear_armor()
	_refresh()


func _refresh() -> void:
	if _grid == null or _player == null or _player.inventory == null:
		return
	_refresh_armor()
	_refresh_craft()
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
				tex = _registry.get_item_texture(_ItemTypes.visual_key(str(slot.id)))
			btn.icon = tex
			btn.expand_icon = true
			var count_suffix := ""
			if int(slot.count) > 1:
				count_suffix = "x%d" % int(slot.count)
			btn.text = count_suffix
			btn.tooltip_text = _ItemTypes.display_name(slot.id)


func _raise_hotbar() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var bar: Control = parent.get_node_or_null("Hotbar") as Control
	if bar == null:
		for child in parent.get_children():
			if child is Control and (child as Node).get_script() == _Hotbar:
				bar = child
				break
	if bar == null or bar == _raised_hotbar:
		return
	_raised_hotbar = bar
	_hotbar_index = bar.get_index()
	parent.move_child(bar, -1)


func _restore_hotbar() -> void:
	if _raised_hotbar == null or not is_instance_valid(_raised_hotbar):
		_raised_hotbar = null
		_hotbar_index = -1
		return
	var parent := _raised_hotbar.get_parent()
	if parent != null:
		var index := clampi(_hotbar_index, 0, parent.get_child_count() - 1)
		parent.move_child(_raised_hotbar, index)
	_raised_hotbar = null
	_hotbar_index = -1


func _settle_layout() -> void:
	_layout_now(self)


func _layout_now(node: Node) -> void:
	if node is Container:
		node.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for child in node.get_children():
		_layout_now(child)


func _ui(id: String) -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_ui"):
		audio.play_ui(id)


func _refresh_craft() -> void:
	for id in _craft_buttons:
		var btn := _craft_buttons[id] as Button
		if btn == null:
			continue
		var bp := _Blueprints.get_blueprint(id)
		var recipe: Array = bp.get("recipe", [])
		var cost := ""
		if not recipe.is_empty():
			var line: Dictionary = recipe[0]
			cost = "  %d %s" % [int(line.get("count", 0)), str(line.get("id", ""))]
		btn.text = "%s%s" % [_ItemTypes.display_name(String(id)), cost]
		btn.disabled = not _Crafting.can_craft(_player.inventory, id)


func _refresh_armor() -> void:
	if _armor_button == null:
		return
	var worn := str(_player.inventory.armor_id)
	if worn == "":
		_armor_button.text = "Armor: none"
		_armor_button.icon = null
		_armor_button.tooltip_text = "Click a leather, stone, or crystal armor in the bag to wear it."
		return
	_armor_button.text = "Armor: %s" % _ItemTypes.display_name(worn)
	_armor_button.tooltip_text = "Worn. Click to put it back in the bag."
	var tex: Texture2D = null
	if _registry and _registry.has_method("get_item_texture"):
		tex = _registry.get_item_texture(_ItemTypes.visual_key(worn))
	_armor_button.icon = tex
	_armor_button.expand_icon = true