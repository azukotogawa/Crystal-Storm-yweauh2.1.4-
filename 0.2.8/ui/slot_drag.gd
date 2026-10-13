class_name SlotDrag
extends CanvasLayer
## Mouse pick-up for inventory and hotbar slots.
## A slot click is also the attack button. Release that action or a held
## pick keeps digging for the whole drag.

const _Inventory = preload("res://inventory/inventory.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _TooltipPanel = preload("res://ui/tooltip_panel.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")

const DRAG_PX2 := 64.0

static var _inst: SlotDrag
static var _zones: Array = []
static var _passthrough: Array = []
static var _modal_open := false
static var _modal_root: Control

var _captured := false
var _lifted := false
var _origin := -1
var _held_id := ""
var _held_count := 0
var _press_pos := Vector2.ZERO
var _press_click: Callable = Callable()
var _inv = null
var _ghost: Control
var _icon: TextureRect
var _count_label: Label


static func register_slot(tree: SceneTree, control: Control, index: int, on_click: Callable) -> void:
	if control == null:
		return
	_prune_zones()
	for i in _zones.size():
		var zone: Dictionary = _zones[i]
		if zone.get("control") == control:
			zone["index"] = index
			zone["on_click"] = on_click
			_ensure(tree)
			return
	_zones.append({
		"control": control,
		"index": index,
		"on_click": on_click,
	})
	_ensure(tree)


static func register_passthrough(control: Control) -> void:
	if control == null:
		return
	if not _passthrough.has(control):
		_passthrough.append(control)


static func set_modal_open(open: bool, root: Control = null) -> void:
	_modal_open = open
	if root != null:
		_modal_root = root


static func cancel() -> void:
	if _inst != null and is_instance_valid(_inst):
		_inst._cancel()


static func _prune_zones() -> void:
	var kept: Array = []
	for zone in _zones:
		if is_instance_valid(zone.get("control")):
			kept.append(zone)
	_zones = kept


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


func _ready() -> void:
	_inst = self
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ghost()
	set_process(false)


func _exit_tree() -> void:
	if _captured and _lifted:
		_place(_inv, _origin, _held_id, _held_count)
	_captured = false
	_lifted = false
	if _inst == self:
		_inst = null


func _process(_delta: float) -> void:
	if _captured and _GameplayInput.blocks_actions():
		_cancel()
	if not _captured:
		set_process(false)


func _input(event: InputEvent) -> void:
	if _GameplayInput.blocks_actions():
		if _captured:
			_cancel()
		return
	if event is InputEventMouseMotion:
		if _captured:
			_drag_motion(_pointer())
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		if _captured and mb.button_index == MOUSE_BUTTON_LEFT:
			_on_left_up(_pointer())
			get_viewport().set_input_as_handled()
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT and _modal_open and _over_modal(_pointer()):
		Input.action_release("build_place")
		if not _over_passthrough(_pointer()):
			get_viewport().set_input_as_handled()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	_on_left_down(_pointer())


func _pointer() -> Vector2:
	return get_viewport().get_mouse_position()


func _on_left_down(pos: Vector2) -> void:
	if _captured:
		return
	var zone := _zone_at(pos)
	if not zone.is_empty():
		# A slot click must not also start a dig or a swing.
		Input.action_release("attack")
		get_viewport().set_input_as_handled()
		var inv = _player_inventory()
		var index := int(zone.get("index", -1))
		if inv == null or inv.get_slot(index) == null:
			return
		_captured = true
		_lifted = false
		_origin = index
		_press_pos = pos
		_press_click = zone.get("on_click", Callable())
		_inv = inv
		_held_id = ""
		_held_count = 0
		set_process(true)
		return
	if not _modal_open or not _over_modal(pos):
		return
	Input.action_release("attack")
	if _over_passthrough(pos):
		return
	get_viewport().set_input_as_handled()


func _drag_motion(pos: Vector2) -> void:
	if not _lifted and _should_lift(pos):
		_lift()
	if _lifted:
		_move_ghost(pos)


func _on_left_up(pos: Vector2) -> void:
	if not _lifted and _should_lift(pos):
		_lift()
	var target := -1
	var zone := _zone_at(pos)
	if not zone.is_empty():
		target = int(zone.get("index", -1))
	var lifted := _lifted
	var origin := _origin
	var inv = _inv
	var item_id := _held_id
	var count := _held_count
	var on_click := _press_click
	_clear_capture()
	if not lifted:
		if target == origin and on_click.is_valid():
			on_click.call()
		return
	_apply_drop(inv, origin, target, item_id, count)


func _should_lift(pos: Vector2) -> bool:
	if pos.distance_squared_to(_press_pos) >= DRAG_PX2:
		return true
	var zone := _zone_at(pos)
	return not zone.is_empty() and int(zone.get("index", -1)) != _origin


func _lift() -> void:
	if _inv == null:
		return
	var slot = _inv.get_slot(_origin)
	if slot == null:
		return
	_held_id = str(slot.id)
	_held_count = int(slot.count)
	_inv.clear_slot(_origin)
	_lifted = true
	_show_ghost(_held_id, _held_count)


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


func _cancel() -> void:
	if not _captured:
		return
	var lifted := _lifted
	var inv = _inv
	var origin := _origin
	var item_id := _held_id
	var count := _held_count
	_clear_capture()
	if lifted:
		_place(inv, origin, item_id, count)


func _clear_capture() -> void:
	_captured = false
	_lifted = false
	_origin = -1
	_held_id = ""
	_held_count = 0
	_press_click = Callable()
	_inv = null
	if _ghost != null:
		_ghost.visible = false


func _player_inventory():
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return null
	return player.get("inventory")


func _zone_at(pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1
	for i in _zones.size():
		var zone: Dictionary = _zones[i]
		var slot_control := zone.get("control") as Control
		if slot_control == null or not is_instance_valid(slot_control):
			continue
		if not slot_control.is_visible_in_tree():
			continue
		var rect := slot_control.get_global_rect()
		if rect.size.x < 2.0 or rect.size.y < 2.0 or not rect.has_point(pos):
			continue
		var score := _z_score(slot_control) * 1000 + i
		if score >= best_score:
			best_score = score
			best = zone
	return best


func _z_score(item: CanvasItem) -> int:
	var total := 0
	var node: CanvasItem = item
	var guard := 0
	while node != null and guard < 20:
		total += node.z_index
		if not node.z_as_relative:
			break
		node = node.get_parent() as CanvasItem
		guard += 1
	return total


func _over_modal(pos: Vector2) -> bool:
	if not _modal_open:
		return false
	if _modal_root == null or not is_instance_valid(_modal_root):
		return false
	if not _modal_root.visible:
		return false
	var rect := _modal_root.get_global_rect()
	return rect.size.x >= 2.0 and rect.has_point(pos)


func _over_passthrough(pos: Vector2) -> bool:
	for entry in _passthrough:
		var slot_control := entry as Control
		if slot_control == null or not is_instance_valid(slot_control):
			continue
		if not slot_control.is_visible_in_tree():
			continue
		var rect := slot_control.get_global_rect()
		if rect.size.x >= 2.0 and rect.has_point(pos):
			return true
	return false


func _build_ghost() -> void:
	_ghost = Control.new()
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.visible = false
	_ghost.custom_minimum_size = Vector2(48, 40)
	_ghost.size = Vector2(48, 40)
	var bg := ColorRect.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = Color(0.1, 0.08, 0.14, 0.92)
	bg.size = Vector2(48, 40)
	_ghost.add_child(bg)
	_icon = TextureRect.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.position = Vector2(4, 2)
	_icon.size = Vector2(40, 36)
	_ghost.add_child(_icon)
	_count_label = Label.new()
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_count_label.position = Vector2(2, 22)
	_count_label.size = Vector2(44, 16)
	_count_label.add_theme_font_size_override("font_size", 12)
	_ghost.add_child(_count_label)
	add_child(_ghost)


func _show_ghost(item_id: String, count: int) -> void:
	if _ghost == null:
		_build_ghost()
	var tex: Texture2D = null
	var registry := get_tree().get_first_node_in_group("game_visual_registry")
	if registry and registry.has_method("get_item_texture"):
		tex = registry.get_item_texture(_ItemTypes.visual_key(item_id))
	_icon.texture = tex
	_count_label.text = ("x%d" % count) if count > 1 else ""
	_ghost.visible = true
	_move_ghost(_pointer())
	_TooltipPanel.hide_tip()


func _move_ghost(pos: Vector2) -> void:
	if _ghost == null:
		return
	_ghost.global_position = pos + Vector2(14, 14)


func _ui_click() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_ui"):
		audio.play_ui("ui_click")
