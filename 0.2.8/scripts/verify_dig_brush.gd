extends SceneTree


const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _LivingForce = preload("res://world/living_force.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")

var failed := false
var flat: FlatWorld
var editor: TerrainEditor
var cm: ChunkManager


class FlatWorld:
	extends "res://world/InfiniteNoiseWorld.gd"
	var bases: Dictionary = {}
	var tiles: Dictionary = {}

	func get_surface_height(wx: float, wz: float) -> float:
		var k := Vector2i(floori(wx), floori(wz))
		return float(bases.get(k, 0.0)) + TerrainEdits.get_height_delta(k.x, k.y)

	func get_tile_type(wx: float, wz: float) -> int:
		var k := Vector2i(floori(wx), floori(wz))
		if tiles.has(k):
			return int(tiles[k])
		var built := TerrainEdits.get_build_tile(k.x, k.y)
		if built >= 0:
			return built
		var ov := FeatureRegistry.get_tile_override(k.x, k.y)
		if ov >= 0:
			return ov
		return VoxelTypes.GRASSLAND

	func invalidate_column_cache(_wx: int, _wz: int) -> void:
		pass


class ColumnPlayer:
	extends Node3D
	var at: Vector3 = Vector3.ZERO

	func get_voxel_position() -> Vector3:
		return at


func _init() -> void:
	call_deferred("_run")


func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("OK %s" % msg)
	else:
		push_error(msg)
		failed = true


func _layer() -> float:
	return _WorldSettings.get_active().layer_height()


func _layers_at(x: int, z: int) -> int:
	return int(round(_TerrainEdits.get_height_delta(x, z) / maxf(_layer(), 0.001)))


func _wipe() -> void:
	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	_ChannelRegistry.reset()
	_LivingForce.reset_session()
	if flat:
		flat.bases.clear()
		flat.tiles.clear()


func _cell_set(cells: Array) -> Dictionary:
	var out := {}
	for c in cells:
		out[c] = true
	return out


func _run() -> void:
	_geometry()
	_radius_item()
	_source_contracts()
	await _boot()
	if editor == null:
		_finish()
		return
	await _radius_one_matches_single()
	await _disk_stroke(2, 5, Vector2i(8, 8), 1)
	await _disk_stroke(3, 13, Vector2i(8, 24), 1)
	await _border_flush()
	await _vertical_skip()
	await _deterministic()
	await _range_block()
	await _range_partial()
	await _protected()
	await _gameplay_floor()
	await _save_roundtrip()
	await _radius_one_beside_water()
	_finish()


func _geometry() -> void:
	var one: Array = _LivingForce.footprint(4, 4, 1, null)
	var two: Array = _LivingForce.footprint(4, 4, 2, null)
	var three: Array = _LivingForce.footprint(4, 4, 3, null)
	_expect(one.size() == 1 and one[0] == Vector2i(4, 4), "radius 1 footprint is the aimed column")
	var two_set := _cell_set(two)
	var two_ok := two.size() == 5
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		two_ok = two_ok and two_set.has(Vector2i(4, 4) + d)
	two_ok = two_ok and not two_set.has(Vector2i(5, 5))
	_expect(two_ok, "radius 2 footprint is center + 4 orthogonal (%d)" % two.size())
	_expect(three.size() == 13 and not _cell_set(three).has(Vector2i(6, 5)), "radius 3 footprint is 13 and drops (2,1) corners")
	var again: Array = _LivingForce.footprint(4, 4, 3, null)
	_expect(_cell_set(again).size() == _cell_set(three).size(), "footprint is deterministic")


func _radius_item() -> void:
	_LivingForce.reset_session()
	var looked: Dictionary = _ItemTypes.get_def("stone_pick")
	_expect(int(looked.get("dig_radius", 0)) == 1, "stone_pick lookup exposes dig_radius 1")
	_expect(_LivingForce.radius_for_item("stone_pick") == 1, "default brush radius is 1")
	_expect(_LivingForce.adjust_session_bias(1, "stone_pick") == 2, "bias +1 -> radius 2")
	_expect(_LivingForce.adjust_session_bias(1, "stone_pick") == 3, "bias +1 -> radius 3")
	_expect(_LivingForce.adjust_session_bias(1, "stone_pick") == 3, "bias clamps at 3")
	_expect(_LivingForce.adjust_session_bias(-1, "stone_pick") == 2, "bias -1 -> radius 2")
	_LivingForce.reset_session()
	_expect(_LivingForce.radius_for_item("stone_pick") == 1, "reset_session clears brush bias")


