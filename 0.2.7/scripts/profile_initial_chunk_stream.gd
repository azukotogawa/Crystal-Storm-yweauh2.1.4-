extends SceneTree
## Profile initial_chunk_stream only. Writes stream_phase_profile.json + startup summary.
## Usage:
##   CRYSTALSTORM_STARTUP_PROFILE=1 CRYSTALSTORM_STREAM_PHASE_PROFILE=1 \
##   CRYSTALSTORM_SCRATCH=/tmp/... godot --headless -s scripts/profile_initial_chunk_stream.gd

const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_STARTUP_PROFILE", "1")
	OS.set_environment("CRYSTALSTORM_STREAM_PHASE_PROFILE", "1")
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_BAKE_ON_NEW", "0")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	if OS.get_environment("CRYSTALSTORM_SCRATCH").is_empty():
		OS.set_environment("CRYSTALSTORM_SCRATCH", "/tmp/grok-goal-3c89103bbbb9/implementer")
	call_deferred("_run")


func _run() -> void:
	var n_runs := int(OS.get_environment("CRYSTALSTORM_ICS_RUNS"))
	if n_runs <= 0:
		n_runs = 3
	var runs: Array = []
	for i in n_runs:
		print("=== ICS PROFILE RUN %d/%d ===" % [i + 1, n_runs])
		var packed: PackedScene = load(MAIN_SCENE) as PackedScene
		if packed == null:
			push_error("main missing")
			_ProbeExit.finish_tree(self, 1, "ICS_PROFILE FAILED")
			return
		var game: Node = packed.instantiate()
		root.add_child(game)
		var compose = game.get_node_or_null("CompositionRoot")
		var frames := 0
		while compose and not bool(compose.get("_boot_done")) and frames < 3600:
			await process_frame
			frames += 1
		var SP = load("res://systems/startup_profiler.gd")
		var SPP = load("res://systems/stream_phase_profiler.gd")
		var startup: Dictionary = SP.report() if SP else {}
		var stream: Dictionary = SPP.report() if SPP else {}
		# Extract initial_chunk_stream from startup stages
		var ics_ms := 0.0
		for st in startup.get("stages", []):
			if str(st.get("stage", "")) == "initial_chunk_stream":
				ics_ms = float(st.get("avg_us", 0.0)) / 1000.0
		runs.append({
			"startup_wall_ms": float(startup.get("wall_ms", 0.0)),
			"ics_ms": ics_ms,
			"stream_window_ms": float(stream.get("window_ms", 0.0)),
			"stream": stream,
			"startup": startup,
		})
		game.queue_free()
		await process_frame
		await process_frame
	# Aggregate
	var ics_vals: Array = []
	var stage_sums: Dictionary = {}
	for r in runs:
		ics_vals.append(float(r.get("ics_ms", 0.0)))
		var stages: Array = r.get("stream", {}).get("stages", [])
		for st in stages:
			var name: String = str(st.get("stage", ""))
			if not stage_sums.has(name):
				stage_sums[name] = []
			(stage_sums[name] as Array).append(float(st.get("total_us", 0)) / 1000.0)
	print("=== ICS AGGREGATE n=%d ===" % n_runs)
	var ics_avg := 0.0
	var ics_worst := 0.0
	for v in ics_vals:
		ics_avg += float(v)
		if float(v) > ics_worst:
			ics_worst = float(v)
	if ics_vals.size() > 0:
		ics_avg /= float(ics_vals.size())
	print("initial_chunk_stream avg_ms=%.2f worst_ms=%.2f" % [ics_avg, ics_worst])
	print("stage\tavg_ms\tworst_ms\tn_runs")
	var ranked: Array = []
	for name in stage_sums.keys():
		var arr: Array = stage_sums[name]
		var s := 0.0
		var w := 0.0
		for v in arr:
			s += float(v)
			if float(v) > w:
				w = float(v)
		var avg := s / float(arr.size())
		ranked.append({"stage": name, "avg_ms": avg, "worst_ms": w})
	ranked.sort_custom(func(a, b): return float(a.avg_ms) > float(b.avg_ms))
	for st in ranked:
		var pct := (float(st.avg_ms) / maxf(ics_avg, 0.001)) * 100.0
		print("%s\t%.3f\t%.3f\t%.1f%%" % [st.stage, st.avg_ms, st.worst_ms, pct])
	var dominant: String = ranked[0].stage if ranked.size() > 0 else ""
	print("LARGEST_CONSUMER %s avg_ms=%.3f" % [dominant, ranked[0].avg_ms if ranked.size() > 0 else 0.0])
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	var out_path := scratch.path_join("ics_phase_aggregate.json")
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"n": n_runs,
			"ics_avg_ms": ics_avg,
			"ics_worst_ms": ics_worst,
			"ranked": ranked,
			"dominant": dominant,
			"runs": runs,
		}, "\t"))
		f.close()
		print("WROTE %s" % out_path)
	_ProbeExit.finish_tree(self, 0, "ICS_PROFILE_OK")
