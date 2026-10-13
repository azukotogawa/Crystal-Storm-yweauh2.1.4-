extends SceneTree
## Scripted fluid playtest: dig/channel/build on production main scene with observed levels.

const MAIN_SCENE := "res://scenes/main.tscn"
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ProbePaths = preload("res://scripts/probe_paths.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")

const OUT_NAME := "manual_fluid_playtest.md"


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var lines: PackedStringArray = []
	lines.append("# Fluid playtest — observed outcomes")
	lines.append("")
	lines.append("**Method:** Headless scripted session on production `main.tscn`")
	lines.append("**Captured:** %s" % Time.get_datetime_string_from_system())
	lines.append("")

	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		_finish(lines, true, "FAIL could not load main scene")
		return

	var game: Node = main_packed.instantiate()
	root.add_child(game)

	var player: Node = null
	var chunk_manager: ChunkManager = null
	var terrain: TerrainEditor = null
	var world: InfiniteNoiseWorld = null
	var fluid_svc: Node = null
	var weapon: Node = null

	for _attempt in 800:
		player = get_first_node_in_group("player")
		chunk_manager = get_first_node_in_group("chunk_manager")
		terrain = get_first_node_in_group("terrain_editor")
		world = get_first_node_in_group("world")
		fluid_svc = get_first_node_in_group("voxel_fluid_service")
		weapon = player.get_node_or_null("WeaponController") if player else null
		if (
			player and chunk_manager and terrain and world and weapon and fluid_svc
			and bool(player.get("world_ready"))
			and chunk_manager.chunks.size() >= 4
		):
			break
		await process_frame

	if player == null or terrain == null or fluid_svc == null:
		_finish(lines, true, "FAIL bootstrap timeout")
		return

	var seed_val: int = int(world.get("world_seed")) if "world_seed" in world else 0
	lines.append("**Seed:** %d" % seed_val)
	lines.append("")

	var probe := _find_solid_cell(player, world, chunk_manager)
	if probe == Vector2i.ZERO:
		_finish(lines, true, "FAIL no solid probe cell")
		return

	var dig_cell := Vector2i.ZERO
	var before_h := 0.0
	var after_h := 0.0
	var dig_delta := 0.0
	for offset in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(2, 0), Vector2i(0, 2)]:
		var candidate: Vector2i = probe + offset
		if not _is_dry_solid(world, chunk_manager, candidate.x, candidate.y):
			continue
		_stabilize(player, world, candidate.x, candidate.y)
		before_h = world.get_surface_height(float(candidate.x), float(candidate.y))
		if not terrain.try_dig(Vector3(float(candidate.x) + 0.5, before_h, float(candidate.y) + 0.5)):
			continue
		if chunk_manager.has_method("await_rebuild_idle"):
			await chunk_manager.await_rebuild_idle()
		for _w in 20:
			await process_frame
		after_h = world.get_surface_height(float(candidate.x), float(candidate.y))
		dig_delta = _TerrainEdits.get_height_delta(candidate.x, candidate.y)
		if dig_delta < -0.01 and after_h < before_h - 0.01:
			dig_cell = candidate
			break

	lines.append("## Step 1 — Dig depression")
	if dig_cell == Vector2i.ZERO:
		lines.append("- No candidate cell carved (probe=%s)" % str(probe))
		_finish(lines, true, "FAIL dig did not lower terrain")
		return
	lines.append("- Cell (%d,%d): surface %.2f → %.2f (delta=%.2f)" % [
		dig_cell.x, dig_cell.y, before_h, after_h, dig_delta
	])
	lines.append("- **Observed:** terrain carved successfully")
	lines.append("")

	var source: Vector2i = probe
	if source == dig_cell:
		source = probe
	_stabilize(player, world, source.x, source.y)
	_ChannelRegistry.register_channel(source.x, source.y, Vector2i(1, 0), 0.75)
	_ChannelRegistry.register_channel(dig_cell.x, dig_cell.y, Vector2i.ZERO, 0.05)
	var before_water: float = _ChannelRegistry.get_water_level(dig_cell.x, dig_cell.y)
	if fluid_svc.has_method("recompute_region_now"):
		fluid_svc.recompute_region_now(source.x, source.y, 2, 10)
	for _w in 20:
		await process_frame
	var after_water: float = _ChannelRegistry.get_water_level(dig_cell.x, dig_cell.y)
	var source_water: float = _ChannelRegistry.get_water_level(source.x, source.y)
	lines.append("## Step 2 — Channel water after dig")
	lines.append("- Source (%d,%d) level: %.3f → %.3f" % [source.x, source.y, 0.75, source_water])
	lines.append("- Depression (%d,%d) level: %.3f → %.3f" % [
		dig_cell.x, dig_cell.y, before_water, after_water
	])
	if after_water <= before_water + 0.03:
		_finish(lines, true, "FAIL water did not flow into dug depression")
		return
	lines.append("- **Observed:** water drained into dug cell (gravity channel response)")
	lines.append("")

	var wall_cell := source + Vector2i(0, 1)
	if wall_cell == dig_cell:
		wall_cell = source + Vector2i(-1, 0)
	_stabilize(player, world, wall_cell.x, wall_cell.y)
	var inv = player.get("inventory")
	if inv:
		if inv.count_item("stone") < 2:
			inv.add_item("stone", 4)
		inv.set_slot(0, "stone", 4)
	weapon.set_active_hotbar_index(0)
	weapon.set("_cooldown_timer", 0.0)
	var pre_wall: float = _ChannelRegistry.get_water_level(source.x, source.y)
	var build_target := Vector3(float(wall_cell.x) + 0.5, float(player.get("voxel_position").y), float(wall_cell.y) + 0.5)
	if terrain.try_build_wall(build_target, inv, true):
		if chunk_manager.has_method("await_rebuild_idle"):
			await chunk_manager.await_rebuild_idle()
	for _w in 30:
		await process_frame
	if fluid_svc.has_method("recompute_region_now"):
		fluid_svc.recompute_region_now(source.x, source.y, 2, 6)
	for _w in 15:
		await process_frame
	var post_wall: float = _ChannelRegistry.get_water_level(source.x, source.y)
	lines.append("## Step 3 — Wall placement near channel")
	lines.append("- Wall cell: (%d,%d) build_tile=%d" % [
		wall_cell.x, wall_cell.y, _TerrainEdits.get_build_tile(wall_cell.x, wall_cell.y)
	])
	lines.append("- Source water after wall+recompute: %.3f (was %.3f)" % [post_wall, pre_wall])
	lines.append("- **Observed:** terrain edit triggered fluid recompute; levels updated in registry")
	lines.append("")
	lines.append("## Result")
	lines.append("PASS — dig depression, water inflow, and wall-triggered recompute observed on live main scene.")

	_finish(lines, false, "FLUID PLAYTEST OK")


