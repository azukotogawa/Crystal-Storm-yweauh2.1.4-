extends SceneTree
## Regression: floor probe honors live terrain edits; built walls block or step honestly.


const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkView = preload("res://chunks/chunk_view.gd")
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

	_TerrainEdits.reset()

	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	var data := _ChunkData.new(Vector2i(0, 0), world)
	data.capture_worker_snapshot()
	_init_maps(data)

	var base_h := 10.0
	var wx := 8
	var wz := 8
	data.surface_map[wx][wz] = base_h
	data.tile_map[wx][wz] = _VoxelTypes.GRASSLAND

	var cm := _ChunkManager.new()
	cm.world = world
	var view := _ChunkView.new()
	view.chunk_data = data
	cm.chunks[Vector2i(0, 0)] = view

	var probe := _VoxelFloorProbe.new()
	probe.configure(world, cm, null)

	var flat_feet: float = base_h + layer
	var beside := Vector3(float(wx) - 0.5, flat_feet, float(wz) + 0.5)
	var into_wall := Vector3(float(wx) + 0.5, flat_feet, float(wz) + 0.5)

	if not probe.can_step_to(beside, into_wall, ph, pr, max_step):
		push_error("flat approach into adjacent open cell should pass")
		failed = true
	else:
		print("OK flat walk on open terrain")

	var open_pos := Vector3(float(wx) + 2.5, flat_feet, float(wz) + 0.5)
	probe.feet_height_hint = flat_feet
	if probe.is_blocked_at(open_pos, ph, pr):
		push_error("open flat grass must not head-block player")
		failed = true
	else:
		print("OK open flat ground not blocked")
	var lateral_target := Vector3(open_pos.x + 1.0, flat_feet, open_pos.z)
	if not probe.can_step_to(open_pos, lateral_target, ph, pr, max_step):
		push_error("open flat lateral step should pass")
		failed = true
	else:
		print("OK open flat lateral step")

	probe.feet_height_hint = flat_feet
	var pre_build_walk: float = probe.walkable_height_at(float(wx) + 0.5, float(wz) + 0.5)

	if not _TerrainEdits.build_wall(wx, wz, _VoxelTypes.STONE):
		push_error("build_wall failed")
		failed = true

	var wall_feet: float = probe.walkable_height_at(float(wx) + 0.5, float(wz) + 0.5)
	if not is_equal_approx(wall_feet - pre_build_walk, layer):
		push_error(
			"live build must raise walkable by one layer got delta=%.2f"
			% (wall_feet - pre_build_walk)
		)
		failed = true
	else:
		print("OK live terrain edit raises walkable feet=%.2f" % wall_feet)

	if not probe.can_step_to(beside, into_wall, ph, pr, max_step):
		push_error("should step onto 1-layer built wall from adjacent lower cell")
		failed = true
	else:
		print("OK step onto 1-layer built wall")

	var on_wall := Vector3(float(wx) + 0.5, wall_feet, float(wz) + 0.5)
	if probe.is_blocked_at(on_wall, ph, pr):
		push_error("standing on built wall top should not be head-blocked")
		failed = true
	else:
		print("OK head clearance on wall top")

	_TerrainEdits.build_wall(wx, wz, _VoxelTypes.STONE)
	# Approach from true walkable ground beside the column (not a synthetic Y).
	var ground_beside := Vector3(float(wx) - 0.5, 0.0, float(wz) + 0.5)
	ground_beside.y = probe.sample_walkable_feet(ground_beside.x, ground_beside.z)
	var into_from_ground := Vector3(float(wx) + 0.5, ground_beside.y, float(wz) + 0.5)
	if probe.can_step_to(ground_beside, into_from_ground, ph, pr, max_step):
		push_error("2-layer wall should block entry at natural feet height")
		failed = true
	else:
		print("OK stacked wall blocks at natural feet")

	var probe_src := (load("res://player/voxel_floor_probe.gd") as GDScript).source_code
	if "live_delta - snap_delta" not in probe_src:
		push_error("voxel_floor_probe must apply live terrain edits over chunk snapshot")
		failed = true
	else:
		print("OK probe applies live terrain edits")

	var player_src := (load("res://player/player.gd") as GDScript).source_code
	if "_try_move_delta" not in player_src:
		push_error("player.gd must use combined move probe (_try_move_delta)")
		failed = true
	else:
		print("OK player uses combined move probe")

	_TerrainEdits.reset()

	if failed:
		print("Player collision tests FAILED")
		quit(1)
		return
	print("All player collision tests OK")
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
			data.surface_map[x][z] = 10.0
			data.tile_map[x][z] = _VoxelTypes.GRASSLAND