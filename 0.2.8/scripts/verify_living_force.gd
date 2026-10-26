extends SceneTree


const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _LivingForce = preload("res://world/living_force.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _FluidService = preload("res://fluids/voxel_fluid_service.gd")

var failed := false
var flat: FlatWorld
var editor: TerrainEditor


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


class DepthCrystal:
	extends Node
	var depths: Dictionary = {}
	var nudges: int = 0

	func get_depth_at(wx: int, wz: int) -> float:
		return float(depths.get(Vector2i(wx, wz), 0.0))

	func nudge_depth(wx: int, wz: int, delta: float) -> float:
		var cur := get_depth_at(wx, wz)
		if cur < 0.04:
			return cur
		depths[Vector2i(wx, wz)] = cur + delta
		nudges += 1
		return float(depths[Vector2i(wx, wz)])


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
	_LivingForce.settle_enabled = true
	_LivingForce.settle_trigger_layers = 2
	_LivingForce.settle_max_cells = 4
	_LivingForce.water_inflow_enabled = true
	_LivingForce.crystal_react_enabled = true
	_LivingForce.pushback_enabled = true
	if flat:
		flat.bases.clear()
		flat.tiles.clear()


func _run() -> void:
	_settle_stored_floor()
	_settle_cap_and_wall()
	await _boot()
	if editor == null:
		_finish()
		return
	await _settle_on_second_dig()
	await _water_inflow()
	await _crystal_pressure()
	_crystal_pushback()
	_finish()


func _settle_stored_floor() -> void:
	_wipe()
	var c := Vector2i(40, 40)
	for _i in 6:
		if not _TerrainEdits.dig(c.x, c.y, 1):
			_expect(false, "stored dig %d should succeed" % _i)
			return
		_LivingForce.apply_settle([c], null)
	var rim := _layers_at(41, 40) == -5 and _layers_at(39, 40) == -5
	rim = rim and _layers_at(40, 41) == -5 and _layers_at(40, 39) == -5
	var outer := _layers_at(42, 40) == 0 and _layers_at(41, 41) == 0
	_expect(_layers_at(40, 40) == -6 and rim and outer, "six digs slump the rim to -5 and leave the outer ring")
	var stuck := not _TerrainEdits.dig(40, 40, 1)
	_LivingForce.apply_settle([c], null)
	_expect(stuck and _layers_at(42, 40) == 0 and _layers_at(41, 40) == -5, "settle stops at the stored floor and does not run outward")


func _settle_cap_and_wall() -> void:
	_wipe()
	_LivingForce.settle_max_cells = 2
	var c := Vector2i(70, 70)
	_TerrainEdits.dig(c.x, c.y, 1)
	_TerrainEdits.dig(c.x, c.y, 1)
	var done: Array = _LivingForce.apply_settle([c], null)
	_LivingForce.settle_max_cells = 4
	_expect(done.size() == 2 and _layers_at(71, 70) == -1 and _layers_at(69, 70) == -1, "settle caps at settle_max_cells")
	_expect(_layers_at(70, 71) == 0 and _layers_at(70, 69) == 0, "neighbours past the cap stay put")
	_wipe()
	_FeatureRegistry.register_feature(81, 80, _WorldFeatureTypes.FeatureKind.NONE, {
		"player_built": true,
		"build_id": "stone_wall",
	})
	for _i in 4:
		_TerrainEdits.dig(80, 80, 1)
		_LivingForce.apply_settle([Vector2i(80, 80)], null)
	_expect(_layers_at(81, 80) == 0 and _layers_at(79, 80) == -3, "a player wall does not slump")
	_expect(str(_FeatureRegistry.get_feature(81, 80).get("build_id", "")) == "stone_wall", "settle does not clear the wall")


func _boot() -> void:
	_wipe()
	flat = FlatWorld.new()
	root.add_child(flat)
	await process_frame
	editor = _TerrainEditor.new()
	var cm := _ChunkManager.new()
	root.add_child(editor)
	editor.world = flat
	editor.bind_chunk_manager(cm)
	await process_frame
	_expect(editor.world != null, "living-force harness ready")


func _settle_on_second_dig() -> void:
	_wipe()
	var first := editor.try_dig(Vector3(8.5, 0, 8.5))
	var first_ok := first and _layers_at(8, 8) == -1 and _layers_at(9, 8) == 0
	await process_frame
	var second := editor.try_dig(Vector3(8.5, 0, 8.5))
	var second_ok := second and _layers_at(8, 8) == -2 and _layers_at(9, 8) == -1 and _layers_at(10, 8) == 0
	_expect(first_ok, "the first dig does not slump")
	_expect(second_ok, "the second dig slumps the orthogonal rim one layer and stops there")


func _water_inflow() -> void:
	_wipe()
	var fluid: Node = _FluidService.new()
	root.add_child(fluid)
	await process_frame
	flat.tiles[Vector2i(30, 20)] = _VoxelTypes.RIVER
	await process_frame
	var ok := editor.try_dig_brush(Vector3(29.5, 0, 20.5), 2)
	fluid.call("request_flow", 29, 20, 6)
	var center_wet := _ChannelRegistry.has_fluid(29, 20, _ChannelRegistry.FLUID_WATER)
	var river_dry := not _ChannelRegistry.has_fluid(30, 20, _ChannelRegistry.FLUID_WATER)
	var far_dry := not _ChannelRegistry.has_fluid(29, 40, _ChannelRegistry.FLUID_WATER)
	var boxed := true
	var wet_n := 0
	for key in _ChannelRegistry.all_fluid_positions(_ChannelRegistry.FLUID_WATER):
		var pos: Vector2i = key
		wet_n += 1
		if absi(pos.x - 29) > 6 or absi(pos.y - 20) > 6:
			boxed = false
	var before := wet_n
	fluid.call("request_flow", 29, 20, 1)
	var after := 0
	var still_boxed := true
	for key in _ChannelRegistry.all_fluid_positions(_ChannelRegistry.FLUID_WATER):
		var pos: Vector2i = key
		after += 1
		if absi(pos.x - 29) > 6 or absi(pos.y - 20) > 6:
			still_boxed = false
	_expect(
		ok and _layers_at(29, 20) == -1 and _layers_at(30, 20) == 0 and center_wet and river_dry and far_dry and boxed,
		"a column dug below the river takes water; the river column and a far cell do not"
	)
	_expect(before > 0 and still_boxed and far_dry, "more flow steps stay inside the local box (%d wet)" % after)
	fluid.queue_free()


func _crystal_pressure() -> void:
	_wipe()
	editor._living_crystal = null
	editor._living_crystal_tries = 0
	var crystal := DepthCrystal.new()
	crystal.name = "DepthCrystal"
	root.add_child(crystal)
	crystal.add_to_group("crystal_manager")
	var origin := Vector2i(14, 14)
	var depth_at := func(x: int, z: int) -> float:
		return crystal.get_depth_at(x, z)
	var none: Array = _LivingForce.pressure_targets(origin, depth_at, 0.04, 2, 4)
	editor.call("_living_crystal_react", [origin], &"dig")
	_expect(none.is_empty() and crystal.nudges == 0 and crystal.depths.is_empty(), "digging does not seed crystal")
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			crystal.depths[Vector2i(origin.x + dx, origin.y + dz)] = 0.5
	crystal.depths[Vector2i(origin.x, origin.y + 4)] = 0.5
	var targets: Array = _LivingForce.pressure_targets(origin, depth_at, 0.04, 2, 4)
	editor.call("_living_crystal_react", [origin], &"dig")
	var nudged_ok := crystal.nudges == 4 and targets.size() == 4
	for t in targets:
		var cell: Vector2i = t
		if absf(crystal.get_depth_at(cell.x, cell.y) - 0.56) > 0.0001:
			nudged_ok = false
	var outside := absf(crystal.get_depth_at(origin.x, origin.y + 4) - 0.5) < 0.0001
	var fifth := true
	var seen := {}
	for t in targets:
		seen[t] = true
	for key in crystal.depths.keys():
		if seen.has(key):
			continue
		if absf(float(crystal.depths[key]) - 0.5) > 0.0001:
			fifth = false
	_expect(nudged_ok and outside and fifth, "dig pressure hits 4 existing cells and leaves the rest")
	var before_build := crystal.get_depth_at(origin.x, origin.y)
	crystal.nudges = 0
	editor.call("_living_crystal_react", [origin], &"build")
	var build_delta := crystal.get_depth_at(origin.x, origin.y) - before_build
	_expect(absf(build_delta - _LivingForce.crystal_build_pressure) < 0.0001 or crystal.nudges > 0, "a new wall adds build pressure to nearby crystal")
	var gained := 0.0
	for key in crystal.depths.keys():
		var cell: Vector2i = key
		gained += crystal.get_depth_at(cell.x, cell.y) - 0.5
	_expect(gained > 0.2 and gained < 0.7, "pressure stays capped (gained %.3f)" % gained)


func _crystal_pushback() -> void:
	_wipe()
	var wall := Vector2i(10, 10)
	var town := Vector2i(12, 12)
	_FeatureRegistry.register_feature(wall.x, wall.y, _WorldFeatureTypes.FeatureKind.NONE, {
		"player_built": true,
		"build_id": "stone_wall",
		"raises_terrain": false,
	})
	_FeatureRegistry.register_feature(town.x, town.y, _WorldFeatureTypes.FeatureKind.TOWN, {"player_built": false})
	_LivingForce.push_watch[wall] = true
	_LivingForce.push_watch[town] = true
	var depth_at := func(_x: int, _z: int) -> float:
		return 1.0
	var broke_on := -1
	for i in 8:
		var broke: Array = _LivingForce.tick_pushback(depth_at)
		if not broke.is_empty():
			broke_on = i + 1
			break
	var wall_gone := _FeatureRegistry.get_feature(wall.x, wall.y).is_empty()
	var town_ok := int(_FeatureRegistry.get_feature(town.x, town.y).get("kind", -1)) == _WorldFeatureTypes.FeatureKind.TOWN
	var extra := 0
	for _i in 100:
		extra += _LivingForce.tick_pushback(depth_at).size()
	_expect(broke_on >= 2 and broke_on <= 6 and wall_gone and town_ok and extra == 0, "pushback breaks one player wall on tick %d and then stops; the town stays" % broke_on)

	_wipe()
	_FeatureRegistry.register_feature(wall.x, wall.y, _WorldFeatureTypes.FeatureKind.NONE, {
		"player_built": true,
		"build_id": "wood_wall",
		"raises_terrain": false,
	})
	_LivingForce.push_watch[wall] = true
	_LivingForce.tick_pushback(depth_at)
	var mid := float(_FeatureRegistry.get_feature(wall.x, wall.y).get("crystal_push", 0.0))
	var blob: Dictionary = _FeatureRegistry.to_dict()
	_FeatureRegistry.reset()
	_LivingForce.reset_session()
	_FeatureRegistry.apply_save_overlay(blob)
	_LivingForce.rearm_push_watch()
	var restored := float(_FeatureRegistry.get_feature(wall.x, wall.y).get("crystal_push", 0.0))
	var armed := bool(_FeatureRegistry.get_feature(wall.x, wall.y).get("crystal_push_armed", false))
	var watch_ok := _LivingForce.push_watch.has(wall)
	var rest_broke := -1
	for i in 8:
		var broke: Array = _LivingForce.tick_pushback(depth_at)
		if not broke.is_empty():
			rest_broke = i + 1
			break
	var quiet := 0
	for _i in 100:
		quiet += _LivingForce.tick_pushback(depth_at).size()
	_expect(
		absf(mid - _LivingForce.pushback_step) < 0.001 and absf(restored - mid) < 0.001 and armed and watch_ok,
		"crystal_push survives save/resume (%.3f)" % restored
	)
	_expect(rest_broke > 0 and _FeatureRegistry.get_feature(wall.x, wall.y).is_empty() and quiet == 0, "resumed pushback still breaks once and does not run away")


func _finish() -> void:
	_LivingForce.reset_session()
	_LivingForce.settle_max_cells = 4
	if failed:
		print("Living force tests FAILED")
		quit(1)
		return
	print("All living force tests OK")
	quit(0)
