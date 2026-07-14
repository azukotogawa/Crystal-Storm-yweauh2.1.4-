extends SceneTree
## Regression: VoxelFloorProbe can step up L-shaped step corners (two perpendicular landings).


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

	var cx := 6
	var cz := 6
	var low_h := 10.0
	var high_h := low_h + layer
	data.surface_map[cx][cz] = low_h
	data.tile_map[cx][cz] = _VoxelTypes.GRASSLAND
	data.surface_map[cx + 1][cz] = high_h
	data.tile_map[cx + 1][cz] = _VoxelTypes.GRASSLAND
	data.surface_map[cx][cz + 1] = high_h
	data.tile_map[cx][cz + 1] = _VoxelTypes.GRASSLAND

	var cm := _ChunkManager.new()
	cm.world = world
	cm.ramp_placement_chance = 100
	cm._build_mesh(data)

	var view := _ChunkView.new()
	view.chunk_data = data
	cm.chunks[Vector2i(0, 0)] = view

	var probe := _VoxelFloorProbe.new()
	probe.configure(world, cm, null)

	var low_start := Vector3(float(cx) + 0.5, low_h + layer, float(cz) + 0.5)
	var x_mid := Vector3(float(cx + 1) + 0.25, 0.0, float(cz) + 0.5)
	x_mid.y = probe.walkable_height_at(x_mid.x, x_mid.z)
	var x_top := Vector3(float(cx + 1) + 0.75, 0.0, float(cz) + 0.5)
	x_top.y = probe.walkable_height_at(x_top.x, x_top.z)
	var z_mid := Vector3(float(cx) + 0.5, 0.0, float(cz + 1) + 0.25)
	z_mid.y = probe.walkable_height_at(z_mid.x, z_mid.z)
	var z_top := Vector3(float(cx) + 0.5, 0.0, float(cz + 1) + 0.75)
	z_top.y = probe.walkable_height_at(z_top.x, z_top.z)

	if not data.has_ramp(cx + 1, cz):
		push_error("expected +X landing ramp")
		failed = true
	elif not data.has_ramp(cx, cz + 1):
		push_error("expected +Z landing ramp")
		failed = true
	else:
		print("OK L-step emits +X and +Z landing ramps")

	if not probe.can_step_to(low_start, x_mid, ph, pr, max_step):
		push_error("should step from low flat onto +X ramp mid")
		failed = true
	else:
		print("OK step low -> +X ramp mid")

	if not probe.can_step_to(x_mid, x_top, ph, pr, max_step):
		push_error("should step along +X ramp to landing interior")
		failed = true
	else:
		print("OK step +X ramp mid -> interior")

	if not probe.can_step_to(low_start, z_mid, ph, pr, max_step):
		push_error("should step from low flat onto +Z ramp mid")
		failed = true
	else:
		print("OK step low -> +Z ramp mid")

	if not probe.can_step_to(z_mid, z_top, ph, pr, max_step):
		push_error("should step along +Z ramp to landing interior")
		failed = true
	else:
		print("OK step +Z ramp mid -> interior")

	var corner_xz := Vector2(float(cx) + 0.5, float(cz) + 0.5)
	var center_h: float = probe.walkable_height_at(corner_xz.x, corner_xz.y)
	var corner_feet: float = probe.sample_walkable_feet(corner_xz.x, corner_xz.y)
	if corner_feet < center_h - layer * 0.25:
		push_error("step-corner feet %.2f below center walkable %.2f" % [corner_feet, center_h])
		failed = true
	else:
		print("OK step-corner low cell feet=%.2f center=%.2f" % [corner_feet, center_h])

	_TerrainRamps.placement_chance = old_chance
	_TerrainRamps.invalidate_mesh_cache()

	if failed:
		print("Ramp step-corner walk tests FAILED")
		quit(1)
		return
	print("All ramp step-corner walk tests OK")
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