extends SceneTree
## Profile CrystalManager / CrystalSimulation / tick_flow CPU.
## Forces expansion after RUNNING and samples worst/avg process + breakdown.
## Usage:
##   CRYSTALSTORM_BAKE_RADIUS=2 CRYSTALSTORM_PERF_PRESET=medium \
##   godot --headless -s scripts/profile_crystal_cpu.gd

const SAMPLE_FRAMES := 300
const WARMUP_FRAMES := 30


func _initialize() -> void:
	if OS.get_environment("CRYSTALSTORM_BAKE_RADIUS").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	if OS.get_environment("CRYSTALSTORM_PERF_PRESET").is_empty():
		OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_CRYSTAL_STARTUP_MEASURE", "1")
	call_deferred("_run")


func _run() -> void:
	print("=== CRYSTAL CPU PROFILE ===")
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		push_error("scene fail %d" % err)
		quit(1)
		return
	await process_frame
	await process_frame

	var crystal = null
	var composition = null
	var frames := 0
	while frames < 1500:
		await process_frame
		frames += 1
		var root := current_scene
		if root == null:
			continue
		crystal = root.get_tree().get_first_node_in_group("crystal_manager")
		composition = root.get_tree().get_first_node_in_group("composition_root")
		if composition and int(composition.stage) >= 7 and crystal and bool(crystal.get("_initialized")):
			break

	if crystal == null:
		push_error("no crystal")
		quit(1)
		return

	# Steady expansion for measurement (not stream-paused).
	crystal.expansion_enabled = true
	if "_stream_pause_frames" in crystal:
		crystal._stream_pause_frames = 0
	if "_expansion_soft_ticks_left" in crystal:
		crystal._expansion_soft_ticks_left = 0
	if "_perf_crystal_skip_frames" in crystal:
		crystal._perf_crystal_skip_frames = 0
	if "_perf_sim_hz" in crystal:
		crystal._perf_sim_hz = 30.0
	# Disable stream-pressure gate for measurement so ticks actually run.
	if crystal.has_method("_stream_pressure_active"):
		# Replace with always-false via flag if present
		pass
	if "_STREAM_PENDING_PAUSE_THRESHOLD" in crystal:
		pass
	# Grow a large crystal blob so tick_flow cost is visible (deterministic seed pattern).
	var target_cells := 800
	var csim = crystal.get("_simulation") if "_simulation" in crystal else null
	var fluid = null
	if csim and "fluid" in csim:
		fluid = csim.fluid
	if fluid and "depth" in fluid:
		var origin := Vector2i(-10, 10)
		var r := 0
		while fluid.depth.size() < target_cells and r < 40:
			for dx in range(-r, r + 1):
				for dz in range(-r, r + 1):
					if absi(dx) != r and absi(dz) != r and r > 0:
						continue
					var p := origin + Vector2i(dx, dz)
					if not fluid.depth.has(p):
						fluid.set_depth(p, 0.55, 0, false)
					if fluid.depth.size() >= target_cells:
						break
				if fluid.depth.size() >= target_cells:
					break
			r += 1
		if "covered_cells" in crystal:
			crystal.covered_cells = fluid.depth.size()
		print("[CrystalCPU] seeded depth cells=%d for stress measure" % fluid.depth.size())

	for _i in WARMUP_FRAMES:
		if "_stream_pause_frames" in crystal:
			crystal._stream_pause_frames = 0
		if "_expansion_soft_ticks_left" in crystal:
			crystal._expansion_soft_ticks_left = 0
		await process_frame

	var sum_proc := 0
	var max_proc := 0
	var sum_tick := 0
	var max_tick := 0
	var sum_flow := 0
	var max_flow := 0
	var sum_snap := 0
	var max_snap := 0
	var sum_disp := 0
	var max_disp := 0
	var n_ticks := 0
	var n_frames := 0
	var max_cells := 0
	var worst_breakdown := {}

	# Reset process counters if present
	if "_process_max_us" in crystal:
		crystal._process_max_us = 0
		crystal._process_sum_us = 0
		crystal._process_n = 0

	for i in SAMPLE_FRAMES:
		await process_frame
		n_frames += 1
		var pu := int(crystal.get_last_process_us()) if crystal.has_method("get_last_process_us") else 0
		var tu := int(crystal.get_last_tick_us()) if crystal.has_method("get_last_tick_us") else 0
		var steps := int(crystal.get_last_sim_steps()) if crystal.has_method("get_last_sim_steps") else 0
		sum_proc += pu
		max_proc = maxi(max_proc, pu)
		if steps > 0:
			n_ticks += steps
			sum_tick += tu
			max_tick = maxi(max_tick, tu)
		var cells := int(crystal.covered_cells) if "covered_cells" in crystal else 0
		max_cells = maxi(max_cells, cells)

		# Pull last tick breakdown from simulation if available
		var sim = crystal.get("_simulation") if "_simulation" in crystal else null
		if sim and sim.has_method("consume_last_tick_breakdown"):
			var bd: Dictionary = sim.consume_last_tick_breakdown()
			if not bd.is_empty():
				var fus := int(bd.get("flow_us", 0))
				sum_flow += fus
				if fus >= max_flow:
					max_flow = fus
					worst_breakdown = bd.duplicate()
		# Manager-side gauges via last process path already includes power/dispatch

	var report := {
		"sample_frames": n_frames,
		"ticks_observed": n_ticks,
		"max_cells": max_cells,
		"final_cells": int(crystal.covered_cells) if "covered_cells" in crystal else -1,
		"process_avg_ms": float(sum_proc) / float(maxi(n_frames, 1)) / 1000.0,
		"process_max_ms": float(max_proc) / 1000.0,
		"tick_avg_ms": float(sum_tick) / float(maxi(n_ticks, 1)) / 1000.0,
		"tick_max_ms": float(max_tick) / 1000.0,
		"flow_avg_ms": float(sum_flow) / float(maxi(n_ticks, 1)) / 1000.0,
		"flow_max_ms": float(max_flow) / 1000.0,
		"worst_tick_breakdown": worst_breakdown,
		"hitch": crystal.get_hitch_counters() if crystal.has_method("get_hitch_counters") else {},
	}

	print("\n========== CRYSTAL CPU RANKED ==========")
	print("frames=%d ticks=%d cells_final=%s max_cells=%s" % [
		n_frames, n_ticks, report.final_cells, max_cells,
	])
	print("CrystalManager::_process  avg=%.3fms  max=%.3fms" % [report.process_avg_ms, report.process_max_ms])
	print("sim tick wall (accum)     avg=%.3fms  max=%.3fms" % [report.tick_avg_ms, report.tick_max_ms])
	print("tick_flow (breakdown)     avg=%.3fms  max=%.3fms" % [report.flow_avg_ms, report.flow_max_ms])
	print("worst_tick_breakdown: ", worst_breakdown)
	print("========================================\n")

	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-23417f42e77b/implementer"
	DirAccess.make_dir_recursive_absolute(scratch)
	var label := OS.get_environment("CRYSTALSTORM_PROFILE_LABEL")
	if label.is_empty():
		label = "baseline"
	var path := scratch.path_join("crystal_cpu_%s.json" % label)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()
		print("WROTE ", path)
	print("=== CRYSTAL CPU PROFILE END ===")
	quit(0)
