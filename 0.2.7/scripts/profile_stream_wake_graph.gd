extends SceneTree
## Dependency graph + timings: chunk_ready → frame-end subsystem activation.
## Measure only.
##
## Usage:
##   CRYSTALSTORM_BAKE_RADIUS=2 godot --headless -s scripts/profile_stream_wake_graph.gd


func _initialize() -> void:
	if OS.get_environment("CRYSTALSTORM_BAKE_RADIUS").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	if OS.get_environment("CRYSTALSTORM_PERF_PRESET").is_empty():
		OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	call_deferred("_run")


func _run() -> void:
	print("=== STREAM WAKE DEPENDENCY PROFILE ===")
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		push_error("scene fail")
		quit(1)
		return
	await process_frame
	await process_frame

	var frames := 0
	var crystal = null
	var cm = null
	var player = null
	var world = null
	var em = null
	var feat = null
	var sq = null
	var living = null
	var hud = null
	var map_ui = null
	while frames < 1500:
		await process_frame
		frames += 1
		var root := current_scene
		if root == null:
			continue
		var tree := root.get_tree()
		crystal = tree.get_first_node_in_group("crystal_manager")
		cm = tree.get_first_node_in_group("chunk_manager")
		player = tree.get_first_node_in_group("player")
		world = tree.get_first_node_in_group("world")
		em = tree.get_first_node_in_group("entity_manager")
		feat = tree.get_first_node_in_group("feature_visual_layer")
		sq = tree.get_first_node_in_group("spatial_query_service")
		living = tree.get_first_node_in_group("living_world_director")
		hud = tree.get_first_node_in_group("game_overlay")
		map_ui = tree.get_first_node_in_group("topographical_map")
		var composition = tree.get_first_node_in_group("composition_root")
		if composition and int(composition.stage) >= 7 and crystal and bool(crystal.get("_initialized")) and cm:
			break

	if crystal == null or cm == null:
		push_error("missing systems")
		quit(1)
		return

	# Reset traces
	if crystal.has_method("set_stream_wake_trace"):
		crystal.set_stream_wake_trace(true)
	if em and em.has_method("reset_stream_wake_trace"):
		em.reset_stream_wake_trace()
	if feat and feat.has_method("reset_stream_wake_trace"):
		feat.reset_stream_wake_trace()
	if sq and sq.has_method("reset_stream_wake_trace"):
		sq.reset_stream_wake_trace()
	if world and world.has_method("reset_query_stats"):
		world.reset_query_stats()
		if world.has_method("set_query_measure_enabled"):
			world.set_query_measure_enabled(true)
	var tq = crystal.get("_terrain_query") if "_terrain_query" in crystal else null
	if tq and tq.has_method("reset_query_stats"):
		tq.reset_query_stats()
		tq.set_query_measure_enabled(true)
	if tq and "use_fast_terrain_height" in tq:
		print("[Wake] CrystalTerrainQuery.use_fast_terrain_height=", tq.use_fast_terrain_height)
		print("[Wake] height path: InfiniteNoiseWorld.get_surface_height (NOT ChunkData.surface_map)")
		print("[Wake] tile path: InfiniteNoiseWorld.get_tile_type (NOT ChunkData.tile_map)")

	# Frame-level aggregation around streaming
	var last_chunks := int(cm.chunks.size()) if "chunks" in cm else 0
	var ready_hook: Array = [0]  # boxed for lambda mutation
	if cm.has_signal("chunk_ready"):
		cm.chunk_ready.connect(func(_c, _d):
			ready_hook[0] = int(ready_hook[0]) + 1
		)

	# Teleport to force stream
	_teleport(player, world, cm, Vector2(160, 160))
	var window_frames := 120
	var sum_crystal_proc := 0
	var max_crystal_proc := 0
	var sum_sim_steps := 0
	var frames_with_new_chunks := 0
	for i in window_frames:
		await process_frame
		var nch := int(cm.chunks.size()) if "chunks" in cm else 0
		if nch != last_chunks:
			frames_with_new_chunks += 1
			last_chunks = nch
		var pu := int(crystal.get_last_process_us()) if crystal.has_method("get_last_process_us") else 0
		var steps := int(crystal.get_last_sim_steps()) if crystal.has_method("get_last_sim_steps") else 0
		sum_crystal_proc += pu
		max_crystal_proc = maxi(max_crystal_proc, pu)
		sum_sim_steps += steps

	var report := {
		"window_frames": window_frames,
		"frames_with_chunk_count_change": frames_with_new_chunks,
		"chunk_ready_signal_count": int(ready_hook[0]),
		"crystal_process_avg_ms": float(sum_crystal_proc) / float(window_frames) / 1000.0,
		"crystal_process_max_ms": float(max_crystal_proc) / 1000.0,
		"crystal_sim_steps_in_window": sum_sim_steps,
		"listeners": {
			"CrystalManager": crystal.get_stream_wake_trace() if crystal.has_method("get_stream_wake_trace") else {},
			"EntityManager": em.get_stream_wake_trace() if em and em.has_method("get_stream_wake_trace") else {},
			"FeatureVisualLayer": feat.get_stream_wake_trace() if feat and feat.has_method("get_stream_wake_trace") else {},
			"SpatialQueryService": sq.get_stream_wake_trace() if sq and sq.has_method("get_stream_wake_trace") else {},
		},
		"terrain_query": tq.get_query_stats() if tq and tq.has_method("get_query_stats") else {},
		"world_surface": world.get_query_stats() if world and world.has_method("get_query_stats") else {},
		"systems_not_on_chunk_ready": {
			"LivingWorldDirector": "always-on _process (biome poll + budgeted ruin scan); NO chunk_ready connect",
			"TopographicalMapBuilder": "on-demand UI job; NO chunk_ready connect",
			"GameOverlay/HUD": "polls biome on timer/UI; NO chunk_ready connect",
			"FeatureRegistry": "static storage; no process; mutated by stream veg install / gameplay, not a listener",
			"GameVisualRegistry": "chunk_ready full-refresh DISCONNECTED",
			"WorldVisuals": "chunk_ready full-refresh DISCONNECTED",
		},
		"crystal_sim_wake_model": {
			"primary_wake": "Node._process every frame once _initialized",
			"chunk_ready_effect": "presentation dirty mark + spawn marker visibility only; does NOT call CrystalSimulation.tick",
			"tick_gating": "expansion_enabled + boot stage + stream_pause + stream_pressure (pending load queue) can SKIP ticks during heavy stream",
			"loaded_chunks_filter": "is_cell_active uses chunk_manager.chunks — streaming changes which cells are simulated, not when _process runs",
			"terrain_source": "CrystalTerrainQuery → InfiniteNoiseWorld.get_surface_height/get_tile_type (+ session caches), not baked ChunkData.surface_map/tile_map",
		},
	}

	_print_report(report)
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-23417f42e77b/implementer"
	DirAccess.make_dir_recursive_absolute(scratch)
	var path := scratch.path_join("stream_wake_graph.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()
		print("WROTE ", path)
	print("=== STREAM WAKE DEPENDENCY PROFILE END ===")
	quit(0)


func _teleport(player, world, cm, off: Vector2) -> void:
	if player == null:
		return
	var base := Vector2.ZERO
	if cm and cm.has_method("get_player_chunk_coord"):
		var c: Vector2i = cm.get_player_chunk_coord()
		base = Vector2(float(c.x * 16 + 8), float(c.y * 16 + 8))
	var wx := base.x + off.x
	var wz := base.y + off.y
	var sy := 20.0
	if world and world.has_method("get_surface_height"):
		sy = float(world.get_surface_height(wx, wz))
	if "voxel_position" in player:
		player.voxel_position = Vector3(wx, sy + 2.0, wz)
		if player.has_method("_sync_global_from_voxel"):
			player._sync_global_from_voxel()


func _print_report(r: Dictionary) -> void:
	print("\n========== STREAM → FRAME DEPENDENCY GRAPH ==========")
	print("chunk_ready emissions in window: ", r.get("chunk_ready_signal_count"))
	print("crystal process avg/max ms: %.3f / %.3f  sim_steps=%s" % [
		float(r.get("crystal_process_avg_ms", 0)), float(r.get("crystal_process_max_ms", 0)),
		r.get("crystal_sim_steps_in_window"),
	])
	print("\n--- chunk_ready listeners (production connects) ---")
	var L: Dictionary = r.get("listeners", {})
	for name in L.keys():
		var d: Dictionary = L[name]
		print("%s: ready_n=%s ready_us=%s max_us=%s extra=%s" % [
			name,
			d.get("chunk_ready_n", d.get("chunk_loaded_n", "?")),
			d.get("chunk_ready_us", d.get("chunk_loaded_us", "?")),
			d.get("chunk_ready_max_us", d.get("chunk_loaded_max_us", "?")),
			d,
		])
	print("\n--- NOT on chunk_ready ---")
	var skip: Dictionary = r.get("systems_not_on_chunk_ready", {})
	for k in skip.keys():
		print("  %s: %s" % [k, skip[k]])
	print("\n--- crystal wake model ---")
	print(JSON.stringify(r.get("crystal_sim_wake_model", {}), "\t"))
	print("\n--- terrain query (window) ---")
	print(JSON.stringify(r.get("terrain_query", {}), "\t"))
	print("=====================================================\n")
