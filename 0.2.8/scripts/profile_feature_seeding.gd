extends SceneTree
## Multi-run feature_seeding phase breakdown (measure only).
## Usage:
##   CRYSTALSTORM_SCRATCH=/tmp/... CRYSTALSTORM_FS_RUNS=5 \
##   godot --headless -s scripts/profile_feature_seeding.gd

const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _StartupProfiler = preload("res://systems/startup_profiler.gd")

## Canonical report rows (order fixed; do not merge).
const REPORT_PHASES: PackedStringArray = [
	"fs/biome_initialization",
	"fs/bootstrap_perf_ready",
	"fs/bootstrap_visual_textures",
	"fs/world_resolve_and_policy",
	"fs/registry_reset",
	"fs/town_generation",
	"fs/town_site_search",
	"fs/town_ground_stamp",
	"fs/road_generation",
	"fs/resource_field_generation",
	"fs/await_frame_after_town",
	"fs/vegetation_placement",
	"fs/ruin_generation",
	"fs/await_frame_after_ruin",
	"fs/spawn_region_generation",
	"fs/spawn_animal_registry",
	"fs/spawn_chunk_stream_bind",
	"fs/cave_feature_generation",
	"fs/navigation_generation",
	"fs/crystal_initialization",
	"fs/spatial_index_creation",
	"fs/serialization",
	"fs/node_creation",
]


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_STARTUP_PROFILE", "1")
	if OS.get_environment("CRYSTALSTORM_PERF_PRESET").is_empty():
		OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_BAKE_ON_NEW", "0")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var runs: int = maxi(int(OS.get_environment("CRYSTALSTORM_FS_RUNS")), 1)
	if runs > 20:
		runs = 20
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-3c89103bbbb9/implementer"
	DirAccess.make_dir_recursive_absolute(scratch)

	# phase -> PackedInt64Array of per-run wall µs
	var series: Dictionary = {}
	for p in REPORT_PHASES:
		series[p] = PackedInt64Array()
	var parent_series := PackedInt64Array()
	var residual_series := PackedInt64Array()

	for r in runs:
		_StartupProfiler.begin_session()
		var packed: PackedScene = load(MAIN_SCENE) as PackedScene
		if packed == null:
			push_error("main missing")
			_ProbeExit.finish_tree(self, 1, "FEATURE_SEEDING_PROFILE FAILED")
			return
		var game: Node = packed.instantiate()
		root.add_child(game)
		var compose = game.get_node_or_null("CompositionRoot")
		var frames := 0
		while compose and not bool(compose.get("_boot_done")) and frames < 3600:
			await process_frame
			frames += 1
		for _i in 10:
			await process_frame

		var samples: Dictionary = _StartupProfiler._samples
		var parent_us: int = 0
		if samples.has("feature_seeding"):
			var arr: PackedInt64Array = samples["feature_seeding"]
			if arr.size() > 0:
				parent_us = int(arr[arr.size() - 1])
		parent_series.append(parent_us)

		var accounted: int = 0
		# Top-level exclusive phases (do not double-count town subphases / spawn subphases).
		var exclusive: PackedStringArray = [
			"fs/biome_initialization",
			"fs/bootstrap_perf_ready",
			"fs/bootstrap_visual_textures",
			"fs/world_resolve_and_policy",
			"fs/registry_reset",
			"fs/town_generation",
			"fs/await_frame_after_town",
			"fs/vegetation_placement",
			"fs/ruin_generation",
			"fs/await_frame_after_ruin",
			"fs/spawn_region_generation",
			"fs/cave_feature_generation",
			"fs/navigation_generation",
			"fs/crystal_initialization",
			"fs/spatial_index_creation",
			"fs/serialization",
			"fs/node_creation",
		]
		for p in REPORT_PHASES:
			var us: int = 0
			if samples.has(p):
				var a: PackedInt64Array = samples[p]
				if a.size() > 0:
					us = int(a[a.size() - 1])
			var bucket: PackedInt64Array = series[p]
			bucket.append(us)
			series[p] = bucket
		for p in exclusive:
			if series.has(p) and series[p].size() > 0:
				accounted += int(series[p][series[p].size() - 1])
		var residual: int = maxi(parent_us - accounted, 0)
		residual_series.append(residual)

		print(
			"FEATURE_SEEDING_RUN %d/%d parent_ms=%.2f residual_ms=%.2f"
			% [r + 1, runs, float(parent_us) / 1000.0, float(residual) / 1000.0]
		)

		# Tear down for next run
		if game.get_parent():
			game.get_parent().remove_child(game)
		game.free()
		_StartupProfiler.end_session()
		for _j in 5:
			await process_frame

	var report: Dictionary = _aggregate(series, parent_series, residual_series)
	var out_path := scratch.path_join("feature_seeding_profile.json")
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()
		print("WROTE %s" % out_path)
	_print_table(report)
	_ProbeExit.finish_tree(self, 0, "FEATURE_SEEDING_PROFILE_OK")


func _aggregate(series: Dictionary, parent_series: PackedInt64Array, residual_series: PackedInt64Array) -> Dictionary:
	var parent_stats: Dictionary = _StartupProfiler._stats(parent_series)
	var parent_avg: float = float(parent_stats.get("avg_us", 0.0))
	var phases: Array = []
	for p in REPORT_PHASES:
		var st: Dictionary = _StartupProfiler._stats(series.get(p, PackedInt64Array()))
		st["stage"] = p
		var avg: float = float(st.get("avg_us", 0.0))
		st["pct_feature_seeding"] = (avg / maxf(parent_avg, 1.0)) * 100.0
		phases.append(st)
	var res_st: Dictionary = _StartupProfiler._stats(residual_series)
	res_st["stage"] = "fs/remaining_unaccounted"
	res_st["pct_feature_seeding"] = (
		float(res_st.get("avg_us", 0.0)) / maxf(parent_avg, 1.0)
	) * 100.0
	phases.append(res_st)
	return {
		"runs": parent_series.size(),
		"preset": OS.get_environment("CRYSTALSTORM_PERF_PRESET"),
		"feature_seeding": parent_stats,
		"phases": phases,
	}


func _print_table(report: Dictionary) -> void:
	var parent: Dictionary = report.get("feature_seeding", {})
	print(
		"FEATURE_SEEDING parent n=%d avg_ms=%.2f p95_ms=%.2f worst_ms=%.2f"
		% [
			int(parent.get("n", 0)),
			float(parent.get("avg_us", 0.0)) / 1000.0,
			float(parent.get("p95_us", 0.0)) / 1000.0,
			float(parent.get("worst_us", 0)) / 1000.0,
		]
	)
	print("phase\tavg_ms\tp95_ms\tworst_ms\tpct_feature_seeding")
	for st in report.get("phases", []):
		print(
			"%s\t%.3f\t%.3f\t%.3f\t%.2f"
			% [
				str(st.get("stage", "")),
				float(st.get("avg_us", 0.0)) / 1000.0,
				float(st.get("p95_us", 0.0)) / 1000.0,
				float(st.get("worst_us", 0)) / 1000.0,
				float(st.get("pct_feature_seeding", 0.0)),
			]
		)
	print("FEATURE_SEEDING_PROFILE_OK")
