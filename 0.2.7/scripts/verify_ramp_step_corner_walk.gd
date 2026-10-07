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
	# Model A corner needs the inner plateau (both landings and the diagonal).
	for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		data.surface_map[cx + d.x][cz + d.y] = high_h
		data.tile_map[cx + d.x][cz + d.y] = _VoxelTypes.GRASSLAND

	var cm := _ChunkManager.new()
	cm.world = world
	cm.ramp_placement_chance = 100
	cm._build_mesh(data)

	var view := _ChunkView.new()
	view.chunk_data = data
	cm.chunks[Vector2i(0, 0)] = view

	var probe := _VoxelFloorProbe.new()
	probe.configure(world, cm, null)
	# Hint at the surface so a default of 0 does not sample the cave floor instead of the prism.
	probe.feet_height_hint = world.get_surface_height(float(cx) + 0.5, float(cz) + 0.5) + layer

	if not data.is_ramp_corner(cx, cz):
		push_error("L-step low cell must be a corner ramp")
		failed = true
	else:
		print("OK L-step corner ramp on low cell")

	# The prism owns the low cell. Landings that only step into that prism are not a second wedge.
	var outer := Vector3(float(cx) + 0.28, 0.0, float(cz) + 0.28)
	outer.y = probe.walkable_height_at(outer.x, outer.z)
	var inner := Vector3(float(cx) + 0.72, 0.0, float(cz) + 0.72)
	inner.y = probe.walkable_height_at(inner.x, inner.z)
	if inner.y < outer.y + layer * 0.25:
		push_error("corner prism must rise toward the landings, outer=%.2f inner=%.2f" % [outer.y, inner.y])
		failed = true
	elif not probe.can_step_to(outer, inner, ph, pr, max_step):
		push_error("should step up the corner prism")
		failed = true
	else:
		print("OK step up corner prism %.2f -> %.2f" % [outer.y, inner.y])

	var x_land := Vector3(float(cx + 1) + 0.5, 0.0, float(cz) + 0.35)
	x_land.y = probe.walkable_height_at(x_land.x, x_land.z)
	if not probe.can_step_to(inner, x_land, ph, pr, max_step):
		push_error("should step from prism onto +X landing")
		failed = true
	else:
		print("OK step prism -> +X landing")

	var z_land := Vector3(float(cx) + 0.35, 0.0, float(cz + 1) + 0.5)
	z_land.y = probe.walkable_height_at(z_land.x, z_land.z)
	if not probe.can_step_to(inner, z_land, ph, pr, max_step):
		push_error("should step from prism onto +Z landing")
		failed = true
	else:
		print("OK step prism -> +Z landing")

	var center_h: float = probe.walkable_height_at(float(cx) + 0.5, float(cz) + 0.5)
	var corner_feet: float = probe.sample_walkable_feet(inner.x, inner.z)
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