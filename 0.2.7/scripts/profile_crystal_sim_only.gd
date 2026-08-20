extends SceneTree
## Crystal simulation-only profile (measure, no optimize).
## Counts active cells, terrain queries, neighbor evals, flow transfers, chunk crossings.
## Windows: early post-boot (startup) + stressed field (gameplay-like).
##
## Usage:
##   CRYSTALSTORM_CRYSTAL_SIM_PROFILE=1 CRYSTALSTORM_BAKE_RADIUS=2 \
##   godot --headless -s scripts/profile_crystal_sim_only.gd

const STARTUP_FRAMES := 180
const GAMEPLAY_FRAMES := 240


func _initialize() -> void:
	OS.set_environment("CRYSTALSTORM_CRYSTAL_SIM_PROFILE", "1")
	OS.set_environment("CRYSTALSTORM_CRYSTAL_STARTUP_MEASURE", "1")
	if OS.get_environment("CRYSTALSTORM_BAKE_RADIUS").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	if OS.get_environment("CRYSTALSTORM_PERF_PRESET").is_empty():
		OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	call_deferred("_run")


func _run() -> void:
	print("=== CRYSTAL SIM-ONLY PROFILE ===")
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

	_force_sim_running(crystal)

	var fluid = _get_fluid(crystal)
	var tq = crystal.get("_terrain_query") if "_terrain_query" in crystal else null
	if fluid and fluid.has_method("set_sim_profile_enabled"):
		fluid.set_sim_profile_enabled(true)
		fluid.reset_sim_profile()
	if tq and tq.has_method("set_query_measure_enabled"):
		tq.set_query_measure_enabled(true)
		tq.reset_query_stats()
	# Unbounded flow for pure algorithmic cost (measure only; not a production change).
	if fluid:
		fluid.flow_budget_us = 0
	if "_simulation" in crystal and crystal._simulation:
		crystal._simulation.flow_budget_us = 0
	if "_perf_flow_budget_us" in crystal:
		crystal._perf_flow_budget_us = 0

	# --- Window A: startup/early natural spread ---
	var proc_a: Dictionary = await _sample_process(crystal, STARTUP_FRAMES)
	var fluid_a: Dictionary = {}
	if fluid and fluid.has_method("get_sim_profile"):
		fluid_a = fluid.get_sim_profile()
	var tq_a: Dictionary = {}
	if tq and tq.has_method("get_query_stats"):
		tq_a = tq.get_query_stats()
	var cells_a := int(crystal.covered_cells) if "covered_cells" in crystal else -1

	# --- Window B: stressed gameplay-like field ---
	if fluid and fluid.has_method("reset_sim_profile"):
		fluid.reset_sim_profile()
	if tq and tq.has_method("reset_query_stats"):
		tq.reset_query_stats()
	_seed_blob(fluid, 600)
	if "covered_cells" in crystal and fluid:
		crystal.covered_cells = fluid.depth.size()
	print("[SimProfile] seeded stress cells=", fluid.depth.size() if fluid else -1)

	_force_sim_running(crystal)
	if fluid:
		fluid.flow_budget_us = 0
	if "_simulation" in crystal and crystal._simulation:
		crystal._simulation.flow_budget_us = 0
	if "_perf_flow_budget_us" in crystal:
		crystal._perf_flow_budget_us = 0
	var proc_b: Dictionary = await _sample_process(crystal, GAMEPLAY_FRAMES)
	var fluid_b: Dictionary = {}
	if fluid and fluid.has_method("get_sim_profile"):
		fluid_b = fluid.get_sim_profile()
	var tq_b: Dictionary = {}
	if tq and tq.has_method("get_query_stats"):
		tq_b = tq.get_query_stats()
	var cells_b := int(crystal.covered_cells) if "covered_cells" in crystal else -1

	var report := {
		"startup": {
			"frames": STARTUP_FRAMES,
			"cells_end": cells_a,
			"process": proc_a,
			"fluid": fluid_a,
			"terrain_query_cache": tq_a,
		},
		"gameplay_stress": {
			"frames": GAMEPLAY_FRAMES,
			"cells_end": cells_b,
			"process": proc_b,
			"fluid": fluid_b,
			"terrain_query_cache": tq_b,
		},
	}
	_print_window("STARTUP (early natural)", report.startup)
	_print_window("GAMEPLAY (seeded stress)", report.gameplay_stress)
	_print_complexity()

	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-23417f42e77b/implementer"
	DirAccess.make_dir_recursive_absolute(scratch)
	var path := scratch.path_join("crystal_sim_only_profile.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()
		print("WROTE ", path)
	print("=== CRYSTAL SIM-ONLY PROFILE END ===")
	quit(0)


func _force_sim_running(crystal) -> void:
	crystal.expansion_enabled = true
	if "_stream_pause_frames" in crystal:
		crystal._stream_pause_frames = 0
	if "_expansion_soft_ticks_left" in crystal:
		crystal._expansion_soft_ticks_left = 0
	if "_perf_crystal_skip_frames" in crystal:
		crystal._perf_crystal_skip_frames = 0
	if "_perf_sim_hz" in crystal:
		crystal._perf_sim_hz = 20.0
	if "_sim_tick_pending" in crystal:
		crystal._sim_tick_pending = false
	if "_STREAM_PENDING_PAUSE_THRESHOLD" in crystal:
		# raise so pressure gate rarely trips during measure
		pass


func _get_fluid(crystal):
	if crystal == null:
		return null
	if "_sim" in crystal and crystal._sim:
		return crystal._sim
	var sim = crystal.get("_simulation") if "_simulation" in crystal else null
	if sim and "fluid" in sim:
		return sim.fluid
	return null


func _seed_blob(fluid, target: int) -> void:
	if fluid == null or not ("depth" in fluid):
		return
	var origin := Vector2i(-10, 10)
	var r := 0
	while fluid.depth.size() < target and r < 35:
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r and r > 0:
					continue
				var p := origin + Vector2i(dx, dz)
				if not fluid.depth.has(p):
					fluid.set_depth(p, 0.55, 0, false)
				if fluid.depth.size() >= target:
					return
		r += 1


func _sample_process(crystal, n: int) -> Dictionary:
	var sum_us := 0
	var max_us := 0
	var sum_tick := 0
	var max_tick := 0
	var steps := 0
	var max_cells := 0
	for i in n:
		await process_frame
		_force_sim_running(crystal)
		var pu := int(crystal.get_last_process_us()) if crystal.has_method("get_last_process_us") else 0
		var tu := int(crystal.get_last_tick_us()) if crystal.has_method("get_last_tick_us") else 0
		var st := int(crystal.get_last_sim_steps()) if crystal.has_method("get_last_sim_steps") else 0
		sum_us += pu
		max_us = maxi(max_us, pu)
		if st > 0:
			steps += st
			sum_tick += tu
			max_tick = maxi(max_tick, tu)
		if "covered_cells" in crystal:
			max_cells = maxi(max_cells, int(crystal.covered_cells))
	return {
		"frames": n,
		"process_avg_ms": float(sum_us) / float(maxi(n, 1)) / 1000.0,
		"process_max_ms": float(max_us) / 1000.0,
		"tick_avg_ms": float(sum_tick) / float(maxi(steps, 1)) / 1000.0,
		"tick_max_ms": float(max_tick) / 1000.0,
		"sim_steps": steps,
		"max_cells": max_cells,
	}


func _print_window(title: String, w: Dictionary) -> void:
	print("\n========== %s ==========" % title)
	var p: Dictionary = w.get("process", {})
	print("process avg=%.3fms max=%.3fms  tick avg=%.3fms max=%.3fms  steps=%s cells_end=%s max_cells=%s" % [
		float(p.get("process_avg_ms", 0)), float(p.get("process_max_ms", 0)),
		float(p.get("tick_avg_ms", 0)), float(p.get("tick_max_ms", 0)),
		p.get("sim_steps", 0), w.get("cells_end", -1), p.get("max_cells", -1),
	])
	var f: Dictionary = w.get("fluid", {})
	if f.is_empty():
		print("(no fluid profile)")
		return
	print("depth_cells avg=%.1f  active avg=%.1f  selected avg=%.1f  ticks=%s flow_calls=%s" % [
		float(f.get("avg_depth_cells", 0)), float(f.get("avg_active_cells", 0)),
		float(f.get("avg_selected_cells", 0)), f.get("ticks_completed", 0), f.get("flow_calls", 0),
	])
	print("counts: cells_processed=%s neighbor_evals=%s cliff_checks=%s conductivity=%s transfers=%s" % [
		f.get("cells_processed", 0), f.get("neighbor_evals", 0), f.get("cliff_checks", 0),
		f.get("conductivity_calls", 0), f.get("flow_transfers", 0),
	])
	print("terrain_queries height=%s tile=%s total=%s  chunk_crossings=%s frontier_classifies=%s" % [
		f.get("terrain_height_queries", 0), f.get("terrain_tile_queries", 0),
		f.get("terrain_queries_total", 0), f.get("chunk_crossings", 0), f.get("frontier_classifies", 0),
	])
	var per: Dictionary = f.get("per_selected_cell", {})
	print("per selected cell: neighbors=%.2f terrain_q=%.2f conductivity=%.2f transfers=%.2f" % [
		float(per.get("neighbor_evals", 0)), float(per.get("terrain_queries", 0)),
		float(per.get("conductivity", 0)), float(per.get("transfers", 0)),
	])
	print("phase times (ranked):")
	for ph in f.get("phases", []):
		print("  %-28s total=%.2fms max=%.2fms" % [
			ph.get("phase", "?"), float(ph.get("total_ms", 0)), float(ph.get("max_us", 0)) / 1000.0,
		])
	var tq: Dictionary = w.get("terrain_query_cache", {})
	if not tq.is_empty():
		print("CrystalTerrainQuery cache: height hit=%.0f%% tile hit=%.0f%% flow hit=%.0f%%" % [
			float(tq.get("height_hit_rate", 0)) * 100.0,
			float(tq.get("tile_hit_rate", 0)) * 100.0,
			float(tq.get("flow_hit_rate", 0)) * 100.0,
		])


func _print_complexity() -> void:
	print("\n========== ALGORITHMIC COMPLEXITY (per logical tick_flow) ==========")
	print("| phase | complexity | notes |")
	print("| scan_active_cells | O(D) | D = depth dictionary size |")
	print("| select_flow_cells | O(A) | A = active cells; each may _has_empty_neighbor O(4) |")
	print("| process_selected_cells | O(S · K) | S = selected (≤ cap); K ≈ 4–8 neighbor passes |")
	print("|   per neighbor | O(1) + terrain | cliff: 2× height; tile; height; conductivity |")
	print("|   conductivity | O(1)+features | flow_factor_at ×2 + channel mult |")
	print("| apply_flow_deltas | O(Δ) | Δ = keys with nonzero transfer; + sort pending_new |")
	print("| dominant cost | O(S · terrain) | repeated get_terrain_height/get_tile inside neighbor loops |")
	print("======================================================================\n")