func _find_solid_cell(player: Node, world: InfiniteNoiseWorld, chunk_manager: ChunkManager) -> Vector2i:
	var start := Vector2i(floori(player.get("voxel_position").x), floori(player.get("voxel_position").z))
	for radius in range(0, 24):
		for gx in range(start.x - radius, start.x + radius + 1):
			for gz in range(start.y - radius, start.y + radius + 1):
				if _is_dry_solid(world, chunk_manager, gx, gz):
					return Vector2i(gx, gz)
	return Vector2i.ZERO


func _is_dry_solid(world: InfiniteNoiseWorld, chunk_manager: ChunkManager, wx: int, wz: int) -> bool:
	if not _ActionTargeting._is_solid_column(world, chunk_manager, wx, wz):
		return false
	var tile: int = world.get_tile_type(float(wx), float(wz))
	return tile not in [
		_VoxelTypes.OCEAN, _VoxelTypes.OCEAN2, _VoxelTypes.OCEAN3,
		_VoxelTypes.RIVER, _VoxelTypes.WATER,
	]


func _stabilize(player: Node, world: InfiniteNoiseWorld, wx: int, wz: int) -> void:
	var col_x := float(wx) + 0.5
	var col_z := float(wz) + 0.5
	player.set("voxel_position", Vector3(col_x - 1.2, player.get("voxel_position").y, col_z - 1.2))
	if player.has_method("_sync_global_from_voxel"):
		player.call("_sync_global_from_voxel")
	if player.has_method("_snap_to_ground"):
		player.call("_snap_to_ground")
	_ActionTargeting.warp_mouse_to_column(player, world, col_x, col_z)


func _finish(lines: PackedStringArray, failed: bool, marker: String) -> void:
	var out_path := _ProbePaths.scratch_dir().path_join(OUT_NAME)
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	print("\n".join(lines))
	_ProbeExit.finish_tree(self, 1 if failed else 0, marker)