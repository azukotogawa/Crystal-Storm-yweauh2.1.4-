extends SceneTree


const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _VoxelFluidService = preload("res://fluids/voxel_fluid_service.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _Capture = preload("res://helpers/probe_capture.gd")


var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _shot(step_name: String) -> void:
	await _Capture.capture_step(step_name)


func _run() -> void:
	_ChannelRegistry.reset()
	_TerrainEdits.reset()

	var svc: Node = _VoxelFluidService.new()
	root.add_child(svc)
	await process_frame
	var query = svc.get("_terrain_query")
	var layer: float = _WorldSettings.get_active().layer_height()
	var heights := {}
	var tiles := {}
	for x in 12:
		for z in 8:
			heights[Vector2i(x, z)] = 10.0
			tiles[Vector2i(x, z)] = _VoxelTypes.GRASSLAND
	tiles[Vector2i(2, 2)] = _VoxelTypes.RIVER
	heights[Vector2i(2, 2)] = 10.0 - layer
	query.test_base_heights = heights
	query.test_tiles = tiles

	if not bool(svc.call("is_persistent_source", 2, 2)):
		_fail("river tile must be a persistent source")
	if bool(svc.call("is_persistent_source", 3, 2)):
		_fail("dry land must not be a source")

	svc.call("request_flow", 2, 2, 4)
	if _ChannelRegistry.has_fluid(3, 2, _ChannelRegistry.FLUID_WATER):
		_fail("undug same-height land must not get overlay water")
	else:
		print("OK no water stacked on undug ground")

	_TerrainEdits.dig(3, 2, 2)
	svc.call("request_flow", 3, 2, 6)
	if not bool(svc.call("is_wet_column", 3, 2)):
		_fail("dug cell beside a river source must fill")
	elif bool(svc.call("is_persistent_source", 3, 2)):
		_fail("flowed cell must not be a persistent source")
	elif not bool(svc.call("is_persistent_source", 2, 2)):
		_fail("river source must stay a source")
	else:
		print("OK dug cell beside source fills through the single flow path")

	var sy: float = float(svc.call("get_body_surface_y", 3, 2))
	if sy <= 0.01:
		_fail("flowed cell must report a surface height")
	else:
		print("OK flowed cell surface_y=%.2f" % sy)

	_ChannelRegistry.reset()
	_TerrainEdits.reset()
	query.test_tiles[Vector2i(8, 6)] = _VoxelTypes.GRASSLAND
	_TerrainEdits.dig(8, 6, 1)
	svc.call("request_flow", 8, 6, 4)
	if _ChannelRegistry.has_fluid(8, 6, _ChannelRegistry.FLUID_WATER):
		_fail("dry-land dig must not create overlay water")
	else:
		print("OK dry dig stays dry")

	var svc_src: String = (_VoxelFluidService as GDScript).source_code
	var editor_src: String = (_TerrainEditor as GDScript).source_code
	var registry_src: String = (load("res://world/channel_registry.gd") as GDScript).source_code
	var banned := ["_flood_body", "_persist_body", "tick_equilibrium", "recompute_region_now", "try_channel_water"]
	var leaks := []
	for word in banned:
		if word in svc_src or word in editor_src or word in registry_src:
			leaks.append(word)
	if not leaks.is_empty():
		_fail("second water flow path reachable: %s" % str(leaks))
	elif svc_src.count("tick_flow(") != 1:
		_fail("service must call tick_flow exactly once, saw %d" % svc_src.count("tick_flow("))
	else:
		print("OK one flow entry point: service -> VoxelFluidEngine.tick_flow")


	var data_w := _ChunkData.new(Vector2i.ZERO, null)
	data_w.capture_worker_snapshot()
	data_w.surface_map.resize(_ChunkData.SIZE)
	data_w.tile_map.resize(_ChunkData.SIZE)
	for xw in _ChunkData.SIZE:
		data_w.surface_map[xw] = []
		data_w.tile_map[xw] = []
		data_w.surface_map[xw].resize(_ChunkData.SIZE)
		data_w.tile_map[xw].resize(_ChunkData.SIZE)
		for zw in _ChunkData.SIZE:
			data_w.surface_map[xw][zw] = 10.0
			data_w.tile_map[xw][zw] = _VoxelTypes.GRASSLAND
	data_w.tile_map[2][2] = _VoxelTypes.RIVER
	var dug_bed: float = 10.0 - layer
	data_w.surface_map[3][2] = dug_bed
	var flow_top: float = dug_bed + layer + 0.875 * layer
	data_w._worker_water_lid[Vector2i(3, 2)] = flow_top
	var cm_w := _ChunkManager.new()
	var water_lid := 0
	var water_on_bed := 0
	var dirt_top := 0
	for qw in cm_w._build_mesh(data_w).get("quads", []):
		if int(qw.get("x", -1)) != 3 or int(qw.get("z", -1)) != 2:
			continue
		if int(qw.get("face_code", -1)) != 0:
			continue
		var qy: float = float(qw.get("y", -1.0))
		var is_water: bool = int(qw.get("type", -1)) == _VoxelTypes.WATER
		if is_water and absf(qy - (dug_bed + layer)) < 0.05 and absf(qy + float(qw.get("dim_y", 0.0)) * layer - flow_top) < 0.05:
			water_lid += 1
		if is_water and absf(qy - dug_bed) < 0.05:
			water_on_bed += 1
		if not is_water and absf(qy - dug_bed) < 0.05:
			dirt_top += 1
	if water_lid != 1:
		_fail("flowed level 7 cell must emit one water lid from the hole floor to its surface, lids=%d" % water_lid)
	elif water_on_bed > 0:
		_fail("flowed water must not replace the floor block, water_on_bed=%d" % water_on_bed)
	elif dirt_top != 1:
		_fail("hole floor must keep its ground top under the water, dirt_tops=%d" % dirt_top)
	else:
		print("OK flowed water lid renders at its real height over the hole floor")

	_ChannelRegistry.reset()
	_TerrainEdits.reset()
	var data := _ChunkData.new(Vector2i.ZERO, null)
	data.capture_worker_snapshot()
	data.surface_map.resize(_ChunkData.SIZE)
	data.tile_map.resize(_ChunkData.SIZE)
	for x in _ChunkData.SIZE:
		data.surface_map[x] = []
		data.tile_map[x] = []
		data.surface_map[x].resize(_ChunkData.SIZE)
		data.tile_map[x].resize(_ChunkData.SIZE)
		for z in _ChunkData.SIZE:
			data.surface_map[x][z] = 8.0
			data.tile_map[x][z] = _VoxelTypes.GRASSLAND
	data.tile_map[5][5] = _VoxelTypes.RIVER
	data.surface_map[5][5] = 8.0
	data.surface_map[6][5] = 8.0 + layer
	data._worker_water_lid[Vector2i(5, 5)] = 8.0 + layer
	var cm := _ChunkManager.new()
	cm.ramp_placement_chance = 100
	var ramps := 0
	for q in cm._build_mesh(data).get("quads", []):
		var fc := int(q.get("face_code", -1))
		if fc == 7 or fc == 8:
			if int(q.get("x", -1)) == 5 and int(q.get("z", -1)) == 5:
				ramps += 1
			if int(q.get("x", -1)) == 6 and int(q.get("z", -1)) == 5:
				ramps += 1
	if ramps > 0:
		_fail("wet/source columns must not emit ramps, got %d" % ramps)
	else:
		print("OK no ramps on wet/source columns")

	if _failed == 0:
		print("All water body tests OK")
		quit(0)
	else:
		push_error("verify_water_body: %d failure(s)" % _failed)
		quit(1)
