extends SceneTree
## Body-level water: sources stay sources; flooded cells are overlay-only; one surface Y.


const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _VoxelFluidService = preload("res://fluids/voxel_fluid_service.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")


var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


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
	query.test_base_heights = heights
	query.test_tiles = tiles

	if not bool(svc.call("is_persistent_source", 2, 2)):
		_fail("river tile must be a persistent source")
	if bool(svc.call("is_persistent_source", 3, 2)):
		_fail("dry land must not be a source")

	# Same-height neighbor is not an indentation — do not stack water on ground.
	svc.call("recompute_region_now", 2, 2, 2, 4)
	if _ChannelRegistry.has_fluid(3, 2, _ChannelRegistry.FLUID_WATER):
		_fail("undug same-height land must not get overlay water")
	else:
		print("OK no water stacked on undug ground")

	_TerrainEdits.dig(3, 2, 1)
	svc.call("recompute_region_now", 3, 2, 2, 6)
	if not bool(svc.call("is_wet_column", 3, 2)):
		_fail("dug cell next to river must flood")
	if bool(svc.call("is_persistent_source", 3, 2)):
		_fail("flooded cell must not become a source")
	if not bool(svc.call("is_persistent_source", 2, 2)):
		_fail("river must remain a source after adjacent dig")
	if _ChannelRegistry.has_fluid(2, 2, _ChannelRegistry.FLUID_WATER):
		_fail("source river must not be stored as overlay occupancy")
	if not _ChannelRegistry.has_fluid(3, 2, _ChannelRegistry.FLUID_WATER):
		_fail("flooded cell must persist overlay occupancy")
	var sy: float = float(svc.call("get_body_surface_y", 3, 2))
	var src_top: float = 10.0 + layer
	if absf(sy - src_top) > 0.05:
		_fail("body surface_y want %.2f got %.2f" % [src_top, sy])
	else:
		print("OK flood from river source surface_y=%.2f" % sy)

	_TerrainEdits.dig(4, 2, 1)
	svc.call("recompute_region_now", 4, 2, 2, 8)
	if not bool(svc.call("is_wet_column", 4, 2)):
		_fail("second dug cell must flood from the wet body")
	if bool(svc.call("is_persistent_source", 4, 2)):
		_fail("second flood must not be a source")
	var sy2: float = float(svc.call("get_body_surface_y", 4, 2))
	if absf(sy2 - sy) > 0.05:
		_fail("connected wet cells must share surface_y %.2f vs %.2f" % [sy, sy2])
	else:
		print("OK propagation same surface_y")

	# Fill/remove the extension; river stays a source.
	_TerrainEdits.build_wall(3, 2, _VoxelTypes.STONE)
	_TerrainEdits.build_wall(4, 2, _VoxelTypes.STONE)
	svc.call("recompute_region_now", 3, 2, 2, 6)
	if bool(svc.call("is_wet_column", 3, 2)) and _ChannelRegistry.has_fluid(3, 2, _ChannelRegistry.FLUID_WATER):
		_fail("filled flooded cell must dry overlay")
	if not bool(svc.call("is_persistent_source", 2, 2)):
		_fail("river must remain a source after fill")
	else:
		print("OK fill dries flood; river still source")

	# Dry land: no source in halo → not wet.
	_ChannelRegistry.reset()
	_TerrainEdits.reset()
	query.test_tiles[Vector2i(8, 6)] = _VoxelTypes.GRASSLAND
	_TerrainEdits.dig(8, 6, 1)
	svc.call("recompute_region_now", 8, 6, 2, 4)
	if _ChannelRegistry.has_fluid(8, 6, _ChannelRegistry.FLUID_WATER):
		_fail("dry-land dig must not create overlay water")
	else:
		print("OK dry dig stays dry")

	# Open the far cell first, then the block between it and the river.
	# The link becomes a water tile; the earlier hole must still fill, and
	# the wave must continue into the next connected empty cell.
	_ChannelRegistry.reset()
	_TerrainEdits.reset()
	for x3 in 12:
		for z3 in 8:
			heights[Vector2i(x3, z3)] = 10.0
			tiles[Vector2i(x3, z3)] = _VoxelTypes.GRASSLAND
	tiles[Vector2i(2, 2)] = _VoxelTypes.RIVER
	query.test_base_heights = heights
	query.test_tiles = tiles
	_TerrainEdits.dig(4, 2, 1)
	_TerrainEdits.dig(5, 2, 1)
	_TerrainEdits.dig(6, 2, 1)
	_TerrainEdits.dig(7, 2, 1)
	svc.set("_dirty_cells", {})
	svc.call("recompute_region_now", 4, 2, 2, 4)
	if bool(svc.call("is_wet_column", 4, 2)):
		_fail("cell two away must stay dry while the block between is solid")
	else:
		print("OK blocked trench stays dry")
	tiles[Vector2i(3, 2)] = _VoxelTypes.RIVER
	query.test_tiles = tiles
	svc.call("requeue_neighbors_on_edit", 3, 2)
	var spread_ok := true
	for sx in [4, 5, 6]:
		if not bool(svc.call("is_wet_column", sx, 2)):
			_fail("opening the link must flood connected empty cell (%d, 2)" % sx)
			spread_ok = false
	if _ChannelRegistry.has_fluid(3, 3, _ChannelRegistry.FLUID_WATER):
		_fail("requeue must not wet undug same-height ground")
		spread_ok = false
	if not bool(svc.call("is_persistent_source", 2, 2)):
		_fail("river source lost after neighbour requeue")
		spread_ok = false
	if spread_ok:
		print("OK water spread through the opened link")
	# Frontier only: river is outside this dirty set. Overlay must carry the wave.
	svc.set("_dirty_cells", {Vector2i(7, 2): true, Vector2i(6, 2): true})
	svc.call("_tick_water", 0.1)
	if not bool(svc.call("is_wet_column", 7, 2)):
		_fail("water must keep spreading into the next connected empty cell")
	elif _ChannelRegistry.has_fluid(2, 2, _ChannelRegistry.FLUID_WATER):
		_fail("continuation must not store the river as overlay")
	else:
		print("OK continued spread past the first empty cells")

	# Longer gap than one local step. Later ticks must keep the wave going
	# from the dirty set requeue left behind. No hand-seeded frontier.
	_ChannelRegistry.reset()
	_TerrainEdits.reset()
	for x4 in 16:
		for z4 in 6:
			heights[Vector2i(x4, z4)] = 10.0
			tiles[Vector2i(x4, z4)] = _VoxelTypes.GRASSLAND
	tiles[Vector2i(1, 2)] = _VoxelTypes.RIVER
	query.test_base_heights = heights
	query.test_tiles = tiles
	for gx in range(3, 12):
		_TerrainEdits.dig(gx, 2, 1)
	svc.set("_dirty_cells", {})
	tiles[Vector2i(2, 2)] = _VoxelTypes.RIVER
	query.test_tiles = tiles
	svc.call("requeue_neighbors_on_edit", 2, 2)
	var chain_wet := 0
	for _step in 8:
		var pending: Dictionary = svc.get("_dirty_cells")
		if pending.is_empty():
			break
		svc.call("_tick_water", 0.1)
	for gx2 in range(3, 12):
		if bool(svc.call("is_wet_column", gx2, 2)):
			chain_wet += 1
		else:
			_fail("opened link must keep filling the gap at (%d, 2)" % gx2)
	if _ChannelRegistry.has_fluid(2, 3, _ChannelRegistry.FLUID_WATER):
		_fail("long gap must not wet same-height ground")
	elif chain_wet == 9:
		print("OK full gap filled across follow-up ticks cells=%d" % chain_wet)

	# Idle sleep / no world scan.
	svc.set("_dirty_cells", {})
	var t0 := Time.get_ticks_usec()
	svc.call("_tick_water", 0.1)
	var idle_us: int = Time.get_ticks_usec() - t0
	var diag: Dictionary = svc.call("get_sim_diagnostics")
	if not bool(diag.get("sleeping", false)):
		_fail("empty dirty must sleep")
	if int(diag.get("subset_cells", -1)) != 0:
		_fail("idle must not load a subset, got %s" % str(diag.get("subset_cells")))
	if idle_us > 2000:
		_fail("idle tick too slow %d us" % idle_us)
	else:
		print("OK idle sleep %d us" % idle_us)

	# Lid sits on the dug bed so the pool is below surrounding ground (not flush).
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
	data_w._worker_water_lid[Vector2i(3, 2)] = 10.0 + layer
	var cm_w := _ChunkManager.new()
	var water_lid := 0
	var dirt_top_indent := 0
	var water_flush := 0
	for qw in cm_w._build_mesh(data_w).get("quads", []):
		if int(qw.get("x", -1)) != 3 or int(qw.get("z", -1)) != 2:
			continue
		if int(qw.get("face_code", -1)) != 0:
			continue
		var qy: float = float(qw.get("y", -1.0))
		if int(qw.get("type", -1)) == _VoxelTypes.WATER and absf(qy - dug_bed) < 0.05:
			water_lid += 1
		if int(qw.get("type", -1)) == _VoxelTypes.WATER and absf(qy - 10.0) < 0.05:
			water_flush += 1
		if int(qw.get("type", -1)) != _VoxelTypes.WATER and absf(qy - dug_bed) < 0.05:
			dirt_top_indent += 1
	if water_lid < 1:
		_fail("indent must emit water lid on dug bed, lids=%d" % water_lid)
	elif water_flush > 0:
		_fail("indent water must not sit flush with undug ground, flush_lids=%d" % water_flush)
	elif dirt_top_indent > 0:
		_fail("indent dirt top must be replaced by water lid, dirt_tops=%d" % dirt_top_indent)
	else:
		print("OK water lid on dug bed (below surrounding ground)")

	# Wet columns are not ramps.
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
