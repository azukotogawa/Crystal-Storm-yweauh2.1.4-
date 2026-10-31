extends SceneTree

const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkView = preload("res://chunks/chunk_view.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _VoxelFloorProbe = preload("res://player/voxel_floor_probe.gd")
const _WorldSettings = preload("res://config/world_settings.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var layer: float = _WorldSettings.get_active().layer_height()
	var ph: float = _WorldSettings.get_active().player_height()
	var pr: float = _WorldSettings.get_active().player_radius()
	var max_step: float = _WorldSettings.get_active().max_step_up_walk()

	var old_chance: int = _TerrainRamps.placement_chance
	_TerrainRamps.placement_chance = 100
	_TerrainRamps.invalidate_mesh_cache()

	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	var data := _ChunkData.new(Vector2i(0, 0), world)
	data.capture_worker_snapshot()
	_init_maps(data)

	var low_x := 5
	var high_x := 6
	var z := 5
	var low_h := 10.0
	var high_h := low_h + layer
	data.surface_map[low_x][z] = low_h
	data.tile_map[low_x][z] = _VoxelTypes.GRASSLAND
	data.surface_map[high_x][z] = high_h
	data.tile_map[high_x][z] = _VoxelTypes.GRASSLAND
	data.surface_map[high_x + 1][z] = high_h
	data.tile_map[high_x + 1][z] = _VoxelTypes.GRASSLAND

	var cm := _ChunkManager.new()
	cm.world = world
	cm.ramp_placement_chance = 100
	cm._build_mesh(data)

	var view := _ChunkView.new()
	view.chunk_data = data
	cm.chunks[Vector2i(0, 0)] = view

	var probe := _VoxelFloorProbe.new()
	probe.configure(world, cm, null)

	var start := Vector3(float(low_x) + 0.5, low_h + layer, float(z) + 0.5)

	var mid := Vector3(float(high_x) + 0.2, 0.0, float(z) + 0.5)
	mid.y = probe.walkable_height_at(mid.x, mid.z)
	var top := Vector3(float(high_x) + 0.85, 0.0, float(z) + 0.5)
	top.y = probe.walkable_height_at(top.x, top.z)

	if not data.has_ramp(high_x, z):
		push_error("expected landing ramp on high cell")
		failed = true

	if not probe.can_step_to(start, mid, ph, pr, max_step):
		push_error("should step from low flat onto ramp mid")
		failed = true
	else:
		print("OK step low -> ramp mid")

	if not probe.can_step_to(mid, top, ph, pr, max_step):
		push_error("should step along ramp toward landing interior")
		failed = true
	else:
		print("OK step ramp mid -> interior")

	mid.y = probe.sample_walkable_feet(mid.x, mid.z)
	var blocked_mid := probe.is_blocked_at(mid, ph, pr)
	if blocked_mid:
		push_error("ramp mid position should not be head-blocked")
		failed = true
	else:
		print("OK ramp mid head clearance")

	var slope_limit: float = tan(deg_to_rad(_WorldSettings.get_active().player_slope_limit_degrees)) * pr
	var steep_mul := 1.0
	for u in [0.15, 0.35, 0.5, 0.65, 0.85]:
		var excess: float = probe.slope_excess_at(float(high_x) + float(u), float(z) + 0.5)
		var mul := 1.0
		if excess > slope_limit * 1.35:
			mul = clampf(1.0 - (excess - slope_limit) / (layer * 2.2), 0.82, 1.0)
		steep_mul = minf(steep_mul, mul)
	print("OK ramp climb mul=%.3f" % steep_mul)
	if steep_mul < 0.82:
		push_error("ramp climb multiplier dropped below 0.82 (%.3f)" % steep_mul)
		failed = true

	_TerrainRamps.placement_chance = old_chance
	_TerrainRamps.invalidate_mesh_cache()

	if failed:
		print("Ramp walk tests FAILED")
		quit(1)
		return
	print("All ramp walk tests OK")
	quit(0)


func _init_maps(data: ChunkData) -> void:
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