extends SceneTree


const _Inventory = preload("res://inventory/inventory.gd")
const _SlotDrag = preload("res://ui/slot_drag.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _Hotbar = preload("res://ui/hotbar.gd")
const _InventoryPanel = preload("res://ui/inventory_panel.gd")
const _OverlayScene = preload("res://ui/game_overlay.tscn")

var _failed := false
var _clicks: Array[int] = []


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	push_error("FAIL " + msg)
	_failed = true


func _run() -> void:
	await process_frame
	_ItemTypes.ensure_builtins()
	root.size = Vector2i(1280, 720)
	var player := _make_player()
	root.add_child(player)
	var inv = player.inventory
	await _check_plain_slots(inv)
	await _check_live_panels(inv)
	if _failed:
		quit(1)
	else:
		print("All inventory drag tests OK")
		quit(0)


func _player_ready_script() -> GDScript:
	var scr := GDScript.new()
	scr.source_code = """extends Node
var inventory
func _ready() -> void:
	add_to_group(\"player\")
	var Inv = load(\"res://inventory/inventory.gd\")
	inventory = Inv.new()
	inventory.set_slot(0, \"wooden_sword\", 1)
	inventory.set_slot(2, \"stone_pick\", 1)
	inventory.set_slot(8, \"spear\", 1)
	inventory.set_slot(9, \"wood\", 6)
"""
	var err := scr.reload()
	if err != OK:
		_fail("live player script %s" % err)
	return scr


func _make_player() -> Node:
	var scr := GDScript.new()
	scr.source_code = "extends Node\nvar inventory\n"
	var err := scr.reload()
	if err != OK:
		_fail("player stub script %s" % err)
	var player := Node.new()
	player.set_script(scr)
	player.name = "PlayerStub"
	player.add_to_group("player")
	player.inventory = _Inventory.new()
	return player


func _check_plain_slots(inv) -> void:
	inv.set_slot(0, "wooden_sword", 1)
	inv.set_slot(1, "stone_pick", 1)
	inv.set_slot(8, "wood", 10)
	inv.set_slot(9, "wood", 4)
	inv.set_slot(10, "stone", 3)
	var layer := CanvasLayer.new()
	layer.layer = 10
	root.add_child(layer)
	var slots: Array[Control] = []
	var indexes := [0, 1, 8, 9, 10]
	for n in indexes.size():
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(48, 40)
		panel.size = Vector2(48, 40)
		panel.position = Vector2(80 + (n % 3) * 80, 80 + int(n / 3) * 70)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		layer.add_child(panel)
		_SlotDrag.register_slot(self, panel, indexes[n], _note_click.bind(indexes[n]))
		slots.append(panel)
	await process_frame
	await process_frame
	await _click(slots[0], false)
	if _clicks != [0]:
		_fail("short click callbacks %s" % [_clicks])
	if _id(inv, 0) != "wooden_sword":
		_fail("short click moved slot 0")
	await _drag(slots[0], slots[1])
	if _id(inv, 0) != "stone_pick" or _id(inv, 1) != "wooden_sword":
		_fail("swap got %s / %s" % [_id(inv, 0), _id(inv, 1)])
	await _drag(slots[2], slots[3])
	if _count(inv, 8) != 0 or _count(inv, 9) != 14:
		_fail("stack got %s / %s" % [_count(inv, 8), _count(inv, 9)])
	await _drag_to(slots[4], Vector2(8, 8))
	if _id(inv, 10) != "stone" or _count(inv, 10) != 3:
		_fail("cancel drop lost stone (%s x%s)" % [_id(inv, 10), _count(inv, 10)])
	layer.queue_free()
	await process_frame


func _check_live_panels(_inv_unused) -> void:
	var previous: Node = get_first_node_in_group("player")
	if previous:
		previous.queue_free()
		await process_frame
	var host := Node.new()
	host.name = "LiveHost"
	var player := Node.new()
	player.name = "Player"
	player.set_script(_player_ready_script())
	host.add_child(player)
	var layer := CanvasLayer.new()
	layer.layer = 10
	host.add_child(layer)
	var overlay: Control = _OverlayScene.instantiate()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(overlay)
	var hotbar := Control.new()
	hotbar.name = "Hotbar"
	hotbar.set_script(_Hotbar)
	var bag := Control.new()
	bag.name = "InventoryPanel"
	bag.set_script(_InventoryPanel)
	layer.add_child(hotbar)
	layer.add_child(bag)
	player.add_to_group("player")
	root.add_child(host)
	await process_frame
	await process_frame
	var inv = player.inventory
	if inv == null:
		_fail("player _ready did not create inventory")
		return
	await _press_key(KEY_I)
	await process_frame
	if not bag.visible:
		_fail("I key did not open the bag")
		return
	var grid: GridContainer = bag.get("_grid")
	if grid == null or grid.get_child_count() < 10:
		_fail("inventory grid missing")
		return
	bag._settle_layout()
	await process_frame
	var from: Control = grid.get_child(0)
	var to: Control = grid.get_child(2)
	if from.get_global_rect().size.x < 2.0 or to.get_global_rect().size.x < 2.0:
		_fail("inventory slot rect %s -> %s" % [from.get_global_rect(), to.get_global_rect()])
		return
	await _drag(from, to)
	if _id(inv, 0) != "stone_pick" or _id(inv, 2) != "wooden_sword":
		_fail("bag drag got %s / %s" % [_id(inv, 0), _id(inv, 2)])
	if _tip(from) != "Stone Pick" or _tip(to) != "Wooden Sword":
		_fail("bag drag labels %s / %s" % [_tip(from), _tip(to)])
	var bag_spear: Control = grid.get_child(8)
	await _click(bag_spear, false)
	if _id(inv, 1) != "spear" or _id(inv, 8) != "":
		_fail("bag click got hotbar %s bag %s" % [_id(inv, 1), _id(inv, 8)])
	if _tip(bag_spear) != "":
		_fail("bag click left spear label %s" % _tip(bag_spear))
	var bar_slots: Array = hotbar.get("_slot_nodes")
	if bar_slots.size() < 3:
		_fail("hotbar slots missing")
		return
	var bar_from: Control = bar_slots[0]
	var bar_to: Control = bar_slots[2]
	if bar_from.get_global_rect().size.x < 2.0:
		_fail("hotbar rect %s" % bar_from.get_global_rect())
		return
	await _drag(bar_from, bar_to)
	if _id(inv, 0) != "wooden_sword" or _id(inv, 2) != "stone_pick":
		_fail("hotbar drag got %s / %s" % [_id(inv, 0), _id(inv, 2)])
		return
	var bag_wood: Control = grid.get_child(9)
	var bar_empty: Control = bar_slots[3]
	await _drag(bag_wood, bar_empty)
	if _id(inv, 3) != "wood" or _count(inv, 3) != 6 or _id(inv, 9) != "":
		_fail("bag to hotbar got %s x%s / bag %s" % [_id(inv, 3), _count(inv, 3), _id(inv, 9)])
		return
	if _tip(bag_wood) != "" or _slot_text(bag_wood) != "":
		_fail("bag wood label stayed %s %s" % [_tip(bag_wood), _slot_text(bag_wood)])
	var bar_labels: Array = hotbar.get("_label_nodes")
	if str(bar_labels[3].text) != "x6":
		_fail("hotbar wood label %s" % bar_labels[3].text)
	await _drag(bar_slots[1], grid.get_child(8))
	if _id(inv, 8) != "spear" or _id(inv, 1) != "":
		_fail("hotbar to bag got bag %s hotbar %s" % [_id(inv, 8), _id(inv, 1)])
	if _tip(grid.get_child(8)) != "Spear":
		_fail("hotbar to bag label %s" % _tip(grid.get_child(8)))


func _tip(control: Control) -> String:
	return str(control.tooltip_text)


func _slot_text(control: Control) -> String:
	if control is Button:
		return (control as Button).text
	return ""


func _note_click(index: int) -> void:
	_clicks.append(index)


func _id(inv, index: int) -> String:
	var slot = inv.get_slot(index)
	if slot == null:
		return ""
	return str(slot.id)


func _count(inv, index: int) -> int:
	var slot = inv.get_slot(index)
	if slot == null:
		return 0
	return int(slot.count)


func _center(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas().origin + control.size * 0.5


func _click(control: Control, move: bool) -> void:
	var pos := _center(control)
	_button(pos, true)
	await process_frame
	if move:
		_motion(pos + Vector2(24, 4), Vector2(24, 4))
		await process_frame
	_button(pos, false)
	await process_frame


func _drag(from: Control, to: Control) -> void:
	var a := _center(from)
	var b := _center(to)
	_button(a, true)
	await process_frame
	_motion(a + Vector2(20, 0), Vector2(20, 0))
	await process_frame
	_motion(lerp(a, b, 0.5), (b - a) * 0.5)
	await process_frame
	_motion(b, b - a)
	await process_frame
	_button(b, false)
	await process_frame


func _drag_to(from: Control, pos: Vector2) -> void:
	var a := _center(from)
	_button(a, true)
	await process_frame
	_motion(a + Vector2(20, 0), Vector2(20, 0))
	await process_frame
	_motion(pos, pos - a)
	await process_frame
	_button(pos, false)
	await process_frame


func _button(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(ev, true)


func _motion(pos: Vector2, _rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.relative = Vector2.ZERO
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(ev, true)


func _press_key(keycode: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = keycode
	down.physical_keycode = keycode
	down.pressed = true
	down.echo = false
	root.push_input(down, true)
	await process_frame
	var up := InputEventKey.new()
	up.keycode = keycode
	up.physical_keycode = keycode
	up.pressed = false
	up.echo = false
	root.push_input(up, true)
