extends SceneTree
## Measure CrystalTerrainQuery / world / FeatureRegistry query cost + duplicates.
## Usage:
##   CRYSTALSTORM_TERRAIN_QUERY_MEASURE=1 CRYSTALSTORM_BAKE_RADIUS=2 \
##   godot --headless -s scripts/profile_terrain_queries.gd

const SAMPLE_FRAMES := 240


func _initialize() -> void:
	OS.set_environment("CRYSTALSTORM_TERRAIN_QUERY_MEASURE", "1")
	if OS.get_environment("CRYSTALSTORM_BAKE_RADIUS").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	if OS.get_environment("CRYSTALSTORM_PERF_PRESET").is_empty():
		OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	call_deferred("_run")


func _run() -> void:
	print("=== TERRAIN QUERY PROFILE ===")
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		push_error("scene failed %d" % err)
		quit(1)
		return
	await process_frame
	await process_frame

	var frames := 0
	var crystal = null
	var composition = null
	while frames < 1200:
		await process_frame
		frames += 1
		var root := current_scene
		if root == null:
			continue
		crystal = root.get_tree().get_first_node_in_group("crystal_manager")
		composition = root.get_tree().get_first_node_in_group("composition_root")
		if composition and int(composition.stage) >= 7 and crystal and bool(crystal.get("_initialized")):
			break

	# Force expansion for measurement window if gated.
	if crystal and "expansion_enabled" in crystal:
		crystal.expansion_enabled = true
	if crystal and "_stream_pause_frames" in crystal:
		crystal._stream_pause_frames = 0
	if crystal and "_expansion_soft_ticks_left" in crystal:
		crystal._expansion_soft_ticks_left = 0
	# Ensure sim can tick frequently for query statistics.
	if crystal and "_perf_sim_hz" in crystal:
		crystal._perf_sim_hz = 20.0
	if crystal and "_perf_crystal_skip_frames" in crystal:
		crystal._perf_crystal_skip_frames = 0

	var terrain = null
	if crystal and "_terrain_query" in crystal:
		terrain = crystal._terrain_query
	if terrain and terrain.has_method("reset_query_stats"):
		terrain.reset_query_stats()
	if terrain and terrain.has_method("set_query_measure_enabled"):
		terrain.set_query_measure_enabled(true)

	# Also reset world / feature registry counters if present.
	var world = current_scene.get_tree().get_first_node_in_group("world") if current_scene else null
	if world and world.has_method("reset_query_stats"):
		world.reset_query_stats()
	if world and world.has_method("set_query_measure_enabled"):
		world.set_query_measure_enabled(true)
	var fr = load("res://world/feature_registry.gd")
	if fr and fr.has_method("reset_query_stats"):
		fr.reset_query_stats()
	if fr and fr.has_method("set_query_measure_enabled"):
		fr.set_query_measure_enabled(true)

	for i in SAMPLE_FRAMES:
		await process_frame

	var report := {
		"sample_frames": SAMPLE_FRAMES,
		"crystal_cells": int(crystal.covered_cells) if crystal and "covered_cells" in crystal else -1,
	}
	if terrain and terrain.has_method("get_query_stats"):
		report["terrain_query"] = terrain.get_query_stats()
	if world and world.has_method("get_query_stats"):
		report["world"] = world.get_query_stats()
	if fr and fr.has_method("get_query_stats"):
		report["feature_registry"] = fr.get_query_stats()

	_print_report(report)
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-23417f42e77b/implementer"
	DirAccess.make_dir_recursive_absolute(scratch)
	var path := scratch.path_join("terrain_query_profile.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()
		print("WROTE ", path)
	print("=== TERRAIN QUERY PROFILE END ===")
	quit(0)


func _print_report(report: Dictionary) -> void:
	print("\n========== TERRAIN QUERY RANKED ==========")
	print("sample_frames=%s crystal_cells=%s" % [report.get("sample_frames"), report.get("crystal_cells")])
	var tq: Dictionary = report.get("terrain_query", {})
	if not tq.is_empty():
		print("\n--- CrystalTerrainQuery ---")
		_print_ops(tq.get("ops", {}))
		print("cache_hits height=%s tile=%s flow=%s" % [
			tq.get("height_hits", 0), tq.get("tile_hits", 0), tq.get("flow_hits", 0),
		])
		print("cache_misses height=%s tile=%s flow=%s" % [
			tq.get("height_misses", 0), tq.get("tile_misses", 0), tq.get("flow_misses", 0),
		])
		print("dup_same_frame height=%s tile=%s flow=%s" % [
			tq.get("height_dups", 0), tq.get("tile_dups", 0), tq.get("flow_dups", 0),
		])
		print("hit_rate height=%.1f%% tile=%.1f%% flow=%.1f%%" % [
			float(tq.get("height_hit_rate", 0.0)) * 100.0,
			float(tq.get("tile_hit_rate", 0.0)) * 100.0,
			float(tq.get("flow_hit_rate", 0.0)) * 100.0,
		])
		print("callers: ", tq.get("callers", {}))
	var w: Dictionary = report.get("world", {})
	if not w.is_empty():
		print("\n--- InfiniteNoiseWorld ---")
		_print_ops(w.get("ops", {}))
		print("surface_dups_frame=%s biome_dups_frame=%s tile_dups_frame=%s" % [
			w.get("surface_dups", 0), w.get("biome_dups", 0), w.get("tile_dups", 0),
		])
	var frs: Dictionary = report.get("feature_registry", {})
	if not frs.is_empty():
		print("\n--- FeatureRegistry ---")
		_print_ops(frs.get("ops", {}))
		print("ruin_centers_dups=%s cache_hits=%s" % [
			frs.get("ruin_centers_dups", 0), frs.get("ruin_centers_hits", 0),
		])
	print("========== END ==========\n")


func _print_ops(ops: Dictionary) -> void:
	var rows: Array = []
	for name in ops.keys():
		var o: Dictionary = ops[name]
		rows.append({
			"name": name,
			"total_us": int(o.get("total_us", 0)),
			"n": int(o.get("n", 0)),
			"max_us": int(o.get("max_us", 0)),
			"avg_us": float(o.get("total_us", 0)) / float(maxi(int(o.get("n", 0)), 1)),
		})
	rows.sort_custom(func(a, b): return int(a.total_us) > int(b.total_us))
	print("| rank | op | n | total_ms | avg_us | max_us |")
	var rank := 1
	for r in rows:
		print("| %4d | %s | %d | %.3f | %.2f | %d |" % [
			rank, r.name, r.n, float(r.total_us) / 1000.0, r.avg_us, r.max_us,
		])
		rank += 1
