extends SceneTree
## Contract: PerfProfiler snapshot/report API exposes all OBJECTIVE perf sections.


const _PerfProfiler = preload("res://systems/perf_profiler.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _PerformanceQualityConfig = preload("res://config/performance_quality_config.gd")


const REQUIRED_SECTIONS: Dictionary = {
	"frame": ["fps", "frame_ms", "budget_ms", "avg_ms", "p95_ms"],
	"chunks": ["visible", "generated_per_sec", "rebuilt_per_sec", "mesh_build_ms", "column_ms", "upload_ms"],
	"streaming": ["schedule_ms", "queue_depth", "mesh_queue_depth", "inflight"],
	"crystal": ["update_ms", "presentation_ms", "cells_updated", "dirty_cells", "frontier_size"],
	"entities": ["update_ms", "navigation_ms", "combat_ms", "ai_count"],
	"render": ["draw_calls", "multimesh_count", "visible_instances"],
	"world": ["terrain_queries", "terrain_edits", "dirty_regions"],
	"ui": ["update_ms"],
	"memory": ["current_mb", "peak_mb"],
	"workers": ["worker_ms", "active", "queue_depth", "avg_job_ms", "longest_job_ms"],
}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false

	var scr: GDScript = load("res://systems/perf_profiler.gd") as GDScript
	if scr == null:
		push_error("FAIL load perf_profiler.gd")
		quit(1)
		return
	print("OK load perf_profiler.gd")

	var profiler: Node = root.get_node_or_null("/root/PerfProfiler")
	if profiler == null:
		push_error("PerfProfiler autoload missing")
		quit(1)
		return

	profiler.begin("crystal_sim")
	profiler.end("crystal_sim")
	profiler.set_gauge("chunks_visible", 4.0)
	profiler.set_gauge("crystal_new_cells", 3.0)
	profiler.inc_rate("chunks_generated", 2)
	profiler.inc_frame("terrain_queries", 5)
	await process_frame
	await process_frame

	if not profiler.has_method("get_runtime_report"):
		push_error("missing get_runtime_report")
		failed = true
	elif not profiler.has_method("format_runtime_report"):
		push_error("missing format_runtime_report")
		failed = true
	else:
		var report: Dictionary = profiler.get_runtime_report()
		for section in REQUIRED_SECTIONS.keys():
			if not report.has(section):
				push_error("report missing section %s" % section)
				failed = true
				continue
			var fields: Array = REQUIRED_SECTIONS[section]
			var block: Dictionary = report[section]
			for field in fields:
				if not block.has(field):
					push_error("report.%s missing field %s" % [section, field])
					failed = true
				elif typeof(block[field]) not in [TYPE_INT, TYPE_FLOAT]:
					push_error("report.%s.%s not numeric" % [section, field])
					failed = true
		if not failed:
			print("OK runtime report sections")

		var formatted: String = profiler.format_runtime_report()
		for header in ["FRAME", "CHUNKS", "STREAMING", "CRYSTAL", "ENTITIES", "RENDER", "WORLD", "MEMORY", "WORKERS", "UI"]:
			if header not in formatted:
				push_error("formatted report missing header %s" % header)
				failed = true
		for label in [
			"FPS:", "Frame Time (ms):", "Chunks Visible:", "Crystal Update Time:",
			"Entity Update Time:", "Draw Calls:", "Terrain Query Count:",
			"Current (MB):", "Worker Total (ms):", "Schedule (ms):",
		]:
			if label not in formatted:
				push_error("formatted report missing label %s" % label)
				failed = true
		if not failed:
			print("OK formatted runtime report headers")

		# Bottleneck ranking API — worker stages must not dominate main hot list alone
		if profiler.has_method("get_bottlenecks"):
			if profiler.has_method("record_worker_stage"):
				profiler.record_worker_stage("chunk_mesh", 2500)
			else:
				profiler.record_us("chunk_mesh", 2500)
			profiler.record_us("crystal_sim", 800)
			profiler.record_us("player_physics", 500)
			await process_frame
			var bots: Array = profiler.get_bottlenecks(5)
			if bots.is_empty():
				push_error("get_bottlenecks empty after timed sections")
				failed = true
			else:
				print("OK bottlenecks[0]=%s %.2fms" % [bots[0].get("name"), float(bots[0].get("ms", 0.0))])
			# Main untracked accounting: worker stage must not inflate main tracked
			if profiler.has_method("get_main_untracked_ms") and profiler.has_method("get_main_tracked_ms"):
				var main_t: float = profiler.get_main_tracked_ms()
				# crystal_sim 0.8 + player 0.5 = 1.3ms; worker mesh excluded
				if main_t > 2.0:
					push_error("main tracked too high with worker stage (got %.2f)" % main_t)
					failed = true
				else:
					print("OK main_tracked=%.2f excludes worker stages" % main_t)
		else:
			push_error("missing get_bottlenecks")
			failed = true

		if profiler.has_method("begin_func") and profiler.has_method("get_hot_functions"):
			profiler.begin_func("ChunkManager::_on_chunk_ready")
			profiler.end_func("ChunkManager::_on_chunk_ready")
			profiler.record_func("CrystalSimulation::tick", 1200)
			await process_frame
			var hots: Array = profiler.get_hot_functions(5)
			if hots.is_empty():
				push_error("get_hot_functions empty")
				failed = true
			else:
				print("OK hot_functions[0]=%s" % str(hots[0].get("name")))
			var report2: Dictionary = profiler.get_runtime_report()
			if not report2.has("hot_functions"):
				push_error("report missing hot_functions")
				failed = true
			else:
				print("OK report.hot_functions present")
		else:
			push_error("missing function hotspot API")
			failed = true

	var cfg := _PerformanceQualityConfig.create_default()
	if int(cfg.debug_update_every) < 4:
		push_error("debug_update_every should stay throttled")
		failed = true
	else:
		print("OK overlay refresh throttle cfg=%d" % int(cfg.debug_update_every))

	profiler.record_us("entity_physics", 800)
	profiler.record_us("entity_navigation", 400)
	await process_frame
	var entity_report: Dictionary = profiler.get_runtime_report()
	if float(entity_report.entities.update_ms) < 0.5:
		push_error(
			"entity_physics snapshot lost after process (got %.3f ms)"
			% float(entity_report.entities.update_ms)
		)
		failed = true
	elif float(entity_report.entities.navigation_ms) < 0.2:
		push_error(
			"entity_navigation snapshot lost after process (got %.3f ms)"
			% float(entity_report.entities.navigation_ms)
		)
		failed = true
	else:
		print(
			"OK physics-phase timings survive process snapshot entity=%.2f nav=%.2f"
			% [float(entity_report.entities.update_ms), float(entity_report.entities.navigation_ms)]
		)

	var tq := _CrystalTerrainQuery.new()
	tq.get_terrain_height(Vector2i(1, 2))
	tq.get_tile(Vector2i(3, 4))
	await process_frame
	var snap: Dictionary = profiler.get_snapshot()
	var terrain_last: int = int(snap.get("frame_counters", {}).get("terrain_queries", 0))
	if terrain_last <= 0:
		push_error("terrain query instrumentation did not increment")
		failed = true
	else:
		print("OK terrain query counter=%d" % terrain_last)

	if failed:
		print("Runtime profiler tests FAILED")
		quit(1)
		return
	print("All runtime profiler tests OK")
	quit(0)