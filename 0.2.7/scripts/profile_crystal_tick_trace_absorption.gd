extends SceneTree
## Trace the first tick that includes ABSORPTION_READY (WorldState fan-out).


func _initialize() -> void:
	OS.set_environment("CRYSTALSTORM_CRYSTAL_TICK_TRACE", "1")
	if OS.get_environment("CRYSTALSTORM_BAKE_RADIUS").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	if OS.get_environment("CRYSTALSTORM_PERF_PRESET").is_empty():
		OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	call_deferred("_run")


func _run() -> void:
	print("=== ABSORPTION TICK TRACE ===")
	change_scene_to_file("res://scenes/main.tscn")
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
		quit(1)
		return

	crystal.expansion_enabled = true
	if "_stream_pause_frames" in crystal:
		crystal._stream_pause_frames = 0
	if "_expansion_soft_ticks_left" in crystal:
		crystal._expansion_soft_ticks_left = 0
	if "_perf_crystal_skip_frames" in crystal:
		crystal._perf_crystal_skip_frames = 0
	if "_perf_flow_budget_us" in crystal:
		crystal._perf_flow_budget_us = 0
	if "_simulation" in crystal and crystal._simulation:
		crystal._simulation.flow_budget_us = 0
	if "_sim" in crystal and crystal._sim:
		crystal._sim.flow_budget_us = 0
		# Seed crystal over a small area to force absorption progress quickly.
		for dx in range(-3, 4):
			for dz in range(-3, 4):
				var p := Vector2i(-10 + dx, 10 + dz)
				crystal._sim.set_depth(p, 0.8, 0, false)

	# Arm only after warm-up so first absorption-bearing tick is captured.
	# Manually complete one absorption via event path to measure fan-out cleanly.
	await process_frame
	await process_frame
	if crystal.has_method("begin_tick_trace_arm"):
		crystal.begin_tick_trace_arm()
	# Force arm active and inject critical absorption-ready as if sim emitted it.
	if crystal.has_method("_tick_trace_start"):
		crystal._tick_trace_start("forced_absorption_apply")
	var Events = load("res://crystal/crystal_sim_events.gd")
	var pos := Vector2i(-10, 10)
	var ev: Dictionary = Events.absorption_ready(pos, 0, {})
	# Also include a multi-cell FLOW_BATCH to show split fan-out.
	var changed: Array = []
	for i in 70:
		changed.append(Vector2i(-10 + (i % 10), 10 + int(i / 10)))
	var flow: Dictionary = Events.flow_batch(changed, changed.duplicate(), 5)
	var events: Array = [flow, ev, Events.stats(12.0, 49)]
	if crystal.has_method("_finish_tick_side_effects"):
		# Mark as sim events for trace
		if crystal._tick_trace_active:
			crystal._tick_trace["events_from_sim"] = events.size()
			for e in events:
				crystal._tick_trace_kind("events_by_kind", int(e.get("kind", 0)))
				if int(e.get("kind", 0)) == 3:
					crystal._tick_trace["flow_batch_changed_n"] = changed.size()
					crystal._tick_trace["flow_batch_mesh_dirty_n"] = changed.size()
					crystal._tick_trace["flow_batch_new_cells"] = 5
		crystal._dispatch_sim_events(events)
		crystal._drain_dispatch_queue_budgeted()
		# Drain remaining deferred units this frame for full count (still measurement of path).
		var guard := 0
		while crystal.get_dispatch_queue_depth() > 0 and guard < 50:
			crystal._drain_dispatch_queue_budgeted()
			guard += 1
		if crystal.has_method("_tick_trace_finish"):
			crystal._tick_trace_finish()

	var trace: Dictionary = crystal.get_tick_trace() if crystal.has_method("get_tick_trace") else {}
	print("ABSORPTION_TRACE ", JSON.stringify(trace, "\t"))
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-23417f42e77b/implementer"
	var path := scratch.path_join("crystal_tick_trace_absorption.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(trace, "\t"))
		f.close()
		print("WROTE ", path)
	print("=== ABSORPTION TICK TRACE END ===")
	quit(0)
