extends SceneTree
## P1 regression: player can walk down a cardinal ramp without head-block false positives.


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
	var probe_src := (load("res://player/voxel_floor_probe.gd") as GDScript).source_code
	if "_solid_blocks_head" not in probe_src:
		push_error("voxel_floor_probe must use ramp-aware head clearance")
		failed = true
	else:
		print("OK ramp-aware head clearance helper")

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

	var cm := _ChunkManager.new()
	cm.world = world
	cm.ramp_placement_chance = 100
	cm._build_mesh(data)
	cm.chunks[Vector2i(0, 0)] = _ChunkView.new()
	cm.chunks[Vector2i(0, 0)].chunk_data = data

	var probe := _VoxelFloorProbe.new()
	probe.configure(world, cm, null)

	if not data.has_ramp(high_x, z):
		push_error("expected landing ramp on high cell")
		failed = true

	var top := Vector3(float(high_x) + 0.85, 0.0, float(z) + 0.5)
	top.y = probe.walkable_height_at(top.x, top.z)
	var mid := Vector3(float(high_x) + 0.25, 0.0, float(z) + 0.5)
	mid.y = probe.walkable_height_at(mid.x, mid.z)
	var low := Vector3(float(low_x) + 0.5, low_h + layer, float(z) + 0.5)

	if probe.is_blocked_at(mid, ph, pr):
		push_error("ramp mid should not be head-blocked during descent")
		failed = true
	else:
		print("OK ramp mid head clear on descent")

	if not probe.can_step_to(top, mid, ph, pr, max_step):
		push_error("should step from landing interior down ramp mid")
		failed = true
	else:
		print("OK step landing -> ramp mid")

	if not probe.can_step_to(mid, low, ph, pr, max_step):
		push_error("should step from ramp mid to low flat")
		failed = true
	else:
		print("OK step ramp mid -> low flat")

	_TerrainRamps.placement_chance = old_chance
	_TerrainRamps.invalidate_mesh_cache()

	if failed:
		quit(1)
	print("All ramp descent walk tests OK")
	quit(0)


func _init_maps(data: _ChunkData) -> void:
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