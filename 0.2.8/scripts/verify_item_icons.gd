extends SceneTree
## Tool and weapon icons on the real hotbar and inventory.
## The old check only asked the generator for a texture at least 16px wide.
## The files are 32px and the hotbar draws them at 44px, so that check passed
## while the slots upscaled the art. This one opens the bag with I, reads the
## slot controls, and requires a 64px texture that is not stretched up.


const _Inventory = preload("res://inventory/inventory.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _Hotbar = preload("res://ui/hotbar.gd")
const _InventoryPanel = preload("res://ui/inventory_panel.gd")
const _Registry = preload("res://systems/game_visual_registry.gd")

const GEAR: Array[String] = [
	"wooden_sword", "spear", "stone_pick", "crystal_hammer", "shortbow", "sling",
]
const MIN_PX := 64

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	push_error("FAIL " + msg)
	print("FAIL " + msg)
	_failed = true


func _run() -> void:
	await process_frame
	_ItemTypes.ensure_builtins()
	root.size = Vector2i(1280, 720)
	var player := Node.new()
	player.name = "PlayerStub"
	player.set_script(_player_script())
	root.add_child(player)
	var inv = player.inventory
	for i in GEAR.size():
		inv.set_slot(i, GEAR[i], 1)
	var registry := _Registry.new()
	root.add_child(registry)
	var layer := CanvasLayer.new()
	layer.layer = 10
	root.add_child(layer)
	var hotbar := _Hotbar.new()
	hotbar.name = "Hotbar"
	layer.add_child(hotbar)
	var bag := _InventoryPanel.new()
	bag.name = "InventoryPanel"
	layer.add_child(bag)
	await process_frame
	await _press_key(KEY_I)
	var ready := false
	for _frame in 120:
		await process_frame
		if bag.visible and _gear_icon(hotbar, 0) != null and _bag_icon(bag, 0) != null:
			ready = true
			break
	if not bag.visible:
		_fail("inventory did not open on I")
	if not ready:
		_fail("gear icons were not bound on the hotbar and bag")
	else:
		_check_hotbar(hotbar)
		_check_bag(bag)
	if _failed:
		quit(1)
		return
	print("All item icon tests OK")
	quit(0)


func _player_script() -> GDScript:
	var scr := GDScript.new()
	scr.source_code = "extends Node\nvar inventory\nfunc _ready() -> void:\n\tadd_to_group(\"player\")\n\tinventory = load(\"res://inventory/inventory.gd\").new()\n"
	var err := scr.reload()
	if err != OK:
		_fail("player stub %s" % err)
	return scr


func _press_key(keycode: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = keycode
	down.physical_keycode = keycode
	down.pressed = true
	root.push_input(down, true)
	await process_frame
	var up := InputEventKey.new()
	up.keycode = keycode
	up.physical_keycode = keycode
	up.pressed = false
	root.push_input(up, true)
	await process_frame


func _hotbar_rect(hotbar: Control, index: int) -> TextureRect:
	if index < 0 or index >= hotbar.get_child_count():
		return null
	var panel := hotbar.get_child(index)
	if panel.get_child_count() < 1:
		return null
	return panel.get_child(0) as TextureRect


func _bag_grid(bag: Control) -> GridContainer:
	return _find_grid(bag)


func _find_grid(node: Node) -> GridContainer:
	if node is GridContainer:
		return node
	for child in node.get_children():
		var found := _find_grid(child)
		if found != null:
			return found
	return null


func _gear_icon(hotbar: Control, index: int) -> Texture2D:
	var rect := _hotbar_rect(hotbar, index)
	if rect == null:
		return null
	return rect.texture


func _bag_icon(bag: Control, index: int) -> Texture2D:
	var grid := _bag_grid(bag)
	if grid == null or index >= grid.get_child_count():
		return null
	var btn := grid.get_child(index) as Button
	if btn == null:
		return null
	return btn.icon


func _drawn_size(control: Control) -> Vector2:
	var drawn := control.size
	if drawn.x < 1.0 or drawn.y < 1.0:
		drawn = control.custom_minimum_size
	return drawn


func _check_texture(where: String, tex: Texture2D, drawn: Vector2) -> void:
	if tex == null:
		_fail("%s has no icon" % where)
		return
	var w := tex.get_width()
	var h := tex.get_height()
	print("OK %s icon %dx%d drawn %.0fx%.0f" % [where, w, h, drawn.x, drawn.y])
	if w < MIN_PX or h < MIN_PX:
		_fail("%s icon is %dx%d, need at least %d" % [where, w, h, MIN_PX])
		return
	if float(w) < drawn.x or float(h) < drawn.y:
		_fail("%s draws %.0fx%.0f from a %dx%d texture" % [where, drawn.x, drawn.y, w, h])
	var image := tex.get_image()
	if image == null:
		_fail("%s icon has no image" % where)
		return
	if _min_opaque_run(image) > 1:
		_fail("%s icon is a scaled-up low-res image (min run %d)" % [where, _min_opaque_run(image)])


func _min_opaque_run(image: Image) -> int:
	var best := 999
	for y in image.get_height():
		var run := 0
		var prev := Color(0, 0, 0, 0)
		for x in image.get_width():
			var px := image.get_pixel(x, y)
			if run > 0 and px == prev:
				run += 1
			else:
				if run > 0 and prev.a > 0.5:
					best = mini(best, run)
				run = 1
				prev = px
		if run > 0 and prev.a > 0.5:
			best = mini(best, run)
	return best


func _check_hotbar(hotbar: Control) -> void:
	for i in GEAR.size():
		var rect := _hotbar_rect(hotbar, i)
		if rect == null:
			_fail("hotbar slot %d missing" % i)
			continue
		if rect.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST:
			_fail("hotbar %s filter is %d" % [GEAR[i], rect.texture_filter])
		_check_texture("hotbar " + GEAR[i], rect.texture, _drawn_size(rect))


func _check_bag(bag: Control) -> void:
	var grid := _bag_grid(bag)
	if grid == null:
		_fail("inventory grid missing")
		return
	for i in GEAR.size():
		var btn := grid.get_child(i) as Button
		if btn == null:
			_fail("bag slot %d missing" % i)
			continue
		if btn.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST \
				and btn.texture_filter != CanvasItem.TEXTURE_FILTER_PARENT_NODE:
			_fail("bag %s filter is %d" % [GEAR[i], btn.texture_filter])
		_check_texture("bag " + GEAR[i], btn.icon, _drawn_size(btn))
