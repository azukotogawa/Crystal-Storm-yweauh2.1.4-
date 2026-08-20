extends SceneTree
## Trace exactly one complete crystal sim tick: events, WorldState.bump,
## SpatialQuery reindex, GameVisualRegistry refresh.
##
## Usage:
##   CRYSTALSTORM_CRYSTAL_TICK_TRACE=1 CRYSTALSTORM_BAKE_RADIUS=2 \
##   godot --headless -s scripts/profile_crystal_tick_trace.gd


func _initialize() -> void:
	OS.set_environment("CRYSTALSTORM_CRYSTAL_TICK_TRACE", "1")
	if OS.get_environment("CRYSTALSTORM_BAKE_RADIUS").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	if OS.get_environment("CRYSTALSTORM_PERF_PRESET").is_empty():
		OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	call_deferred("_run")


func _run() -> void:
	print("=== CRYSTAL TICK TRACE PROBE ===")
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		push_error("scene fail")
		quit(1)
		return
	await process_frame
	await process_frame

	var crystal = null
	var frames := 0
	while frames < 1500:
		await process_frame
		frames += 1
		var root := current_scene
		if root == null:
			continue
		crystal = root.get_tree().get_first_node_in_group("crystal_manager")
		var composition = root.get_tree().get_first_node_in_group("composition_root")
		if composition and int(composition.stage) >= 7 and crystal and bool(crystal.get("_initialized")):
			break

	if crystal == null:
		push_error("no crystal")
		quit(1)
		return

	# Force expansion so the first complete tick happens soon.
	crystal.expansion_enabled = true
	if crystal.has_method("begin_tick_trace_arm"):
		crystal.begin_tick_trace_arm()
	if "_stream_pause_frames" in crystal:
		crystal._stream_pause_frames = 0
	if "_expansion_soft_ticks_left" in crystal:
		crystal._expansion_soft_ticks_left = 0
	if "_perf_crystal_skip_frames" in crystal:
		crystal._perf_crystal_skip_frames = 0
	if "_perf_sim_hz" in crystal:
		crystal._perf_sim_hz = 30.0
	if "_perf_flow_budget_us" in crystal:
		crystal._perf_flow_budget_us = 0  # complete tick in one go for clean fan-out view
	if "_simulation" in crystal and crystal._simulation:
		crystal._simulation.flow_budget_us = 0
	if "_sim" in crystal and crystal._sim:
		crystal._sim.flow_budget_us = 0

	var wait := 0
	while wait < 600:
		await process_frame
		wait += 1
		if "_stream_pause_frames" in crystal:
			crystal._stream_pause_frames = 0
		if "_expansion_soft_ticks_left" in crystal:
			crystal._expansion_soft_ticks_left = 0
		if crystal.has_method("is_tick_trace_done") and crystal.is_tick_trace_done():
			break

	var trace: Dictionary = {}
	if crystal.has_method("get_tick_trace"):
		trace = crystal.get_tick_trace()

	# Kind labels
	var kind_names := {
		"1": "DEPTH_CHANGED",
		"2": "DEPTH_CLEARED",
		"3": "FLOW_BATCH",
		"4": "MESH_DIRTY",
		"5": "POWER_DELTA",
		"6": "STATS",
		"7": "ABSORPTION_READY",
		"8": "RUIN_ABSORPTION_READY",
	}
	var by_kind: Dictionary = trace.get("events_by_kind", {})
	var labeled := {}
	for k in by_kind.keys():
		labeled[kind_names.get(str(k), str(k))] = by_kind[k]

	print("\n--- TICK TRACE SUMMARY ---")
	print("done=%s total_us=%s cells %s→%s" % [
		str(crystal.is_tick_trace_done()) if crystal.has_method("is_tick_trace_done") else "?",
		trace.get("total_us", -1),
		trace.get("cells_before", -1),
		trace.get("cells_after", -1),
	])
	print("sim_events=%s by_kind=%s" % [trace.get("events_from_sim", 0), labeled])
	print("critical_applies=%s deferred_enqueued=%s flow_batch_splits=%s" % [
		trace.get("critical_applies", 0),
		trace.get("deferred_enqueued", 0),
		trace.get("flow_batch_splits", 0),
	])
	print("apply_one_sim_event=%s presentation_apply=%s drain_same_frame=%s queue_left=%s" % [
		trace.get("apply_one_sim_event", 0),
		trace.get("presentation_apply_events", 0),
		trace.get("drain_applies_same_frame", 0),
		trace.get("dispatch_queue_remaining", 0),
	])
	print("WorldState.bump=%s  SpatialQuery._on_world_state_changed=%s reindex_chunks_sum=%s" % [
		trace.get("worldstate_bumps", 0),
		trace.get("spatial_ws_changed", 0),
		trace.get("spatial_reindex_chunks", 0),
	])
	print("GVR refresh=%s" % [trace.get("gvr_refresh", {})])
	print("absorption clears: tile=%s feature=%s rebuild_chunk=%s" % [
		trace.get("clear_tile_calls", 0),
		trace.get("clear_feature_calls", 0),
		trace.get("rebuild_chunk_calls", 0),
	])
	print("phases_us=%s" % [trace.get("phases_us", {})])
	print("FLOW_BATCH payload changed=%s mesh_dirty=%s new_cells=%s" % [
		trace.get("flow_batch_changed_n", 0),
		trace.get("flow_batch_mesh_dirty_n", 0),
		trace.get("flow_batch_new_cells", 0),
	])

	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-23417f42e77b/implementer"
	DirAccess.make_dir_recursive_absolute(scratch)
	var path := scratch.path_join("crystal_tick_trace.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(trace, "\t"))
		f.close()
		print("WROTE ", path)

	# Structural call-graph note for absorption fan-out (code path)
	print("\n--- FAN-OUT RULE (code) ---")
	print("ABSORPTION_READY is critical → immediate _apply_one_sim_event → _complete_absorption")
	print("  → FeatureRegistry.clear_tile_override → WorldState.bump (1)")
	print("  → FeatureRegistry.clear_feature → WorldState.bump (1)")
	print("  → each bump emits changed → SpatialQueryService._on_world_state_changed")
	print("  → reindexes ALL loaded chunks (not once per tick)")
	print("FLOW_BATCH is deferred, split into ≤32-cell units → presentation per unit, no WorldState.bump")
	print("GameVisualRegistry.refresh_* is NOT on the crystal tick path (only explicit refresh_all)")

	print("=== CRYSTAL TICK TRACE PROBE END ===")
	quit(0 if (crystal.has_method("is_tick_trace_done") and crystal.is_tick_trace_done()) else 1)
