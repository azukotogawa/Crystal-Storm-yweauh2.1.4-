class_name SlotDrag
extends CanvasLayer
## Inventory and hotbar drag.
## Left click is also the attack button, so a press on a slot releases that
## action before WeaponController's poll. Godot's built-in drag accumulates
## mouse relative; after window stretch that relative is often zero, so this
## lifts from press→motion→release using the cursor position instead.


const _Inventory = preload("res://inventory/inventory.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _TooltipPanel = preload("res://ui/tooltip_panel.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")

const DRAG_THRESHOLD := 8

static var _inst: SlotDrag

var _pending := false
var _origin := -1
var _held_id := ""
var _held_count := 0
var _inv = null
## Set when a drag drops, so the release that ends it does not also click.
var _drop_click_block := false
var _armed := false
var _press_pos := Vector2.ZERO
var _press_control: Control = null
var _slot_controls: Array[Control] = []
var _preview: Control = null


static func register_slot(tree: SceneTree, control: Control, index: int, on_click: Callable) -> void:
	if control == null:
		return
	control.mouse_filter = Control.MOUSE_FILTER_STOP
	control.set_meta(&"slot_index", index)
	control.set_meta(&"slot_click", on_click)
	if control.has_meta(&"slot_drag_wired"):
		_ensure(tree)
		if _inst != null and is_instance_valid(_inst):
			_inst._track(control)
		return
	control.set_meta(&"slot_drag_wired", true)
	control.gui_input.connect(_on_slot_gui.bind(control))
	_ensure(tree)
	if _inst != null and is_instance_valid(_inst):
		_inst._track(control)


static func register_passthrough(control: Control) -> void:
	bind_click_shield(control)


static func bind_click_shield(control: Control) -> void:
	if control == null or control.has_meta(&"slot_shield"):
		return
	control.set_meta(&"slot_shield", true)
	control.gui_input.connect(_shield_gui)


static func set_modal_open(_open: bool, _root: Control = null) -> void:
	pass


static func cancel() -> void:
	if _inst == null or not is_instance_valid(_inst):
		return
	_inst._cancel_drag()


static func _ensure(tree: SceneTree) -> void:
	if tree == null:
		return
	if _inst != null and is_instance_valid(_inst):
		return
	var node := SlotDrag.new()
	node.layer = 15
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	_inst = node
	# Root is still inserting the game scene during early _ready.
	tree.root.call_deferred("add_child", node)


static func _on_slot_gui(event: InputEvent, control: Control) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed:
			Input.action_release("build_place")
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		Input.action_release("attack")
		_TooltipPanel.hide_tip()
		if _inst != null and is_instance_valid(_inst):
			_inst._arm(control, mb.position)
		return
	# Release is handled in _input so a drop still lands after the cursor
	# leaves the origin slot. Ignore it here to avoid a second click.


static func _shield_gui(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		Input.action_release("attack")
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		Input.action_release("build_place")


func _ready() -> void:
	_inst = self
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	var vp := get_viewport()
	if vp:
		vp.gui_drag_threshold = DRAG_THRESHOLD


func _exit_tree() -> void:
	if _pending:
		_place(_inv, _origin, _held_id, _held_count)
		_pending = false
	if _inst == self:
		_inst = null


func _input(event: InputEvent) -> void:
	if not _armed and not _pending:
		return
	if event is InputEventMouseMotion:
		_on_mouse_move((event as InputEventMouseMotion).position)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_on_mouse_up(mb.position)
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _armed and not _pending:
		set_process(false)
		return
	if _GameplayInput.blocks_actions():
		_cancel_drag()


func _track(control: Control) -> void:
	if control == null:
		return
	for existing in _slot_controls:
		if existing == control:
			return
	_slot_controls.append(control)


func _arm(control: Control, local_pos: Vector2) -> void:
	_drop_click_block = false
	_armed = true
	_press_control = control
	_press_pos = control.get_global_transform_with_canvas() * local_pos
	set_process(true)


func _on_mouse_move(canvas: Vector2) -> void:
	if not _armed:
		return
	if not _pending:
		if canvas.distance_to(_press_pos) < DRAG_THRESHOLD:
			return
		if _press_control == null or not is_instance_valid(_press_control):
			_armed = false
			return
		if _lift(_press_control) == null:
			_armed = false
			return
	_move_preview(canvas)


func _on_mouse_up(canvas: Vector2) -> void:
	if not _armed:
		return
	_armed = false
	if not _pending:
		_try_click(canvas)
		return
	var dest := _slot_at(canvas)
	if dest != null and is_instance_valid(dest):
		_accept(dest, {
			"kind": "slot",
			"index": _origin,
			"id": _held_id,
			"count": _held_count,
		})
	else:
		_place(_inv, _origin, _held_id, _held_count)
		_clear_held()
	_hide_preview()


func _try_click(canvas: Vector2) -> void:
	if _drop_click_block:
		_drop_click_block = false
		return
	var control := _press_control
	_press_control = null
	if control == null or not is_instance_valid(control):
		return
	if not control.get_global_rect().has_point(canvas):
		return
	var on_click: Callable = control.get_meta(&"slot_click", Callable())
	if on_click.is_valid():
		on_click.call()


func _cancel_drag() -> void:
	_armed = false
	if _pending:
		_place(_inv, _origin, _held_id, _held_count)
		_clear_held()
	_hide_preview()
	var vp := get_viewport()
	if vp and vp.gui_is_dragging():
		vp.gui_cancel_drag()


func _slot_at(canvas: Vector2) -> Control:
	var best: Control = null
	var best_area := INF
	var live: Array[Control] = []
	for control in _slot_controls:
		if control == null or not is_instance_valid(control):
			continue
		live.append(control)
		if not control.is_visible_in_tree():
			continue
		var rect := control.get_global_rect()
		if not rect.has_point(canvas):
			continue
		var area := rect.size.x * rect.size.y
		if best == null or area < best_area:
			best = control
			best_area = area
		elif area == best_area and control.is_greater_than(best):
			best = control
	_slot_controls = live
	return best


func _lift(control: Control) -> Variant:
	if _pending:
		return null
	var inv = _player_inventory()
	var index := int(control.get_meta(&"slot_index", -1))
	if inv == null or index < 0:
		return null
	var slot = inv.get_slot(index)
	if slot == null:
		return null
	_pending = true
	_origin = index
	_held_id = str(slot.id)
	_held_count = int(slot.count)
	_inv = inv
	inv.clear_slot(index)
	Input.action_release("attack")
	_TooltipPanel.hide_tip()
	_show_preview(_held_id, _held_count)
	set_process(true)
	return {"kind": "slot", "index": index, "id": _held_id, "count": _held_count}


func _accept(control: Control, data: Variant) -> void:
	if not _pending or not (data is Dictionary):
		return
	_drop_click_block = true
	var index := int(control.get_meta(&"slot_index", -1))
	var origin := int(data.get("index", _origin))
	var item_id := str(data.get("id", _held_id))
	var count := int(data.get("count", _held_count))
	var inv = _inv
	_clear_held()
	_apply_drop(inv, origin, index, item_id, count)


func _clear_held() -> void:
	_pending = false
	_origin = -1
	_held_id = ""
	_held_count = 0
	_inv = null
	_press_control = null


func _apply_drop(inv, origin: int, index: int, item_id: String, count: int) -> void:
	if inv == null or item_id == "" or count <= 0:
		return
	if index < 0 or index == origin:
		_place(inv, origin, item_id, count)
		return
	var dest = inv.get_slot(index)
	if dest == null:
		inv.set_slot(index, item_id, count)
		_ui_click()
		return
	var dest_id := str(dest.id)
	var dest_count := int(dest.count)
	if dest_id == item_id and _ItemTypes.is_stackable(item_id):
		var space := _ItemTypes.max_stack_for(item_id) - dest_count
		var moved := mini(maxi(space, 0), count)
		if moved > 0:
			inv.set_slot(index, item_id, dest_count + moved)
			count -= moved
			_ui_click()
		if count > 0:
			_place(inv, origin, item_id, count)
		return
	inv.set_slot(index, item_id, count)
	if inv.get_slot(origin) == null:
		inv.set_slot(origin, dest_id, dest_count)
	else:
		_place(inv, origin, dest_id, dest_count)
	_ui_click()


func _place(inv, index: int, item_id: String, count: int) -> void:
	if inv == null or item_id == "" or count <= 0:
		return
	if index >= 0 and inv.get_slot(index) == null:
		inv.set_slot(index, item_id, count)
		return
	var left := int(inv.add_item(item_id, count))
	if left <= 0:
		return
	for i in _Inventory.TOTAL_SLOTS:
		var slot = inv.get_slot(i)
		if slot != null and str(slot.id) == item_id:
			inv.set_slot(i, item_id, int(slot.count) + left)
			return


func _player_inventory():
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return null
	return player.get("inventory")


func _show_preview(item_id: String, count: int) -> void:
	_hide_preview()
	_preview = _make_preview(item_id, count)
	add_child(_preview)


func _move_preview(canvas: Vector2) -> void:
	if _preview == null or not is_instance_valid(_preview):
		return
	_preview.position = canvas + Vector2(12, 12)


func _hide_preview() -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null


func _make_preview(item_id: String, count: int) -> Control:
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size = Vector2(140, 40)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var registry := get_tree().get_first_node_in_group("game_visual_registry")
	if registry and registry.has_method("get_item_texture"):
		icon.texture = registry.get_item_texture(_ItemTypes.visual_key(item_id))
	row.add_child(icon)
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name := _ItemTypes.display_name(item_id)
	label.text = name if count <= 1 else "%s x%d" % [name, count]
	row.add_child(label)
	return box


func _ui_click() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_ui"):
		audio.play_ui("ui_click")