func _source_contracts() -> void:
	var editor_src := (_TerrainEditor as GDScript).source_code
	_expect("_replace_cell_with_water_block" not in editor_src and "_has_adjacent_water(wx, wz):\n\t\t_grant_dig_loot" not in editor_src, "dig beside water has no instant water swap")
	var weapon_src := (load("res://weapons/weapon_controller.gd") as GDScript).source_code
	_expect(weapon_src.count("try_dig_brush(") == 1, "try_dig_brush is only the dig-tool stroke")
	_expect("is_action_just_pressed(\"brush_grow\")" in weapon_src and "is_action_just_pressed(\"brush_shrink\")" in weapon_src, "brush_grow/brush_shrink actions adjust brush radius")
	_expect("_is_active_combat_weapon" in weapon_src, "combat weapons stay off the dig path")
	_expect("func _try_dig_tool_or_fill_remove" not in weapon_src, "non-dig items have no fill dig path")
	var weapon_dig_at := weapon_src.find("func _do_dig_attack")
	var weapon_dig_end := weapon_src.find("\nfunc ", weapon_dig_at + 10)
	var weapon_dig_body := weapon_src.substr(weapon_dig_at, maxi(weapon_dig_end - weapon_dig_at, 0))
	_expect("try_dig_brush(" in weapon_dig_body and "if not _is_active_dig_tool()" in weapon_dig_body, "only the dig-tool stroke breaks blocks")
	var highlight_src := (load("res://player/target_highlight.gd") as GDScript).source_code
	_expect("func get_brush_footprint" in highlight_src and "BrushMark" in highlight_src, "highlight exposes the brush footprint")
	_expect("SHADOW_CASTING_SETTING_OFF" in highlight_src, "brush marks do not cast shadows")


func _boot() -> void:
	_wipe()
	flat = FlatWorld.new()
	root.add_child(flat)
	editor = _TerrainEditor.new()
	cm = _ChunkManager.new()
	root.add_child(editor)
	editor.world = flat
	editor.bind_chunk_manager(cm)
	await process_frame
	_expect(editor.world != null and editor.chunk_manager != null, "brush harness ready")


func _stroke(pos: Vector3, radius: int, player: Node = null) -> bool:
	await process_frame
	cm.edit_flush_count = 0
	cm.edit_flush_chunk_count = 0
	return editor.try_dig_brush(pos, radius, player)


func _radius_one_matches_single() -> void:
	_wipe()
	var single := Vector2i(4, 4)
	var single_ok: bool = await _stroke(Vector3(4.5, 0, 4.5), 1)
	_expect(single_ok and _layers_at(single.x, single.y) == -1, "radius 1 digs the aimed column one layer")
	_expect(_layers_at(5, 4) == 0 and _layers_at(4, 5) == 0, "radius 1 does not touch neighbours")
	_wipe()
	var dig_ok := editor.try_dig(Vector3(4.5, 0, 4.5))
	_expect(dig_ok and _layers_at(4, 4) == -1 and _layers_at(5, 4) == 0, "try_dig matches that single-column result")


