extends SceneTree
## Main scene: profiler-backed values become non-zero during healthy runtime.


const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _EntityBrainRegistry = preload("res://entities/entity_brain_registry.gd")


const REQUIRED_SECTIONS: Dictionary = {
	"frame": ["fps", "frame_ms", "budget_ms"],
	"chunks": ["visible", "generated_per_sec", "rebuilt_per_sec", "mesh_build_ms", "column_ms"],
	"streaming": ["queue_depth", "mesh_queue_depth", "inflight"],
	"crystal": ["update_ms", "presentation_ms", "cells_updated", "dirty_cells", "frontier_size"],
	"entities": ["update_ms", "navigation_ms", "ai_count"],
	"render": ["draw_calls", "multimesh_count", "visible_instances"],
	"world": ["terrain_queries", "terrain_edits", "dirty_regions"],
	"memory": ["current_mb", "peak_mb"],
	"workers": ["worker_ms", "queue_depth"],
}


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		push_error("main scene missing")
		_ProbeExit.finish_tree(self, 1, "Profiler main tests FAILED")
		return

	var game: Node = main_packed.instantiate()
	root.add_child(game)

	var crystal: CrystalManager = null
	var chunk_manager: ChunkManager = null
	var profiler: Node = root.get_node_or_null("/root/PerfProfiler")
	var debug_panel: Node = null

	for _attempt in 1200:
		crystal = get_first_node_in_group("crystal_manager") as CrystalManager
		chunk_manager = get_first_node_in_group("chunk_manager") as ChunkManager
		debug_panel = get_first_node_in_group("debug_panel")
		if (
			crystal != null and crystal._initialized
			and chunk_manager != null and chunk_manager.get_chunk_count() > 0
			and profiler != null
		):
			break
		await process_frame

	if crystal == null or not crystal._initialized:
		push_error("crystal_manager not ready")
		failed = true
	elif chunk_manager == null or chunk_manager.get_chunk_count() <= 0:
		push_error("chunks not loaded")
		failed = true
	elif profiler == null:
		push_error("profiler autoload missing")
		failed = true

	var report_a: Dictionary = {}
	var report_b: Dictionary = {}
	if not failed:
		_EntityBrainRegistry.ensure_builtins()
		var entity_mgr = get_first_node_in_group("entity_manager")
		var player = get_first_node_in_group("player")
		if entity_mgr and player and player.has_method("get_voxel_position"):
			var col: Vector3 = player.get_voxel_position()
			var wx := floori(col.x) + 1
			var wz := floori(col.z) + 1
			var brain = _EntityBrainRegistry.get_def(&"rabbit")
			if brain:
				entity_mgr.call("_spawn_world_entity", wx, wz, brain, Vector2i(wx, wz), Color(0.75, 0.7, 0.65))
				print("OK spawned probe rabbit at %d,%d" % [wx, wz])

		if profiler.has_method("sample_scene_stats"):
			profiler.sample_scene_stats(self)
		report_a = profiler.get_runtime_report()
		for _warm in 120:
			await process_frame

		var best_entity_ms := 0.0
		var best_nav_ms := 0.0
		var best_crystal_ms := 0.0
		var best_chunk_mesh_ms := 0.0
		var best_terrain_queries := 0
		for _sample in 60:
			await process_frame
			if profiler.has_method("sample_scene_stats"):
				profiler.sample_scene_stats(self)
			var sample: Dictionary = profiler.get_runtime_report()
			best_entity_ms = maxf(best_entity_ms, float(sample.entities.update_ms))
			best_nav_ms = maxf(best_nav_ms, float(sample.entities.navigation_ms))
			best_crystal_ms = maxf(best_crystal_ms, float(sample.crystal.update_ms))
			best_chunk_mesh_ms = maxf(best_chunk_mesh_ms, float(sample.chunks.mesh_build_ms))
			best_terrain_queries = maxi(best_terrain_queries, int(sample.world.terrain_queries))
		if crystal and crystal._terrain_query:
			var tq = crystal._terrain_query
			if tq.has_method("get_terrain_height"):
				for i in 16:
					tq.get_terrain_height(Vector2i(4 + i, 4))
				await process_frame
				best_terrain_queries = maxi(
					best_terrain_queries,
					int(profiler.get_runtime_report().world.terrain_queries)
				)
		report_b = profiler.get_runtime_report()

		for section in REQUIRED_SECTIONS.keys():
			if not report_b.has(section):
				push_error("overlay report missing section %s" % section)
				failed = true
				continue
			for field in REQUIRED_SECTIONS[section]:
				if not report_b[section].has(field):
					push_error("overlay report.%s missing %s" % [section, field])
					failed = true

		if int(report_b.chunks.visible) <= 0:
			push_error("chunks visible should be >0 on main scene")
			failed = true
		else:
			print("OK chunks visible=%d" % int(report_b.chunks.visible))

		var crystal_signal := (
			float(report_b.crystal.frontier_size) > 0.0
			or float(report_b.crystal.update_ms) > 0.0
			or int(report_b.crystal.cells_updated) > 0
		)
		if not crystal_signal:
			push_error("crystal metrics all zero after warmup")
			failed = true
		else:
			print("OK crystal metrics live")

		var entity_timing_live := best_entity_ms > 0.0 or best_nav_ms > 0.0
		if not entity_timing_live:
			push_error(
				"entity timings zero after warmup (best update=%.3f nav=%.3f ai=%d)"
				% [best_entity_ms, best_nav_ms, int(report_b.entities.ai_count)]
			)
			failed = true
		else:
			print(
				"OK entity timings live best_update=%.2f best_nav=%.2f ai=%d"
				% [best_entity_ms, best_nav_ms, int(report_b.entities.ai_count)]
			)

		var world_live := (
			best_terrain_queries > 0
			or int(report_b.world.dirty_regions) > 0
			or int(report_b.world.terrain_edits) > 0
		)
		if not world_live:
			push_error(
				"world counters inert (best_queries=%d dirty=%d edits=%d)"
				% [best_terrain_queries, int(report_b.world.dirty_regions), int(report_b.world.terrain_edits)]
			)
			failed = true
		else:
			print(
				"OK world metrics best_queries=%d edits=%d dirty=%d"
				% [best_terrain_queries, int(report_b.world.terrain_edits), int(report_b.world.dirty_regions)]
			)

		var timed_section_live := (
			best_crystal_ms > 0.0
			or best_chunk_mesh_ms > 0.0
			or best_entity_ms > 0.0
			or best_nav_ms > 0.0
		)
		if not timed_section_live:
			push_error("no timed section reported non-zero last-frame ms across samples")
			failed = true
		else:
			print(
				"OK timed sections best crystal=%.2f chunk_mesh=%.2f entity=%.2f"
				% [best_crystal_ms, best_chunk_mesh_ms, best_entity_ms]
			)

		var grew := _report_changed(report_a, report_b)
		if not grew:
			push_error("profiler metrics did not change between samples A and B")
			failed = true
		else:
			print("OK profiler metrics changed A→B")

		if debug_panel and debug_panel.has_method("is_overlay_visible"):
			debug_panel.set_overlay_visible(true)
			await process_frame
			await process_frame
			if profiler.has_method("format_runtime_report"):
				var text: String = profiler.format_runtime_report()
				if "CHUNKS" not in text or "WORLD" not in text:
					push_error("debug overlay perf block missing section headers")
					failed = true
				elif "Entity Update Time:" not in text:
					push_error("debug overlay perf block missing entity timing line")
					failed = true
				else:
					print("OK debug overlay perf block present")

	if failed:
		_ProbeExit.finish_tree(self, 1, "Profiler main tests FAILED")
	else:
		_ProbeExit.finish_tree(self, 0, "All profiler main tests OK")


func _report_changed(a: Dictionary, b: Dictionary) -> bool:
	if int(a.chunks.visible) != int(b.chunks.visible):
		return true
	if float(a.crystal.frontier_size) != float(b.crystal.frontier_size):
		return true
	if float(a.crystal.update_ms) != float(b.crystal.update_ms):
		return true
	if int(a.crystal.cells_updated) != int(b.crystal.cells_updated):
		return true
	if float(a.entities.update_ms) != float(b.entities.update_ms):
		return true
	if float(a.entities.navigation_ms) != float(b.entities.navigation_ms):
		return true
	if int(a.world.terrain_queries) != int(b.world.terrain_queries):
		return true
	if int(a.world.dirty_regions) != int(b.world.dirty_regions):
		return true
	if float(a.chunks.generated_per_sec) != float(b.chunks.generated_per_sec):
		return true
	return false