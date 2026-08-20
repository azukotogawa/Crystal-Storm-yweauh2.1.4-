extends SceneTree
## Paired crystal renderer benchmark — same seed/spread, legacy vs procedural.

const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _CrystalClusterMesh = preload("res://helpers/crystal_cluster_mesh.gd")
const _CrystalChunkLayer = preload("res://crystal/crystal_chunk_layer.gd")

const SPREAD_SECONDS := 45.0
const SETTLE_SECONDS := 6.0
const SAMPLE_SECONDS := 8.0

const TRACKED_SECTIONS := ["crystal_mesh", "crystal_sim"]


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	OS.set_environment("CRYSTALSTORM_GPU_PROBE_HEADLESS", "1")
	call_deferred("_run")


func _run() -> void:
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH").strip_edges()
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-d95151e877bc/implementer"
	DirAccess.make_dir_recursive_absolute(scratch)

	var renderer := OS.get_environment("CRYSTALSTORM_CRYSTAL_RENDERER").strip_edges().to_lower()
	if renderer.is_empty():
		renderer = "procedural"
	var log_name := "crystal_render_after.log" if renderer != "legacy" else "crystal_render_baseline.log"

	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		_ProbeExit.finish_tree(self, 1, "crystal render benchmark FAILED")
		return

	var game: Node = main_packed.instantiate()
	root.add_child(game)

	var crystal_mgr: CrystalManager = null
	var chunk_manager: ChunkManager = null
	var profiler: Node = root.get_node_or_null("/root/PerfProfiler")

	for _attempt in 900:
		crystal_mgr = get_first_node_in_group("crystal_manager") as CrystalManager
		chunk_manager = get_first_node_in_group("chunk_manager")
		if (
			crystal_mgr != null and chunk_manager != null and profiler != null
			and crystal_mgr._initialized
		):
			break
		await process_frame

	if crystal_mgr == null:
		_ProbeExit.finish_tree(self, 1, "crystal render benchmark FAILED")
		return

	for _w in 60:
		await process_frame

	var spread_end_ms := Time.get_ticks_msec() + int(SPREAD_SECONDS * 1000.0)
	while Time.get_ticks_msec() < spread_end_ms:
		await process_frame
	if chunk_manager and chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle(120)

	var expansion_was_enabled := crystal_mgr.expansion_enabled
	crystal_mgr.expansion_enabled = false
	var settle_end_ms := Time.get_ticks_msec() + int(SETTLE_SECONDS * 1000.0)
	while Time.get_ticks_msec() < settle_end_ms:
		await process_frame
	if chunk_manager and chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle(90)

	var samples: Array = []
	var prev_cumulative: Dictionary = {}
	var sample_end_ms := Time.get_ticks_msec() + int(SAMPLE_SECONDS * 1000.0)
	while Time.get_ticks_msec() < sample_end_ms:
		await process_frame
		if profiler and profiler.has_method("sample_scene_stats"):
			profiler.sample_scene_stats(self)
		var sample: Dictionary = _collect_sample(profiler)
		_apply_section_deltas(sample, prev_cumulative)
		prev_cumulative = sample.get("sections_cumulative", {}).duplicate()
		samples.append(sample)

	crystal_mgr.expansion_enabled = expansion_was_enabled

	var scene := _collect_crystal_scene_stats()
	var agg := _aggregate(samples)
	var draw_calls_gpu := float(agg.get("draw_calls_avg", 0.0))
	var draw_calls_est := float(scene.get("crystal_multimesh_nodes", 0))
	if draw_calls_gpu <= 0.0:
		draw_calls_est = draw_calls_est
	var buffer_gpu := float(agg.get("buffer_mem_bytes_avg", 0.0))
	var gpu_mem_est := float(scene.get("gpu_memory_est_bytes", 0))
	if buffer_gpu > 0.0:
		gpu_mem_est = buffer_gpu

	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Crystal render benchmark")
	lines.append("renderer=%s" % renderer)
	lines.append("crystal_cells=%d" % crystal_mgr.covered_cells)
	lines.append("spread_seconds=%.1f settle_seconds=%.1f sample_seconds=%.1f" % [
		SPREAD_SECONDS, SETTLE_SECONDS, SAMPLE_SECONDS,
	])
	lines.append("")
	lines.append("## Plan metrics (5)")
	lines.append("")
	lines.append("| metric | value |")
	lines.append("|--------|-------|")
	lines.append("| draw_calls | %.2f |" % (draw_calls_gpu if draw_calls_gpu > 0.0 else draw_calls_est))
	lines.append("| triangle_count | %d |" % int(scene.get("crystal_estimated_triangles", 0)))
	lines.append("| gpu_memory_bytes | %.0f |" % gpu_mem_est)
	lines.append("| crystal_mesh_time_ms | %.3f |" % float(agg.get("crystal_mesh_delta_sum", 0.0)))
	lines.append("| frame_time_ms | %.3f |" % float(agg.get("frame_ms_avg", 0.0)))
	lines.append("")
	lines.append("## Estimation notes")
	lines.append("draw_calls_source=%s" % ("gpu_counter" if draw_calls_gpu > 0.0 else "crystal_multimesh_nodes"))
	lines.append("gpu_memory_source=%s" % ("gpu_counter" if buffer_gpu > 0.0 else "mesh_buffer_estimate"))
	lines.append("crystal_instances=%d" % int(scene.get("crystal_instances", 0)))
	lines.append("crystal_multimesh_nodes=%d" % int(scene.get("crystal_multimesh_nodes", 0)))
	lines.append("crystal_tris_per_instance=%.3f" % float(scene.get("crystal_tris_per_instance", 0.0)))
	lines.append("crystal_renderer_mode=%s" % str(scene.get("crystal_renderer", renderer)))
	lines.append("uses_procedural_layers=%d" % int(scene.get("procedural_layers", 0)))

	var log_path := "%s/%s" % [scratch, log_name]
	_write_text(log_path, "\n".join(lines))
	print("CRYSTAL_RENDER_BENCHMARK=%s" % log_path)
	print("\n".join(lines))
	_ProbeExit.finish_tree(self, 0, "crystal render benchmark OK")


