extends SceneTree

const _ItemTypes = preload("res://helpers/item_types.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _Inventory = preload("res://inventory/inventory.gd")


class FakeWorld:
	extends RefCounted

	func get_surface_height(_x: float, _z: float) -> float:
		return 4.0


var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	print("FAIL " + msg)


func _key(code: int, pressed: bool, shift: bool = false) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code as Key
	ev.keycode = code as Key
	ev.shift_pressed = shift
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _run() -> void:
	var w := Node.new()
	w.set_script(load("res://weapons/weapon_controller.gd"))
	root.add_child(w)
	w.inventory = _Inventory.new()
	await process_frame
	var seen: Array[int] = []
	for i in 4:
		_key(KEY_Z, true)
		await process_frame
		await process_frame
		_key(KEY_Z, false)
		await process_frame
		seen.append(w.blueprint_quarter)
	if seen != [1, 2, 3, 0]:
		_fail("Z quarters %s" % str(seen))
	_key(KEY_Z, true, true)
	await process_frame
	await process_frame
	_key(KEY_Z, false, true)
	await process_frame
	if w.blueprint_quarter != 3:
		_fail("Shift+Z gave %d want 3" % w.blueprint_quarter)

	var world := FakeWorld.new()
	var line := _ItemTypes.BreakShape.LINE_3
	var spans := []
	for q in 4:
		var aim := _ItemTypes.rotate_aim(Vector3(1.0, 0.0, 0.0), q)
		var cells := _TerrainEdits.brush_cells(line, Vector3i(10, 0, 10), aim, world, true)
		var xs := {}
		var zs := {}
		for c in cells:
			xs[c.x] = true
			zs[c.z] = true
		spans.append([xs.size(), zs.size()])
	if spans != [[1, 3], [3, 1], [1, 3], [3, 1]]:
		_fail("brush line footprint per quarter %s" % str(spans))

	if _failed == 0:
		print("All rotation checks OK")
		quit(0)
	else:
		quit(1)