func _disk_stroke(radius: int, expect_n: int, center: Vector2i, expect_chunks: int) -> void:
	_wipe()
	var pos := Vector3(float(center.x) + 0.5, 0.0, float(center.y) + 0.5)
	var ok: bool = await _stroke(pos, radius)
	var fp: Array = _LivingForce.footprint(center.x, center.y, radius, flat)
	var dug_ok := ok and fp.size() == expect_n
	for c in fp:
		var cell: Vector2i = c
		if _layers_at(cell.x, cell.y) != -1:
			dug_ok = false
	var outside := Vector2i(center.x + radius, center.y + radius)
	dug_ok = dug_ok and _layers_at(outside.x, outside.y) == 0
	_expect(dug_ok, "radius %d removes %d disk columns" % [radius, expect_n])
	var stats: Dictionary = editor.last_stroke_stats
	_expect(
		cm.edit_flush_count == 1 and int(stats.get("cell_count", 0)) == expect_n and int(stats.get("flush_chunks", -1)) == expect_chunks,
		"radius %d one flush, %d cells, %d chunks (got flush %d cells %s chunks %s)" % [
			radius, expect_n, expect_chunks, cm.edit_flush_count, str(stats.get("cell_count")), str(stats.get("flush_chunks"))
		]
	)


func _border_flush() -> void:
	_wipe()
	var ok: bool = await _stroke(Vector3(15.5, 0, 8.5), 2)
	var stats: Dictionary = editor.last_stroke_stats
	_expect(
		ok and cm.edit_flush_count == 1 and int(stats.get("cell_count", 0)) > 1 and int(stats.get("flush_chunks", 0)) >= 2,
		"chunk-border brush is one flush across %s chunks for %s cells" % [str(stats.get("flush_chunks")), str(stats.get("cell_count"))]
	)


func _vertical_skip() -> void:
	_wipe()
	var center := Vector2i(12, 18)
	flat.bases[Vector2i(center.x + 1, center.y)] = _layer() * 3.0
	var fp: Array = _LivingForce.footprint(center.x, center.y, 2, flat)
	var skipped: bool = not _cell_set(fp).has(Vector2i(center.x + 1, center.y)) and fp.size() == 4
	var ok: bool = await _stroke(Vector3(float(center.x) + 0.5, 0, float(center.y) + 0.5), 2)
	var dug_ok := ok and _layers_at(center.x, center.y) == -1
	dug_ok = dug_ok and _layers_at(center.x + 1, center.y) == 0
	dug_ok = dug_ok and _layers_at(center.x - 1, center.y) == -1
	_expect(skipped and dug_ok, "a column more than radius layers away is left standing")


func _deterministic() -> void:
	_wipe()
	var first_ok: bool = await _stroke(Vector3(6.5, 0, 30.5), 2)
	var snap := {}
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(2, 0)]:
		snap[Vector2i(6, 30) + d] = _layers_at(6 + d.x, 30 + d.y)
	_wipe()
	var second_ok: bool = await _stroke(Vector3(6.5, 0, 30.5), 2)
	var same := first_ok and second_ok
	for key in snap.keys():
		var cell: Vector2i = key
		if _layers_at(cell.x, cell.y) != int(snap[key]):
			same = false
	_expect(same, "the same brush stroke is deterministic")


func _range_block() -> void:
	_wipe()
	var player := ColumnPlayer.new()
	player.at = Vector3.ZERO
	var before := _TerrainEdits.edit_count()
	var ok: bool = await _stroke(Vector3(30.5, 0, 0.5), 2, player)
	_expect(not ok and editor.last_fail_reason == "Out of range" and _TerrainEdits.edit_count() == before, "aimed cell outside 8 voxels digs nothing")
	player.free()


func _range_partial() -> void:
	_wipe()
	var player := ColumnPlayer.new()
	player.at = Vector3.ZERO
	var center := Vector2i(3, 0)  # inside reach() (4.5 since ctl-03) so the stroke starts; radius-3 edge cells fall outside
	var fp: Array = _LivingForce.footprint(center.x, center.y, 3, flat)
	var expect: Array = []
	var skipped := 0
	for c in fp:
		var cell: Vector2i = c
		if _ActionTargeting._column_in_range(player, cell.x, cell.y, _ActionTargeting.reach()):
			expect.append(cell)
		else:
			skipped += 1
	var ok: bool = await _stroke(Vector3(3.5, 0, 0.5), 3, player)
	var good := ok and skipped > 0 and expect.size() > 0 and _layers_at(center.x, center.y) == -1
	for c in expect:
		var cell: Vector2i = c
		if _layers_at(cell.x, cell.y) != -1:
			good = false
	for c in fp:
		var cell: Vector2i = c
		if cell not in expect and _layers_at(cell.x, cell.y) != 0:
			good = false
	_expect(good, "cells outside interaction range are skipped (%d skipped)" % skipped)
	player.free()