func _collect_sample(profiler: Node) -> Dictionary:
	var snap: Dictionary = profiler.get_snapshot() if profiler and profiler.has_method("get_snapshot") else {}
	var secs: Dictionary = snap.get("sections", {})
	var sections_cumulative: Dictionary = {}
	for section in TRACKED_SECTIONS:
		sections_cumulative[section] = float(secs.get(section, {}).get("last_ms", 0.0))
	return {
		"frame_ms": float(snap.get("frame_ms", 0.0)),
		"draw_calls": float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"buffer_mem_bytes": float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)),
		"sections_cumulative": sections_cumulative,
	}


func _collect_crystal_scene_stats() -> Dictionary:
	var crystal_mm := 0
	var crystal_instances := 0
	var crystal_tris := 0
	var procedural_layers := 0
	var walk_root: Node = root.get_node_or_null("Game")
	if walk_root == null:
		walk_root = root
	var stack: Array[Node] = [walk_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is _CrystalChunkLayer:
			var layer := node as _CrystalChunkLayer
			if layer.uses_procedural_mesh():
				procedural_layers += 1
		if node is MultiMeshInstance3D and node.name == "CrystalFluid":
			crystal_mm += 1
			var mm: MultiMesh = (node as MultiMeshInstance3D).multimesh
			var count := mm.instance_count if mm else 0
			crystal_instances += count
			var lod_tier := _CrystalClusterMesh.LOD_NEAR
			var parent := node.get_parent()
			if parent is _CrystalChunkLayer:
				lod_tier = (parent as _CrystalChunkLayer).lod_tier
			var tri_per := (
				12 if _CrystalClusterMesh.use_legacy_renderer()
				else _CrystalClusterMesh.triangle_count_for_lod(lod_tier)
			)
			crystal_tris += count * tri_per

	var tris_per_inst := 0.0
	if crystal_instances > 0:
		tris_per_inst = float(crystal_tris) / float(crystal_instances)
	var gpu_mem_est := _CrystalClusterMesh.estimate_gpu_buffer_bytes(
		crystal_instances, crystal_tris, crystal_mm
	)
	return {
		"crystal_multimesh_nodes": crystal_mm,
		"crystal_instances": crystal_instances,
		"crystal_estimated_triangles": crystal_tris,
		"crystal_tris_per_instance": tris_per_inst,
		"gpu_memory_est_bytes": gpu_mem_est,
		"procedural_layers": procedural_layers,
		"crystal_renderer": "legacy" if _CrystalClusterMesh.use_legacy_renderer() else "procedural",
	}


func _aggregate(samples: Array) -> Dictionary:
	if samples.is_empty():
		return {}
	var out: Dictionary = {"frames": samples.size()}
	for field in ["frame_ms", "draw_calls", "buffer_mem_bytes"]:
		var vals: Array[float] = []
		for s in samples:
			vals.append(float(s.get(field, 0.0)))
		out["%s_avg" % field] = _mean(vals)
	for section in TRACKED_SECTIONS:
		var vals: Array[float] = []
		for s in samples:
			vals.append(float(s.get("%s_delta_ms" % section, 0.0)))
		out["%s_delta_sum" % section] = _sum(vals)
	return out


func _apply_section_deltas(sample: Dictionary, prev_cumulative: Dictionary) -> void:
	var current: Dictionary = sample.get("sections_cumulative", {})
	for section in TRACKED_SECTIONS:
		var now := float(current.get(section, 0.0))
		var prev := float(prev_cumulative.get(section, 0.0))
		sample["%s_delta_ms" % section] = maxf(now - prev, 0.0)


static func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sum := 0.0
	for v in values:
		sum += float(v)
	return sum / float(values.size())


static func _sum(values: Array) -> float:
	var total := 0.0
	for v in values:
		total += float(v)
	return total


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()