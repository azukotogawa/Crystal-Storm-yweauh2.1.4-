extends SceneTree

const _ItemTypes = preload("res://helpers/item_types.gd")
const _Weapon = preload("res://weapons/weapon_controller.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _Ramps = preload("res://helpers/terrain_ramps.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _Highlight = preload("res://player/target_highlight.gd")
const _Inventory = preload("res://inventory/inventory.gd")
const _BreakFx = preload("res://systems/block_break_fx.gd")

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
	_test_break_preview()
	_test_batch_dig()
	_test_drops_fx_wear()
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
	if "MULTI_BLOCK_BREAK" not in body:
		_fail("_try_dig_tool must use the batched dig under MULTI_BLOCK_BREAK")
		return
	var dig_at := src.find("func _do_dig_attack")
	var dig_end := src.find("\nfunc ", dig_at + 10)
	var dig_body := src.substr(dig_at, maxi(dig_end - dig_at, 0))
	if "TerrainEdits.dig_cells(" not in dig_body or "MULTI_BLOCK_BREAK" not in dig_body:
		_fail("_try_dig_tool stroke must batch dig_cells under MULTI_BLOCK_BREAK")
		return
	print("OK weapon resolves the aimed cell list")


func _test_break_preview() -> void:
	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	var flat := _FlatBreakWorld.new()
	root.add_child(flat)
	var pick = _ItemTypes.get_item_def("stone_pick")
	var saved_tier := int(pick.tool_tier)
	pick.tool_tier = 3
	var anchor := Vector3i(4, 0, 4)
	var aim := Vector3(0, 0, 1)
	var flat_preview: Array = _Highlight.break_preview_cells("stone_pick", anchor, aim, flat, null)
	_expect_cells("face preview on flat ground", flat_preview, [
		anchor, Vector3i(3, 0, 4), Vector3i(5, 0, 4),
	])
	var flat_marks: Array = _Highlight.preview_mark_cells("stone_pick", anchor, aim, flat, null)
	_expect_cells("face preview marks skip the aimed column", flat_marks, [
		Vector3i(3, 0, 4), Vector3i(5, 0, 4),
	])
	_TerrainEdits.dig(3, 4, 1)
	var stepped: Array = _Highlight.break_preview_cells("stone_pick", anchor, aim, flat, null)
	_expect_cells("face preview follows the dug neighbor", stepped, [
		anchor, Vector3i(3, -1, 4), Vector3i(5, 0, 4),
	])
	var blocker := _BlockColumn.new()
	blocker.wx = 5
	var blocked: Array = _Highlight.break_preview_cells("stone_pick", anchor, aim, flat, blocker)
	_expect_cells("face preview drops a blocked column", blocked, [
		anchor, Vector3i(3, -1, 4),
	])
	pick.tool_tier = 1
	var tall: Array = _Highlight.break_preview_cells("stone_pick", anchor, aim, flat, null)
	_expect_cells("1x2 preview drops the air cell above", tall, [anchor])
	var outside := Vector3i(4000, 0, 0)
	pick.tool_tier = 3
	var abroad: Array = _Highlight.break_preview_cells("stone_pick", outside, aim, flat, null)
	if not abroad.is_empty():
		_fail("preview outside the border must be empty, got %s" % abroad)
	else:
		print("OK preview outside the border is empty")
	for _i in 4:
		_TerrainEdits.dig(8, 8, 1)
	var floor_cell := Vector3i(8, _TerrainEdits.surface_block_y(flat, 8, 8), 8)
	pick.tool_tier = 0
	var floor_preview: Array = _Highlight.break_preview_cells("stone_pick", floor_cell, aim, flat, null)
	if not floor_preview.is_empty():
		_fail("preview at the dig floor must be empty, got %s" % floor_preview)
	else:
		print("OK preview at the dig floor is empty")
	pick.tool_tier = saved_tier
	var src := (load("res://player/target_highlight.gd") as GDScript).source_code
	var at := src.find("func _update_brush_footprint")
	var end := src.find("\nfunc ", at + 10)
	var body := src.substr(at, maxi(end - at, 0))
	if "break_preview_cells" not in src or "_place_break_preview" not in body:
		_fail("dig highlight must preview the clipped break shape")
	elif "clip_breakable_cells" not in (load("res://world/terrain_edits.gd") as GDScript).source_code:
		_fail("preview must clip through the breakable-cell check")
	else:
		print("OK dig highlight previews the clipped break shape")
	flat.free()
	_TerrainEdits.reset()


func _test_batch_dig() -> void:
	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	var flat := _FlatBreakWorld.new()
	root.add_child(flat)
	var editor := _TerrainEditor.new()
	var cm := _ChunkManager.new()
	root.add_child(editor)
	editor.world = flat
	editor.bind_chunk_manager(cm)
	var line: Array[Vector3i] = [
		Vector3i(4, 0, 4),
		Vector3i(5, 0, 4),
		Vector3i(6, 0, 4),
		Vector3i(4, 1, 4),
	]
	var before := {}
	for cell in line:
		if cell.y != 0:
			continue
		before[Vector2i(cell.x, cell.z)] = _Ramps.walkable_height(flat, float(cell.x) + 0.5, float(cell.z) + 0.5)
	cm.edit_flush_count = 0
	cm.edit_flush_chunk_count = 0
	var batch: Dictionary = _TerrainEdits.dig_cells(line, editor)
	var removed: Array = batch.get("removed", [])
	var line_ok := removed.size() == line.size() and int(batch.get("dug_count", 0)) == 3
	for cell in line:
		if not _has_cell(removed, cell):
			line_ok = false
		if cell.y == 0 and _layers_at(cell.x, cell.z) != -1:
			line_ok = false
	if _layers_at(4, 4) != -1:
		line_ok = false
	for cell in line:
		if cell.y != 0:
			continue
		var stand: float = _Ramps.walkable_height(flat, float(cell.x) + 0.5, float(cell.z) + 0.5)
		var was: float = float(before.get(Vector2i(cell.x, cell.z), -999.0))
		if stand >= was - 0.01:
			line_ok = false
	if not line_ok:
		_fail("line cells must all leave and drop collision")
	elif int(batch.get("remesh_count", 0)) != 1 or int(batch.get("water_count", 0)) != 1 or int(batch.get("crystal_count", 0)) != 1:
		_fail("one chunk must remesh, reflow water, and update crystal once")
	elif cm.edit_flush_count != 1:
		_fail("one chunk must rebuild once, flush %d" % cm.edit_flush_count)
	else:
		print("OK one chunk: cells removed, collision dropped, one rebuild")
	_TerrainEdits.reset()
	var cm_edge := _ChunkManager.new()
	editor.bind_chunk_manager(cm_edge)
	var home_a := _TerrainEdits.chunk_for_column(15, 8)
	var home_b := _TerrainEdits.chunk_for_column(16, 8)
	if home_a == home_b:
		_fail("chunk edge fixture must cover two chunks")
	else:
		var edge: Array[Vector3i] = [Vector3i(15, 0, 8), Vector3i(16, 0, 8), Vector3i(15, 0, 9)]
		var edge_before := {}
		for cell in edge:
			edge_before[Vector2i(cell.x, cell.z)] = _Ramps.walkable_height(flat, float(cell.x) + 0.5, float(cell.z) + 0.5)
		var edge_batch: Dictionary = _TerrainEdits.dig_cells(edge, editor)
		var edge_removed: Array = edge_batch.get("removed", [])
		var edge_ok := edge_removed.size() == edge.size() and int(edge_batch.get("dug_count", 0)) == edge.size()
		for cell in edge:
			if not _has_cell(edge_removed, cell) or _layers_at(cell.x, cell.z) != -1:
				edge_ok = false
			var stand_e: float = _Ramps.walkable_height(flat, float(cell.x) + 0.5, float(cell.z) + 0.5)
			var was_e: float = float(edge_before.get(Vector2i(cell.x, cell.z), -999.0))
			if stand_e >= was_e - 0.01:
				edge_ok = false
		var homes: int = int(edge_batch.get("remesh_count", 0))
		if not edge_ok:
			_fail("edge cells must all leave and drop collision")
		elif homes != 2 or int(edge_batch.get("water_count", 0)) != 2 or int(edge_batch.get("crystal_count", 0)) != 2:
			_fail("two chunks must each remesh, reflow, and update crystal once")
		elif cm_edge.edit_flush_count != 1:
			_fail("two chunks must share one rebuild flush, flush %d" % cm_edge.edit_flush_count)
		else:
			print("OK two chunks: cells removed, collision dropped, one rebuild each")
	editor.free()
	flat.free()
	cm.free()
	cm_edge.free()


func _test_drops_fx_wear() -> void:
	var hammer := _ItemTypes.get_def("crystal_hammer")
	if not is_equal_approx(float(hammer.get("impact_ratio", -1.0)), 0.62):
		_fail("crystal hammer impact_ratio must stay 0.62")
		return
	if not is_equal_approx(float(hammer.get("anim_duration", -1.0)), 1.1):
		_fail("crystal hammer duration must stay 1.1")
		return
	if _ItemTypes.tool_max_durability("stone_pick") != 48:
		_fail("stone pick durability must start at 48")
		return
	if _ItemTypes.tool_max_durability("crystal_hammer") != 0:
		_fail("crystal hammer must not use dig durability")
		return
	if not is_equal_approx(_ItemTypes.dig_time_scale(1), 1.0):
		_fail("one broken cell must keep the dig timing")
		return
	if _ItemTypes.dig_time_scale(4) <= _ItemTypes.dig_time_scale(1):
		_fail("more broken cells must slow the next dig")
		return
	if _ItemTypes.wear_for_cells(3) != 3:
		_fail("wear must match the broken cell count")
		return
	var bag = _Inventory.new()
	bag.set_slot(0, "stone_pick", 1)
	bag.set_slot(1, "crystal_hammer", 1)
	if bag.wear_tool(0, _ItemTypes.wear_for_cells(3)) != 45:
		_fail("a 3-cell swing must wear the pick by 3")
		return
	var saved: Dictionary = bag.to_dict()
	var loaded = _Inventory.new()
	loaded.load_from_dict(saved)
	var kept = loaded.get_slot(0)
	if kept == null or int(kept.get("durability", -1)) != 45:
		_fail("pick durability must round-trip through the save")
		return
	if bag.wear_tool(0, 45) != 0 or bag.get_slot(0) != null:
		_fail("a spent pick must leave the hotbar")
		return
	if bag.wear_tool(1, 9) != -1 or bag.get_slot(1) == null:
		_fail("the hammer swing must not spend durability")
		return
	_TerrainEdits.reset()
	var flat := _FlatBreakWorld.new()
	var editor := _TerrainEditor.new()
	var pocket := _Pocket.new()
	pocket.inventory = bag
	pocket.add_to_group("player")
	root.add_child(flat)
	root.add_child(editor)
	root.add_child(pocket)
	editor.world = flat
	var wide: Array[Vector3i] = []
	for i in 6:
		wide.append(Vector3i(20 + i, 0, 3))
	var swing: Dictionary = _TerrainEdits.dig_cells(wide, editor)
	var stone := bag.count_item("stone")
	if int(swing.get("dug_count", 0)) != 6 or int(swing.get("drop_count", 0)) != _TerrainEdits.DROP_CAP_PER_SWING or stone != _TerrainEdits.DROP_CAP_PER_SWING:
		_fail("six cells must drop only the swing cap, got dug %s drops %s stone %s" % [swing.get("dug_count"), swing.get("drop_count"), stone])
	else:
		var more: Array[Vector3i] = [Vector3i(30, 0, 3), Vector3i(31, 0, 3)]
		var follow: Dictionary = _TerrainEdits.dig_cells(more, editor)
		if int(follow.get("drop_count", 0)) != 2 or bag.count_item("stone") != stone + 2:
			_fail("the next swing must drop again up to the cap")
		else:
			print("OK drops cap at %d per swing" % _TerrainEdits.DROP_CAP_PER_SWING)
	if not is_equal_approx(_BreakFx.break_fx_scale(1), 0.85):
		_fail("one cell must keep the chip scale")
	elif _BreakFx.break_fx_scale(9) <= _BreakFx.break_fx_scale(1):
		_fail("more cells must scale the break FX up")
	elif _BreakFx.break_fx_scale(40) > 1.45 + 0.001:
		_fail("break FX scale must stay capped")
	else:
		var fx = _BreakFx.new()
		root.add_child(fx)
		var spots: Array[Vector3] = []
		for i in 6:
			spots.append(Vector3(float(i), 1.0, 2.0))
		var played := int(fx.notify_scaled_breaks(spots, Color(0.2, 0.55, 0.25)))
		if played != _BreakFx.SWING_FX_CAP or fx.break_count() != _BreakFx.SWING_FX_CAP:
			_fail("six breaks must play %d FX, played %d count %d" % [_BreakFx.SWING_FX_CAP, played, fx.break_count()])
		else:
			print("OK break FX scales and caps at %d" % _BreakFx.SWING_FX_CAP)
		fx.free()
	var src := (load("res://weapons/weapon_controller.gd") as GDScript).source_code
	var at := src.find("func _do_dig_attack")
	var end := src.find("\nfunc ", at + 10)
	var body := src.substr(at, maxi(end - at, 0))
	if "dig_time_scale(" not in body or "wear_tool(" not in body or "_notify_scaled_break(" not in body:
		_fail("the dig stroke must scale timing, wear, and FX with the cell count")
	elif "notify_scaled_breaks" not in src:
		_fail("scaled break FX must go through BlockBreakFx")
	else:
		print("OK dig timing and durability scale with the cell count")
	pocket.free()
	editor.free()
	flat.free()
	_TerrainEdits.reset()


class _Pocket:
	extends Node
	var inventory


func _has_cell(cells: Array, want: Vector3i) -> bool:
	for item in cells:
		if item is Vector3i and (item as Vector3i) == want:
			return true
	return false


func _layers_at(x: int, z: int) -> int:
	var layer: float = _WorldSettings.get_active().layer_height()
	return int(round(_TerrainEdits.get_height_delta(x, z) / maxf(layer, 0.001)))


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


class _BlockColumn:
	extends RefCounted
	var wx: int = 0

	func break_cell_blocked(x: int, _z: int) -> String:
		if x == wx:
			return "water"
		return ""


class _FlatBreakWorld:
	extends "res://world/InfiniteNoiseWorld.gd"

	func get_surface_height(wx: float, wz: float) -> float:
		var k := Vector2i(floori(wx), floori(wz))
		return TerrainEdits.get_height_delta(k.x, k.y)

	func get_tile_type(_wx: float, _wz: float) -> int:
		return VoxelTypes.GRASSLAND

	func invalidate_column_cache(_wx: int, _wz: int) -> void:
		pass


func _expect_cells(label: String, got: Array, expect: Array) -> void:
	if got.size() != expect.size():
		_fail("%s size %d != %d (%s)" % [label, got.size(), expect.size(), got])
		return
	for i in got.size():
		if got[i] != expect[i]:
			_fail("%s [%d] %s != %s" % [label, i, str(got[i]), str(expect[i])])
			return
	print("OK " + label)
