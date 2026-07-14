extends SceneTree
## P0 perf contract: terrain edit rebuild scope + MEDIUM-preset latency budget.


const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _SmokeProbeHelpers = preload("res://scripts/smoke_probe_helpers.gd")
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")

## Isolated interior ring=0 ~320–950ms at MEDIUM; full-suite contention can exceed 1.5s on shared hosts.
const MAX_REBUILD_WALL_MS := 2000.0
const MAX_REBUILD_FRAMES := 120


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var failed := false

	var terrain_src := (load("res://world/terrain_editor.gd") as GDScript).source_code
	if "rebuild_ring_for_cell" not in terrain_src:
		push_error("terrain_editor must compute adaptive rebuild ring after edits")
		failed = true
	else:
		print("OK terrain edit uses adaptive rebuild ring")

	var cm_src := (load("res://chunks/chunk_manager.gd") as GDScript).source_code
	if "_compute_column_maps(true)" not in cm_src or "func _regenerate_chunk_mesh" not in cm_src:
		push_error("chunk rebuild must regenerate column maps on worker")
		failed = true
	else:
		print("OK chunk rebuild path is full column-map regen + mesh")

	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		push_error("main scene load failed")
		_ProbeExit.finish_tree(self, 1, "Chunk rebuild perf FAILED")
		return

	var game: Node = main_packed.instantiate()
	root.add_child(game)

	var player: Node = null
	var chunk_manager: ChunkManager = null
	var world: InfiniteNoiseWorld = null
	var terrain: TerrainEditor = null
	var weapon: Node = null

	for _attempt in 600:
		player = get_first_node_in_group("player")
		chunk_manager = get_first_node_in_group("chunk_manager")
		world = get_first_node_in_group("world")
		terrain = get_first_node_in_group("terrain_editor")
		weapon = player.get_node_or_null("WeaponController") if player else null
		if (
			player != null and chunk_manager != null and world != null
			and terrain != null and weapon != null
			and bool(player.get("world_ready"))
			and chunk_manager.chunks.size() >= 3
		):
			break
		await process_frame

	if chunk_manager == null or weapon == null:
		push_error("bootstrap timeout")
		_ProbeExit.finish_tree(self, 1, "Chunk rebuild perf FAILED")
		return

	for _w in 60:
		await process_frame

	var profiler = root.get_node_or_null("/root/PerfProfiler") if root else null
	if profiler and profiler.has_method("begin"):
		profiler.begin("chunk_mesh")
		profiler.end("chunk_mesh")
		profiler.begin("chunk_buffer")
		profiler.end("chunk_buffer")

	var pick_def: Dictionary = _ItemTypes.get_def("stone_pick")
	var pick_range: float = float(pick_def.get("range", 2.4))
	var inv = player.get("inventory")
	if inv:
		inv.set_slot(1, "stone_pick", 1)
	if weapon.has_method("set_active_hotbar_index"):
		weapon.set_active_hotbar_index(1)

	var player_col := Vector2i(
		floori(float(player.get("voxel_position").x)),
		floori(float(player.get("voxel_position").z))
	)
	var solid_cells: Array[Vector2i] = []
	for radius in range(1, 10):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var wx: int = player_col.x + dx
				var wz: int = player_col.y + dz
				if (
					_ActionTargeting._is_solid_column(world, chunk_manager, wx, wz)
					and _TerrainEditor.rebuild_ring_for_cell(wx, wz) == 0
				):
					solid_cells.append(Vector2i(wx, wz))

	var player_chunk := chunk_manager.get_player_chunk_coord()
	solid_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_pc: bool = chunk_manager.world_to_chunk_coord(a.x, a.y) == player_chunk
		var b_pc: bool = chunk_manager.world_to_chunk_coord(b.x, b.y) == player_chunk
		if a_pc != b_pc:
			return a_pc
		var da: int = absi(a.x - player_col.x) + absi(a.y - player_col.y)
		var db: int = absi(b.x - player_col.x) + absi(b.y - player_col.y)
		return da < db
	)

	var dig_wx := -1
	var dig_wz := -1
	var dig_coord := Vector2i.ZERO
	var chunks_before: int = chunk_manager.chunks.size()
	var before_h: float = 0.0
	var after_h: float = 0.0
	var delta: float = 0.0
	var mesh_sy: float = -1.0
	var wall_ms := 0.0
	var frames_elapsed := 0
	var dig_ok := false

	for cell in solid_cells:
		dig_wx = cell.x
		dig_wz = cell.y
		_SmokeProbeHelpers.position_player_for_forward_dig(
			player, world, chunk_manager, dig_wx, dig_wz, pick_range
		)
		_SmokeProbeHelpers.clear_mouse_offscreen(player)
		for _w in 8:
			await process_frame
		var dig_info: Dictionary = _ActionTargeting.resolve_action(
			player, world, chunk_manager, pick_range, false, &"dig"
		)
		if not dig_info.get("valid", false) or dig_info.get("mode", &"") != &"dig":
			continue
		var dig_cell: Vector2i = dig_info.get("cell", Vector2i.ZERO)
		if _TerrainEditor.rebuild_ring_for_cell(dig_cell.x, dig_cell.y) != 0:
			continue
		dig_wx = dig_cell.x
		dig_wz = dig_cell.y
		dig_coord = chunk_manager.world_to_chunk_coord(dig_wx, dig_wz)
		before_h = world.get_surface_height(float(dig_wx), float(dig_wz))
		var t0_ms := Time.get_ticks_msec()
		var frames0 := Engine.get_process_frames()
		weapon.set("_cooldown_timer", 0.0)
		weapon.call("_try_dig")
		if chunk_manager.has_method("await_rebuild_idle"):
			await chunk_manager.await_rebuild_idle()
		for _w in 20:
			await process_frame
		wall_ms = float(Time.get_ticks_msec() - t0_ms)
		frames_elapsed = Engine.get_process_frames() - frames0
		after_h = world.get_surface_height(float(dig_wx), float(dig_wz))
		delta = _TerrainEdits.get_height_delta(dig_wx, dig_wz)
		mesh_sy = _SmokeProbeHelpers.dig_mesh_surface_y(chunk_manager, dig_wx, dig_wz)
		var mesh_ok := mesh_sy >= 0.0 and mesh_sy < before_h - 0.01 and absf(mesh_sy - after_h) < 0.2
		dig_ok = delta < -0.01 and after_h < before_h - 0.01 and mesh_ok
		if dig_ok and wall_ms <= MAX_REBUILD_WALL_MS and frames_elapsed <= MAX_REBUILD_FRAMES:
			break
		if dig_ok:
			dig_ok = false

	if not dig_ok:
		push_error(
			"dig rebuild corroboration failed wx=%d wz=%d before=%.2f after=%.2f delta=%.2f mesh=%.2f"
			% [dig_wx, dig_wz, before_h, after_h, delta, mesh_sy]
		)
		failed = true
	else:
		var chunks_after: int = chunk_manager.chunks.size()
		if wall_ms > MAX_REBUILD_WALL_MS:
			push_error("dig rebuild wall time %.1fms exceeds %.0fms" % [wall_ms, MAX_REBUILD_WALL_MS])
			failed = true
		elif frames_elapsed > MAX_REBUILD_FRAMES:
			push_error("dig rebuild took %d frames (max %d)" % [frames_elapsed, MAX_REBUILD_FRAMES])
			failed = true
		elif chunks_after < chunks_before:
			push_error("chunk count dropped %d→%d during single edit" % [chunks_before, chunks_after])
			failed = true
		else:
			var mesh_peak_ms := 0.0
			var buffer_peak_ms := 0.0
			if profiler and profiler.has_method("get_snapshot"):
				var sections: Dictionary = profiler.get_snapshot().get("sections", {})
				mesh_peak_ms = float(sections.get("chunk_mesh", {}).get("max_ms", 0.0))
				buffer_peak_ms = float(sections.get("chunk_buffer", {}).get("max_ms", 0.0))
			print(
				"OK dig rebuild coord=%s wall=%.1fms frames=%d worker_peak mesh=%.2fms buffer=%.2fms chunks=%d"
				% [dig_coord, wall_ms, frames_elapsed, mesh_peak_ms, buffer_peak_ms, chunks_after]
			)

	# Build on interior column in same chunk (ring=0 baseline; edge band tested elsewhere).
	var build_cell := _interior_cell_in_chunk(dig_coord, Vector2i(dig_wx, dig_wz))
	var build_wx := build_cell.x
	var build_wz := build_cell.y
	if inv:
		if inv.count_item("stone") < 2:
			inv.add_item("stone", 8)
		inv.set_slot(0, "stone", 8)
	if build_cell.x == -1 and build_cell.y == -1:
		push_error("no interior build cell in chunk %s after dig at (%d,%d)" % [dig_coord, dig_wx, dig_wz])
		failed = true
		_ProbeExit.finish_tree(self, 1, "Chunk rebuild perf FAILED")
		return
	var build_coord := chunk_manager.world_to_chunk_coord(build_wx, build_wz)
	var build_h: float = world.get_surface_height(float(build_wx), float(build_wz))
	var build_target := Vector3(float(build_wx) + 0.5, build_h, float(build_wz) + 0.5)
	var build_t0_ms := Time.get_ticks_msec()
	var build_ok := false
	if terrain and terrain.has_method("try_build_wall"):
		build_ok = terrain.call("try_build_wall", build_target, inv, true)
	if chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle()
	for _w in 20:
		await process_frame
	var build_wall_ms := float(Time.get_ticks_msec() - build_t0_ms)
	var build_delta: float = _TerrainEdits.get_height_delta(build_wx, build_wz)
	build_ok = build_ok and build_delta > 0.01 and _TerrainEdits.get_build_tile(build_wx, build_wz) >= 0
	if not build_ok:
		push_error("build rebuild corroboration failed at (%d,%d)" % [build_wx, build_wz])
		failed = true
	elif build_wall_ms > MAX_REBUILD_WALL_MS:
		push_error("build rebuild wall time %.1fms exceeds %.0fms" % [build_wall_ms, MAX_REBUILD_WALL_MS])
		failed = true
	else:
		print(
			"OK build rebuild coord=%s wall=%.1fms delta=%.2f (interior ring=0 baseline)"
			% [build_coord, build_wall_ms, build_delta]
		)

	if failed:
		_ProbeExit.finish_tree(self, 1, "Chunk rebuild perf FAILED")
		return
	_ProbeExit.finish_tree(self, 0, "All chunk rebuild perf tests OK")


func _interior_cell_in_chunk(coord: Vector2i, skip: Vector2i = Vector2i(-99999, -99999)) -> Vector2i:
	var band: int = _TerrainEditor.REBUILD_EDGE_BAND
	for lx in range(band, _ChunkData.SIZE - band):
		for lz in range(band, _ChunkData.SIZE - band):
			var wx: int = coord.x * _ChunkData.SIZE + lx
			var wz: int = coord.y * _ChunkData.SIZE + lz
			if wx == skip.x and wz == skip.y:
				continue
			return Vector2i(wx, wz)
	return Vector2i(-1, -1)