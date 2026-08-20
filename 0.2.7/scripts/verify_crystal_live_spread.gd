extends SceneTree
## Integration: crystal fluid spread on the shipped world seed (12349) with real terrain tiles.

const MAIN_SCENE := "res://scenes/main.tscn"
const _CrystalManager = preload("res://crystal/crystal_manager.gd")
const _CrystalFluidSim = preload("res://crystal/crystal_fluid_sim.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var failed := false

	if not _test_origin_relocated_off_river():
		failed = true

	if not _test_sim_spread_on_live_world():
		failed = true

	if not await _test_main_scene_spread():
		failed = true

	if failed:
		_ProbeExit.finish_tree(self, 1, "Crystal live spread tests FAILED")
	else:
		_ProbeExit.finish_tree(self, 0, "All crystal live spread tests OK")


func _test_origin_relocated_off_river() -> bool:
	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 12349
	var cm := _CrystalManager.new()
	cm.world = world
	var origin: Vector2i = cm.pick_origin_spawn_cell()
	var center_tile: int = world.get_tile_type(0.0, 0.0)
	if center_tile != _VoxelTypes.RIVER:
		push_error("expected seed 12349 center to be RIVER for regression, got %d" % center_tile)
		return false
	if origin == Vector2i.ZERO:
		push_error("origin spawn must relocate off river at (0,0)")
		return false
	if _CrystalTypes.is_water_tile(world.get_tile_type(float(origin.x), float(origin.y))):
		push_error("relocated origin %s is still water" % origin)
		return false
	print("OK origin relocated (0,0) river → %s tile=%d" % [origin, world.get_tile_type(float(origin.x), float(origin.y))])
	return true


func _test_sim_spread_on_live_world() -> bool:
	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 12349
	var cm := _CrystalManager.new()
	cm.world = world
	var origin: Vector2i = cm.pick_origin_spawn_cell()

	var terrain := _CrystalTerrainQuery.new()
	terrain.world = world
	var cfg := _CrystalSimConfig.create_default()
	var sim := _CrystalFluidSim.new(cfg, terrain)
	sim.max_new_cells_per_tick = 0
	sim.empty_cell_inflow_cap = 0.12
	sim.set_depth(origin, cfg.initial_spawn_depth, 0, false)

	var neighbor_depths_before := _neighbor_depth_sum(sim, origin)
	for _i in 24:
		terrain.begin_sim_tick(_i + 1)
		sim.tick_flow(0.3)

	var cells: int = sim.cell_count()
	var neighbor_depths_after := _neighbor_depth_sum(sim, origin)
	if cells <= 1:
		push_error("live-world sim stuck at %d cell(s) origin=%s" % [cells, origin])
		return false
	if neighbor_depths_after <= neighbor_depths_before:
		push_error("neighbors gained no depth before=%.3f after=%.3f" % [neighbor_depths_before, neighbor_depths_after])
		return false
	print(
		"OK live-world sim spread cells=%d neighbors %.3f→%.3f origin=%s"
		% [cells, neighbor_depths_before, neighbor_depths_after, origin]
	)
	return true


func _test_main_scene_spread() -> bool:
	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		push_error("could not load main scene")
		return false

	var game: Node = main_packed.instantiate()
	root.add_child(game)

	var crystal: CrystalManager = null
	var player: Node = null
	for _attempt in 1200:
		crystal = get_first_node_in_group("crystal_manager") as CrystalManager
		player = get_first_node_in_group("player")
		if (
			crystal != null and crystal._initialized
			and player != null and bool(player.get("world_ready"))
		):
			break
		await process_frame

	if crystal == null or not crystal._initialized:
		push_error("crystal_manager failed to initialize in main scene")
		return false
	if player == null or not bool(player.get("world_ready")):
		push_error("player failed to reach world_ready in main scene")
		return false

	var spawns: Array = crystal.get_active_spawns()
	if spawns.is_empty():
		push_error("no active spawns in main scene")
		return false
	var origin_pos: Vector2i = spawns[0].world_pos
	if _CrystalTypes.is_water_tile(crystal._tile_at(origin_pos)):
		push_error("main scene origin %s still on water tile" % origin_pos)
		return false

	var cells_start: int = crystal.covered_cells
	for _w in 480:
		await process_frame
	var cells_end: int = crystal.covered_cells

	if cells_end <= cells_start:
		push_error("main scene crystal did not spread start=%d end=%d origin=%s" % [cells_start, cells_end, origin_pos])
		return false

	var neighbor_sum := 0.0
	for dir in _CrystalTypes.NEIGHBOR_DIRS:
		var n: Vector2i = origin_pos + dir
		neighbor_sum += crystal.get_depth_at(n.x, n.y)
	if neighbor_sum < 0.04:
		push_error("main scene neighbors have no crystal depth at origin=%s" % origin_pos)
		return false

	if player.has_method("get_voxel_position"):
		# Early-survival spawns ~28–40 columns from origin; warp for proximity observation only.
		var observe := Vector3(float(origin_pos.x) + 4.5, 8.0, float(origin_pos.y) - 3.5)
		if "voxel_position" in player:
			player.set("voxel_position", observe)
		if player.has_method("_sync_global_from_voxel"):
			player.call("_sync_global_from_voxel")
		if player.has_method("_snap_to_ground"):
			player.call("_snap_to_ground")
		var pcol: Vector3 = player.get_voxel_position()
		var dist: float = Vector2(pcol.x, pcol.z).distance_to(Vector2(float(origin_pos.x) + 0.5, float(origin_pos.y) + 0.5))
		if dist > 14.0:
			push_error("player observe warp failed dist=%.1f origin=%s" % [dist, origin_pos])
			return false
		print(
			"OK main scene spread %d→%d cells origin=%s player_dist=%.1f neighbor_depth=%.3f"
			% [cells_start, cells_end, origin_pos, dist, neighbor_sum]
		)
	else:
		print(
			"OK main scene spread %d→%d cells origin=%s neighbor_depth=%.3f"
			% [cells_start, cells_end, origin_pos, neighbor_sum]
		)
	return true


func _neighbor_depth_sum(sim: _CrystalFluidSim, origin: Vector2i) -> float:
	var total := 0.0
	for dir in _CrystalTypes.NEIGHBOR_DIRS:
		var n: Vector2i = origin + dir
		total += sim.get_depth_at(n.x, n.y)
	return total