func _protected() -> void:
	_wipe()
	var center := Vector2i(50, 50)
	flat.tiles[Vector2i(51, 50)] = _VoxelTypes.RIVER
	_FeatureRegistry.register_feature(49, 50, _WorldFeatureTypes.FeatureKind.TOWN, {"player_built": false})
	_FeatureRegistry.register_feature(50, 51, _WorldFeatureTypes.FeatureKind.RUIN, {"player_built": false})
	_FeatureRegistry.register_feature(50, 49, _WorldFeatureTypes.FeatureKind.NONE, {
		"player_built": true,
		"build_id": "stone_wall",
	})
	_FeatureRegistry.register_feature(50, 50, _WorldFeatureTypes.FeatureKind.NONE, {"crystal_overlay": true})
	var ok: bool = await _stroke(Vector3(50.5, 0, 50.5), 2)
	var good := ok and _layers_at(50, 50) == -1
	good = good and _layers_at(51, 50) == 0 and _layers_at(49, 50) == 0
	good = good and _layers_at(50, 51) == 0 and _layers_at(50, 49) == 0
	good = good and not _FeatureRegistry.get_feature(49, 50).is_empty()
	good = good and not _FeatureRegistry.get_feature(50, 51).is_empty()
	good = good and str(_FeatureRegistry.get_feature(50, 49).get("build_id", "")) == "stone_wall"
	good = good and bool(_FeatureRegistry.get_feature(50, 50).get("crystal_overlay", false))
	_expect(good, "water, town, ruin, player wall, and crystal overlay are not removed")
	_wipe()
	var before := _TerrainEdits.edit_count()
	var outside: bool = await _stroke(Vector3(2000.5, 0, 0.5), 2)
	_expect(not outside and editor.last_fail_reason == "Outside playable area" and _TerrainEdits.edit_count() == before, "outside the playable border digs nothing")


func _gameplay_floor() -> void:
	_wipe()
	var digs := 0
	for _i in 8:
		await process_frame
		if editor.try_dig(Vector3(3.5, 0, 12.5)):
			digs += 1
		else:
			break
	_expect(digs == 4 and _layers_at(3, 12) == -4, "gameplay dig floor stops at -4 layers (%d digs, center %d)" % [digs, _layers_at(3, 12)])
	_expect(editor.last_fail_reason == "Can't dig any deeper", "deeper dig reports the floor")
	_expect(_layers_at(5, 12) == 0, "settle does not cascade two columns out")


func _save_roundtrip() -> void:
	_wipe()
	var ok: bool = await _stroke(Vector3(9.5, 0, 40.5), 2)
	var blob: Dictionary = _TerrainEdits.to_dict()
	var center := _layers_at(9, 40)
	var side := _layers_at(10, 40)
	_TerrainEdits.reset()
	var cleared := _layers_at(9, 40) == 0 and _layers_at(10, 40) == 0
	_TerrainEdits.load_from_dict(blob)
	_expect(
		ok and cleared and _layers_at(9, 40) == center and _layers_at(10, 40) == side and center == -1 and side == -1,
		"save/resume keeps the brush edits"
	)


func _radius_one_beside_water() -> void:
	_wipe()
	_ChannelRegistry.reset()
	flat.tiles[Vector2i(2, 70)] = _VoxelTypes.RIVER
	var h0 := flat.get_surface_height(3.0, 70.0)
	var ok: bool = await _stroke(Vector3(3.5, 0, 70.5), 1)
	var tile := _FeatureRegistry.get_tile_override(3, 70)
	var h1 := flat.get_surface_height(3.0, 70.0)
	var stamped := tile == _VoxelTypes.RIVER or tile == _VoxelTypes.WATER
	_expect(ok and not stamped and h1 < h0 - 0.01, "radius 1 beside water digs a cavity and stamps no tile")


func _finish() -> void:
	if failed:
		print("Dig brush tests FAILED")
		quit(1)
		return
	print("All dig brush tests OK")
	quit(0)
