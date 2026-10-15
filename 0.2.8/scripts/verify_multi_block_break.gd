extends SceneTree

const _ItemTypes = preload("res://helpers/item_types.gd")
const _Weapon = preload("res://weapons/weapon_controller.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL " + msg)


func _run() -> void:
	_ItemTypes.reset()
	_ItemTypes.ensure_builtins()
	if not _ItemTypes.MULTI_BLOCK_BREAK:
		_fail("MULTI_BLOCK_BREAK must default true")
	_test_tier_widen()
	_test_shapes_face_aim()
	_test_weapon_uses_same_cells()
	if _failed == 0:
		print("All multi block break tests OK")
		quit(0)
	else:
		push_error("verify_multi_block_break: %d failure(s)" % _failed)
		quit(1)


func _test_tier_widen() -> void:
	var pick := _ItemTypes.get_def("stone_pick")
	if int(pick.get("break_shape", -1)) != _ItemTypes.BreakShape.SINGLE:
		_fail("stone_pick base shape must be single")
		return
	if int(pick.get("tool_tier", -1)) != 0:
		_fail("stone_pick tier must start at 0")
		return
	var expected: Array[int] = [
		_ItemTypes.BreakShape.SINGLE,
		_ItemTypes.BreakShape.VERTICAL_1X2,
		_ItemTypes.BreakShape.LINE_3,
		_ItemTypes.BreakShape.FACE_3X3,
	]
	for tier in expected.size():
		var got := _ItemTypes.break_shape_for("stone_pick", tier)
		if got != expected[tier]:
			_fail("tier %d shape %s != %s" % [tier, _ItemTypes.break_shape_name(got), _ItemTypes.break_shape_name(expected[tier])])
			return
	if _ItemTypes.break_shape_for("stone_pick", 9) != _ItemTypes.BreakShape.FACE_3X3:
		_fail("tier past the last shape must stay on the 3x3 face")
		return
	if _ItemTypes.break_shape_for("wooden_sword", 3) != _ItemTypes.BreakShape.SINGLE:
		_fail("weapons must stay a single cell")
		return
	if _ItemTypes.break_shape_for("stone_pick") != _ItemTypes.BreakShape.SINGLE:
		_fail("stone_pick with no upgrade must stay single")
		return
	print("OK tier widen single -> 1x2 vertical -> line_3 -> face_3x3")


func _test_shapes_face_aim() -> void:
	var anchor := Vector3i(10, 4, 20)
	_expect_cells("single +Z", _cells(_ItemTypes.BreakShape.SINGLE, anchor, Vector3(0, 0, 1)), [anchor])
	_expect_cells("1x2 +Z", _cells(_ItemTypes.BreakShape.VERTICAL_1X2, anchor, Vector3(0, 0, 1)), [
		anchor, Vector3i(10, 5, 20),
	])
	_expect_cells("line +Z", _cells(_ItemTypes.BreakShape.LINE_3, anchor, Vector3(0, 0, 1)), [
		anchor, Vector3i(9, 4, 20), Vector3i(11, 4, 20),
	])
	_expect_cells("face +Z", _cells(_ItemTypes.BreakShape.FACE_3X3, anchor, Vector3(0, 0, 1)), _face_z(anchor))
	_expect_cells("line +X", _cells(_ItemTypes.BreakShape.LINE_3, anchor, Vector3(1, 0, 0)), [
		anchor, Vector3i(10, 4, 21), Vector3i(10, 4, 19),
	])
	_expect_cells("line -X", _cells(_ItemTypes.BreakShape.LINE_3, anchor, Vector3(-1, 0, 0)), [
		anchor, Vector3i(10, 4, 19), Vector3i(10, 4, 21),
	])
	_expect_cells("line -Z", _cells(_ItemTypes.BreakShape.LINE_3, anchor, Vector3(0, 0, -1)), [
		anchor, Vector3i(11, 4, 20), Vector3i(9, 4, 20),
	])
	_expect_cells("face +X", _cells(_ItemTypes.BreakShape.FACE_3X3, anchor, Vector3(0.2, 3.0, 0.1)), _face_x(anchor))
	var flat := _cells(_ItemTypes.BreakShape.LINE_3, anchor, Vector3(0, 1, 0))
	_expect_cells("line no flat aim", flat, [
		anchor, Vector3i(9, 4, 20), Vector3i(11, 4, 20),
	])


func _test_weapon_uses_same_cells() -> void:
	var weapon = _Weapon.new()
	var anchor := Vector3i(4, 2, 8)
	var aim := Vector3(0, 0, 1)
	var from_weapon: Array = weapon.break_cells_for("stone_pick", anchor, aim)
	var line_cells: Array = weapon.break_cells_for("stone_pick", anchor, aim)
	weapon.free()
	var from_items: Array = _ItemTypes.break_cells(_ItemTypes.break_shape_for("stone_pick", 2), anchor, aim)
	var direct: Array = _ItemTypes.break_cells(_ItemTypes.break_shape_for("stone_pick", 3), anchor, aim)
	if from_weapon.size() != 1 or from_weapon[0] != anchor or line_cells.size() != 1:
		_fail("weapon stone_pick tier 0 must be the aimed cell, got %s" % from_weapon)
		return
	if from_items.size() != 3 or from_items[0] != anchor:
		_fail("line tier must be 3 cells from the aim, got %s" % from_items)
		return
	if direct.size() != 9 or direct[0] != anchor:
		_fail("face tier must be 9 cells starting at the aim, got %s" % direct)
		return
	var src := (load("res://weapons/weapon_controller.gd") as GDScript).source_code
	var at := src.find("func _try_dig_tool")
	var end := src.find("\nfunc ", at + 10)
	var body := src.substr(at, maxi(end - at, 0))
	if "break_cells_for(" not in body or "_aim_forward(" not in body:
		_fail("_try_dig_tool must resolve break cells toward the aim")
		return
	print("OK weapon resolves the aimed cell list")


func _cells(shape: int, anchor: Vector3i, aim: Vector3) -> Array:
	return _ItemTypes.break_cells(shape, anchor, aim)


func _face_z(anchor: Vector3i) -> Array:
	var cells: Array = [anchor]
	for uy in range(-1, 2):
		for rx in range(-1, 2):
			if rx == 0 and uy == 0:
				continue
			cells.append(Vector3i(anchor.x + rx, anchor.y + uy, anchor.z))
	return cells


func _face_x(anchor: Vector3i) -> Array:
	var cells: Array = [anchor]
	for uy in range(-1, 2):
		for rz in range(-1, 2):
			if rz == 0 and uy == 0:
				continue
			cells.append(Vector3i(anchor.x, anchor.y + uy, anchor.z - rz))
	return cells


func _expect_cells(label: String, got: Array, expect: Array) -> void:
	if got.size() != expect.size():
		_fail("%s size %d != %d (%s)" % [label, got.size(), expect.size(), got])
		return
	for i in got.size():
		if got[i] != expect[i]:
			_fail("%s [%d] %s != %s" % [label, i, str(got[i]), str(expect[i])])
			return
	print("OK " + label)
