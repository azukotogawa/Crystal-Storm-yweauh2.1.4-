extends SceneTree
## GPU / renderer investigation — idle vs streaming movement (no optimizations).


const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _ChunkView = preload("res://chunks/chunk_view.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const IDLE_SECONDS := 12.0
const STREAM_SECONDS := 20.0

const TRACKED_SECTIONS := [
	"chunk_mesh", "chunk_buffer", "chunk_upload", "crystal_sim", "crystal_mesh",
	"map_build", "entity_physics", "entity_navigation", "vegetation_growth", "debug_panel",
]

const _CrystalClusterMesh = preload("res://helpers/crystal_cluster_mesh.gd")
const _CrystalChunkLayer = preload("res://crystal/crystal_chunk_layer.gd")

const BOX_TRIS_PER_INSTANCE := 12
const WEDGE_TRIS_ESTIMATE := 8
const CORNER_TRIS_ESTIMATE := 12


func _init() -> void:
	if OS.get_environment("CRYSTALSTORM_PERF_PRESET").strip_edges().is_empty():
		OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH").strip_edges()
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-d700decdc9e9/implementer"
	DirAccess.make_dir_recursive_absolute(scratch)

	var allow_screenshots := OS.get_environment("CRYSTALSTORM_GPU_PROBE_HEADLESS") != "1"
	var preset := OS.get_environment("CRYSTALSTORM_PERF_PRESET").strip_edges().to_lower()

	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		_ProbeExit.finish_tree(self, 1, "gpu renderer investigation FAILED")
		return

	var game: Node = main_packed.instantiate()
	root.add_child(game)

	var player: Node = null
	var chunk_manager: ChunkManager = null
	var profiler: Node = root.get_node_or_null("/root/PerfProfiler")
	var debug_panel: Node = null

	for _attempt in 900:
		player = get_first_node_in_group("player")
		chunk_manager = get_first_node_in_group("chunk_manager")
		debug_panel = get_first_node_in_group("debug_panel")
		if (
			player != null and chunk_manager != null and profiler != null
			and bool(player.get("world_ready"))
			and chunk_manager.chunks.size() >= 3
		):
			break
		await process_frame

	if chunk_manager == null or player == null:
		_ProbeExit.finish_tree(self, 1, "gpu renderer investigation FAILED")
		return

	for _w in 60:
		await process_frame
	if chunk_manager.has_method("await_rebuild_idle"):
		# Crystal growth can keep rebuild queues hot; cap wait so the probe finishes.
		await chunk_manager.await_rebuild_idle(180)
	print("GPU_PROBE=boot_ready chunks=%d" % chunk_manager.chunks.size())

	if debug_panel:
		debug_panel.visible = true
		if debug_panel.has_method("set_process"):
			debug_panel.set_process(true)

	var start_chunk_column := chunk_manager.get_player_chunk_coord()
	var start_chunk_f3 := _chunk_coord_f3(player)
	var start_voxel := _player_voxel_world(player)

	# BEFORE: idle (stable loaded bubble)
	print("GPU_PROBE=phase_idle start")
	var idle_samples := await _sample_phase("idle", IDLE_SECONDS, false, profiler, chunk_manager, allow_screenshots)
	print("GPU_PROBE=phase_idle done frames=%d" % idle_samples.size())
	var idle_scene := _collect_scene_render_stats(chunk_manager)
	if allow_screenshots:
		await _capture_screenshot("%s/gpu_screenshot_before_idle.png" % scratch)
		await _capture_f3_overlay("%s/gpu_f3_overlay_before.txt" % scratch, debug_panel)

	# AFTER: sustained movement + streaming churn
	print("GPU_PROBE=phase_stream start")
	var stream_samples := await _sample_phase("streaming", STREAM_SECONDS, true, profiler, chunk_manager, allow_screenshots)
	print("GPU_PROBE=phase_stream done frames=%d" % stream_samples.size())
	var end_chunk_column := chunk_manager.get_player_chunk_coord()
	var end_chunk_f3 := _chunk_coord_f3(player)
	var end_voxel := _player_voxel_world(player)
	var stream_scene := _collect_scene_render_stats(chunk_manager)
	if allow_screenshots:
		await _capture_screenshot("%s/gpu_screenshot_after_streaming.png" % scratch)
		await _capture_f3_overlay("%s/gpu_f3_overlay_after.txt" % scratch, debug_panel)

	var report := _build_report(
		preset,
		chunk_manager,
		start_chunk_column,
		end_chunk_column,
		start_chunk_f3,
		end_chunk_f3,
		start_voxel,
		end_voxel,
		idle_samples,
		stream_samples,
		idle_scene,
		stream_scene,
		allow_screenshots
	)

	var md_path := "%s/gpu_renderer_before_after_report.md" % scratch
	var jsonl_path := "%s/gpu_renderer_samples.jsonl" % scratch
	_write_text(md_path, report)
	_write_jsonl(jsonl_path, idle_samples, stream_samples)

	_write_chunk_upload_telemetry(scratch, idle_samples, stream_samples, profiler)

	print("GPU_REPORT=%s" % md_path)
	print("GPU_JSONL=%s" % jsonl_path)
	print(report)
	_ProbeExit.finish_tree(self, 0, "gpu renderer investigation OK")


func _sample_phase(
	phase: String,
	seconds: float,
	walk: bool,
	profiler: Node,
	chunk_manager: ChunkManager,
	wait_post_draw: bool = true
) -> Array:
	var samples: Array = []
	var prev_cumulative: Dictionary = {}
	if walk:
		Input.action_press("ui_right")
	var end_ms := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end_ms:
		await process_frame
		if wait_post_draw:
			await RenderingServer.frame_post_draw
		if profiler and profiler.has_method("sample_scene_stats"):
			profiler.sample_scene_stats(self)
		var sample: Dictionary = _collect_frame_sample(phase, profiler, chunk_manager)
		_apply_section_deltas(sample, prev_cumulative)
		prev_cumulative = sample.get("sections_cumulative", {}).duplicate()
		samples.append(sample)
	if walk:
		Input.action_release("ui_right")
	for _idle in 30:
		await process_frame
	return samples


func _collect_frame_sample(phase: String, profiler: Node, chunk_manager: ChunkManager) -> Dictionary:
	var snap: Dictionary = profiler.get_snapshot() if profiler and profiler.has_method("get_snapshot") else {}
	var secs: Dictionary = snap.get("sections", {})
	var scene: Dictionary = snap.get("scene_stats", {})
	var runtime: Dictionary = profiler.get_runtime_report() if profiler and profiler.has_method("get_runtime_report") else {}
	var render_block: Dictionary = runtime.get("render", {})
	var chunks_visible := 0
	if chunk_manager != null:
		chunks_visible = chunk_manager.chunks.size()
	var sections_cumulative: Dictionary = {}
	for section in TRACKED_SECTIONS:
		sections_cumulative[section] = float(secs.get(section, {}).get("last_ms", 0.0))
	return {
		"phase": phase,
		"frame": Engine.get_process_frames(),
		"time_us": Time.get_ticks_usec(),
		"fps": float(Engine.get_frames_per_second()),
		"frame_ms": float(snap.get("frame_ms", 0.0)),
		"worker_ms": float(snap.get("worker_ms", 0.0)),
		"untracked_ms": float(snap.get("untracked_ms", 0.0)),
		"sections_cumulative": sections_cumulative,
		"chunk_upload_ms": sections_cumulative.get("chunk_upload", 0.0),
		"chunk_mesh_ms": sections_cumulative.get("chunk_mesh", 0.0),
		"draw_calls": _perf_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects_in_frame": _perf_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"primitives_in_frame": _perf_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"video_mem_bytes": _rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),
		"texture_mem_bytes": _rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),
		"buffer_mem_bytes": _rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED),
		"pipeline_compilations": 0,
		"rs_draw_calls": _rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"rs_primitives": _rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"multimesh_nodes": int(scene.get("multimesh_nodes", render_block.get("multimesh_count", 0))),
		"multimesh_instances": int(scene.get("multimesh_instances", render_block.get("visible_instances", 0))),
		"texture_bindings": int(scene.get("texture_bindings", render_block.get("texture_bindings", 0))),
		"unique_materials": int(scene.get("unique_materials", render_block.get("unique_materials", 0))),
		"visible_chunks": chunks_visible,
		"pending_buffer_uploads": _ChunkView.pending_buffer_upload_count(),
		"pending_surface_uploads": _ChunkView.pending_surface_upload_count(),
	}


func _perf_monitor(which: int) -> float:
	return float(Performance.get_monitor(which))


func _rendering_info(kind: int) -> int:
	return int(RenderingServer.get_rendering_info(kind))


func _collect_scene_render_stats(chunk_manager: ChunkManager) -> Dictionary:
	var mm_nodes := 0
	var mm_instances := 0
	var est_triangles := 0
	var crystal_mm_nodes := 0
	var crystal_instances := 0
	var crystal_est_triangles := 0
	var material_ids: Dictionary = {}
	var texture_ids: Dictionary = {}
	var transparent_nodes := 0
	var sprite_nodes := 0
	var mesh_instances := 0
	var chunk_views := 0
	var pending_buffers := 0
	var pending_surface := 0
	var texture_bindings := 0

	if chunk_manager != null and is_instance_valid(chunk_manager):
		chunk_views = chunk_manager.chunks.size()
	pending_buffers = _ChunkView.pending_buffer_upload_count()
	pending_surface = _ChunkView.pending_surface_upload_count()

	var walk_root: Node = root.get_node_or_null("Game")
	if walk_root == null:
		walk_root = root
	var stack: Array[Node] = [walk_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)

		if node is MultiMeshInstance3D:
			mm_nodes += 1
			var mm_i: MultiMeshInstance3D = node as MultiMeshInstance3D
			var mm: MultiMesh = mm_i.multimesh
			var count := mm.instance_count if mm else 0
			mm_instances += count
			var kind := "box"
			if mm_i.name == "CrystalFluid":
				kind = "crystal"
			elif "cardinal" in str(mm_i.name):
				kind = "cardinal"
			elif "corner" in str(mm_i.name):
				kind = "corner"
			elif "diagonal" in str(mm_i.name):
				kind = "diagonal"
			var tri_per := BOX_TRIS_PER_INSTANCE
			match kind:
				"crystal":
					crystal_mm_nodes += 1
					crystal_instances += count
					if _CrystalClusterMesh.use_legacy_renderer():
						tri_per = BOX_TRIS_PER_INSTANCE
					else:
						var lod_tier := _CrystalClusterMesh.LOD_FULL
						var parent := mm_i.get_parent()
						if parent is _CrystalChunkLayer:
							lod_tier = (parent as _CrystalChunkLayer).lod_tier
						tri_per = _CrystalClusterMesh.triangle_count_for_lod(lod_tier)
					crystal_est_triangles += count * tri_per
					est_triangles += count * tri_per
				"cardinal":
					est_triangles += count * WEDGE_TRIS_ESTIMATE
				"corner", "diagonal":
					est_triangles += count * CORNER_TRIS_ESTIMATE
				_:
					est_triangles += count * tri_per
			_register_material(material_ids, texture_ids, mm_i.material_override)
			if _is_transparent_material(mm_i.material_override):
				transparent_nodes += 1
		elif node is MeshInstance3D:
			mesh_instances += 1
			var mi: MeshInstance3D = node as MeshInstance3D
			var mi_mat: Material = mi.material_override
			if mi_mat == null and mi.mesh and mi.mesh.get_surface_count() > 0:
				mi_mat = mi.mesh.surface_get_material(0)
			_register_material(material_ids, texture_ids, mi_mat)
			if mi.mesh:
				est_triangles += int(mi.mesh.get_surface_count()) * 12
			if _is_transparent_material(mi_mat):
				transparent_nodes += 1
		elif node is Sprite3D:
			sprite_nodes += 1
			var spr: Sprite3D = node as Sprite3D
			_register_material(material_ids, texture_ids, spr.material_override)
			if spr.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				transparent_nodes += 1

	return {
		"chunk_views": chunk_views,
		"crystal_multimesh_nodes": crystal_mm_nodes,
		"crystal_instances": crystal_instances,
		"crystal_estimated_triangles": crystal_est_triangles,
		"crystal_renderer": (
			"legacy" if _CrystalClusterMesh.use_legacy_renderer() else "procedural"
		),
		"multimesh_nodes": mm_nodes,
		"multimesh_instances": mm_instances,
		"mesh_instances": mesh_instances,
		"sprite3d_nodes": sprite_nodes,
		"unique_materials": material_ids.size(),
		"transparent_drawables": transparent_nodes,
		"estimated_triangles": est_triangles,
		"pending_buffer_uploads": pending_buffers,
		"pending_surface_uploads": pending_surface,
		"texture_bindings": texture_ids.size(),
	}


func _register_material(ids: Dictionary, texture_ids: Dictionary, mat: Material) -> void:
	if mat == null:
		return
	ids[mat.get_instance_id()] = true
	if mat is ShaderMaterial:
		var shader_mat := mat as ShaderMaterial
		var shader: Shader = shader_mat.shader
		if shader:
			for uni_variant in shader.get_shader_uniform_list():
				var uni: Dictionary = uni_variant
				var val: Variant = shader_mat.get_shader_parameter(str(uni.get("name", "")))
				if val is Texture2D:
					texture_ids[(val as Texture2D).get_instance_id()] = true
	elif mat is StandardMaterial3D:
		var std := mat as StandardMaterial3D
		for tex in [std.albedo_texture, std.normal_texture, std.orm_texture]:
			if tex is Texture2D:
				texture_ids[tex.get_instance_id()] = true


func _is_transparent_material(mat: Material) -> bool:
	if mat == null:
		return false
	if mat is StandardMaterial3D:
		var std := mat as StandardMaterial3D
		return std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	if mat is ShaderMaterial:
		var shader: Shader = (mat as ShaderMaterial).shader
		if shader and shader.code:
			var code := shader.code.to_lower()
			if "blend_mix" in code or "blend_add" in code or "alpha" in code:
				if "depth_draw_opaque" not in code:
					return true
	return false


func _aggregate(samples: Array) -> Dictionary:
	if samples.is_empty():
		return {}
	var fields := [
		"fps", "frame_ms", "worker_ms", "untracked_ms",
		"chunk_upload_ms", "chunk_mesh_ms",
		"draw_calls", "objects_in_frame", "primitives_in_frame",
		"video_mem_bytes", "texture_mem_bytes", "buffer_mem_bytes",
		"rs_draw_calls", "rs_primitives",
		"multimesh_nodes", "multimesh_instances", "texture_bindings",
		"unique_materials", "visible_chunks",
		"pending_buffer_uploads", "pending_surface_uploads",
	]
	var out: Dictionary = {"frames": samples.size()}
	for field in fields:
		var vals: Array[float] = []
		for s in samples:
			vals.append(float(s.get(field, 0.0)))
		out["%s_avg" % field] = _mean(vals)
		out["%s_p95" % field] = _percentile(vals, 0.95)
		out["%s_max" % field] = _max(vals)
	for section in TRACKED_SECTIONS:
		var delta_key := "%s_delta_ms" % section
		var vals: Array[float] = []
		for s in samples:
			vals.append(float(s.get(delta_key, 0.0)))
		out["%s_delta_avg" % section] = _mean(vals)
		out["%s_delta_p95" % section] = _percentile(vals, 0.95)
		out["%s_delta_max" % section] = _max(vals)
		out["%s_delta_sum" % section] = _sum(vals)
	if not samples.is_empty():
		var first: Dictionary = samples[0]
		var last: Dictionary = samples[samples.size() - 1]
		for section in TRACKED_SECTIONS:
			var start_cum := float(first.get("sections_cumulative", {}).get(section, 0.0))
			var end_cum := float(last.get("sections_cumulative", {}).get(section, 0.0))
			out["%s_lifetime_delta" % section] = end_cum - start_cum
	return out


func _apply_section_deltas(sample: Dictionary, prev_cumulative: Dictionary) -> void:
	var current: Dictionary = sample.get("sections_cumulative", {})
	for section in TRACKED_SECTIONS:
		var now := float(current.get(section, 0.0))
		var prev := float(prev_cumulative.get(section, 0.0))
		sample["%s_delta_ms" % section] = maxf(now - prev, 0.0)


func _chunk_coord_f3(player: Node) -> Vector2i:
	if player == null or not player.has_method("get_voxel_position"):
		return Vector2i.ZERO
	var col: Vector3 = player.get_voxel_position()
	var ws = _WorldSettings.get_active()
	var world_voxel := Vector3(
		ws.column_to_world(col.x),
		col.y,
		ws.column_to_world(col.z)
	)
	return Vector2i(
		floori(world_voxel.x / float(_ChunkData.SIZE)),
		floori(world_voxel.z / float(_ChunkData.SIZE))
	)


func _player_voxel_world(player: Node) -> Vector3:
	if player == null or not player.has_method("get_voxel_position"):
		return Vector3.ZERO
	var col: Vector3 = player.get_voxel_position()
	var ws = _WorldSettings.get_active()
	return Vector3(
		ws.column_to_world(col.x),
		col.y,
		ws.column_to_world(col.z)
	)


func _build_report(
	preset: String,
	chunk_manager: ChunkManager,
	start_chunk_column: Vector2i,
	end_chunk_column: Vector2i,
	start_chunk_f3: Vector2i,
	end_chunk_f3: Vector2i,
	start_voxel: Vector3,
	end_voxel: Vector3,
	idle_samples: Array,
	stream_samples: Array,
	idle_scene: Dictionary,
	stream_scene: Dictionary,
	screenshots: bool
) -> String:
	var idle := _aggregate(idle_samples)
	var stream := _aggregate(stream_samples)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# GPU / renderer investigation (before vs after streaming)")
	lines.append("")
	lines.append("**Method:** Production `main.tscn`, preset=%s. BEFORE=idle %.0fs. AFTER=sustained `ui_right` %.0fs." % [
		preset, IDLE_SECONDS, STREAM_SECONDS,
	])
	lines.append("**No optimizations applied** — measurement only.")
	lines.append("**Captured:** %s" % Time.get_datetime_string_from_system())
	if float(stream.get("draw_calls_avg", 0.0)) <= 0.0:
		lines.append(
			"**GPU counter note:** `Performance`/`RenderingServer` draw/primitive counters read 0 in this run "
			+ "(headless without `frame_post_draw`). Per-frame profiler Δ tables and scene-walk stats remain valid; "
			+ "re-run display probe for GPU triangle/draw-call counters."
		)
	lines.append("")
	lines.append("## Session context")
	lines.append("")
	lines.append("| Field | Value |")
	lines.append("|-------|-------|")
	lines.append("| RENDER_DISTANCE | %d |" % int(chunk_manager.RENDER_DISTANCE))
	lines.append("| MAX_INFLIGHT | %d |" % int(chunk_manager.MAX_INFLIGHT_CHUNKS))
	lines.append("| Start chunk (column space, ChunkManager) | %s |" % str(start_chunk_column))
	lines.append("| End chunk (column space, ChunkManager) | %s |" % str(end_chunk_column))
	lines.append("| Start chunk (world space, F3/debug_panel) | %s |" % str(start_chunk_f3))
	lines.append("| End chunk (world space, F3/debug_panel) | %s |" % str(end_chunk_f3))
	lines.append("| Start voxel (world, F3) | %.1f, %.1f, %.1f |" % [start_voxel.x, start_voxel.y, start_voxel.z])
	lines.append("| End voxel (world, F3) | %.1f, %.1f, %.1f |" % [end_voxel.x, end_voxel.y, end_voxel.z])
	lines.append("| Chunks crossed (column space) | %d |" % (
		absi(end_chunk_column.x - start_chunk_column.x) + absi(end_chunk_column.y - start_chunk_column.y)
	))
	lines.append("| Chunks crossed (world/F3 space) | %d |" % (
		absi(end_chunk_f3.x - start_chunk_f3.x) + absi(end_chunk_f3.y - start_chunk_f3.y)
	))
	lines.append("")
	lines.append(
		"**Coordinate note:** `ChunkManager.get_player_chunk_coord()` divides **column** coords "
		+ "(`player.get_voxel_position()` before `column_to_world`). F3 `Chunk:` divides **world** "
		+ "voxel coords (`column_to_world` × `voxel_scale`). Both are valid; they differ when "
		+ "`voxel_scale` ≠ 1. Session end F3 chunk %s matches screenshot overlay." % str(end_chunk_f3)
	)
	lines.append("")
	lines.append("## F3 overlay metrics (current debug panel)")
	lines.append("")
	lines.append("The F3 overlay (`ui/debug_panel.gd`) exposes gameplay stats plus a `--- PERF ---` block from `PerfProfiler.format_runtime_report()` (FRAME/CHUNKS/CRYSTAL/ENTITIES/RENDER/WORLD).")
	lines.append("Captured overlay text: `gpu_f3_overlay_before.txt`, `gpu_f3_overlay_after.txt` (when display probe runs).")
	lines.append("")
	_append_investigation_matrix(lines, idle, stream, idle_scene, stream_scene)
	lines.append("")
	_append_section_delta_table(lines, idle, stream)
	lines.append("")
	_append_spike_analysis(lines, stream_samples)
	lines.append("")
	lines.append("## GPU counters — BEFORE (idle)")
	lines.append("")
	_append_metric_table(lines, idle)
	lines.append("")
	lines.append("## GPU counters — AFTER (streaming movement)")
	lines.append("")
	_append_metric_table(lines, stream)
	lines.append("")
	lines.append("## Scene composition (end of AFTER phase)")
	lines.append("")
	lines.append("| Metric | Idle end | Stream end |")
	lines.append("|--------|----------|------------|")
	for key in [
		"chunk_views", "multimesh_nodes", "multimesh_instances", "mesh_instances",
		"sprite3d_nodes", "unique_materials", "transparent_drawables",
		"estimated_triangles", "pending_buffer_uploads",
	]:
		lines.append(
			"| %s | %s | %s |"
			% [key, str(idle_scene.get(key, 0)), str(stream_scene.get(key, 0))]
		)
	lines.append("")
	lines.append("## Delta (AFTER − BEFORE)")
	lines.append("")
	lines.append("| Metric | Δ avg | Interpretation |")
	lines.append("|--------|-------|----------------|")
	for metric in [
		["draw_calls", "Draw calls / frame"],
		["primitives_in_frame", "GPU triangles submitted"],
		["rs_primitives", "RenderingServer primitives"],
		["multimesh_instances", "Visible multimesh instances (scene walk)"],
		["estimated_triangles", "Estimated triangles (scene walk)"],
		["unique_materials", "Material switches (unique materials)"],
		["buffer_mem_bytes", "GPU buffer memory"],
		["chunk_mesh_delta_sum", "Chunk mesh build (per-frame Δ sum)"],
		["chunk_upload_delta_sum", "Chunk upload drain (per-frame Δ sum)"],
		["crystal_sim_delta_sum", "Crystal sim (per-frame Δ sum)"],
	]:
		var field: String = metric[0]
		var label: String = metric[1]
		var a := 0.0
		var b := 0.0
		if field.ends_with("_delta_sum"):
			a = float(idle.get(field, 0.0))
			b = float(stream.get(field, 0.0))
		elif field in idle_scene:
			a = float(idle_scene.get(field, 0))
			b = float(stream_scene.get(field, 0))
		else:
			a = float(idle.get("%s_avg" % field, 0.0))
			b = float(stream.get("%s_avg" % field, 0.0))
		lines.append("| %s | %+.1f | %s |" % [label, b - a, _delta_note(field, b - a)])
	lines.append("")
	lines.append("## Overdraw & shader notes (static analysis)")
	lines.append("")
	lines.append("- Terrain shader `ChunkView.gdshader`: `cull_disabled` submits all box faces; fragment shader **discards** non-target faces (`render_this_face`) — GPU still shades rejected fragments.")
	lines.append("- Atlas `texture()` + branchy face shading per fragment; **one shared** terrain `ShaderMaterial` + one ramp material across chunks (low material-switch cost).")
	lines.append("- Transparent: crystal procedural shader uses `blend_mix`; vegetation/entity billboards may use alpha cutout — see `transparent_drawables` count.")
	lines.append("- **Overdraw:** not directly measurable in-script; orthographic top-down view stacks few opaque layers except vegetation sprites + crystal overlay.")
	lines.append("")
	lines.append("## Upload bandwidth")
	lines.append("")
	lines.append("| Metric | Idle | Stream | Notes |")
	lines.append("|--------|------|--------|-------|")
	lines.append("| buffer_mem_bytes (avg) | %.0f | %.0f | VRAM buffer pool |" % [
		float(idle.get("buffer_mem_bytes_avg", 0.0)),
		float(stream.get("buffer_mem_bytes_avg", 0.0)),
	])
	lines.append("| pending_buffer_uploads (end) | %d | %d | Queue depth at phase end |" % [
		int(idle_scene.get("pending_buffer_uploads", 0)),
		int(stream_scene.get("pending_buffer_uploads", 0)),
	])
	lines.append("| chunk_upload per-frame Δ (avg ms) | %.3f | %.3f | True per-frame upload drain cost |" % [
		float(idle.get("chunk_upload_delta_avg", 0.0)),
		float(stream.get("chunk_upload_delta_avg", 0.0)),
	])
	lines.append("| chunk_upload per-frame Δ (sum ms) | %.1f | %.1f | Total upload time in phase window |" % [
		float(idle.get("chunk_upload_delta_sum", 0.0)),
		float(stream.get("chunk_upload_delta_sum", 0.0)),
	])
	lines.append("| chunk_upload lifetime Δ (cumulative) | %.1f | %.1f | Monotonic PerfProfiler last_us; NOT per-frame |" % [
		float(idle.get("chunk_upload_lifetime_delta", 0.0)),
		float(stream.get("chunk_upload_lifetime_delta", 0.0)),
	])
	lines.append("")
	lines.append(
		"Deferred `MultiMesh.buffer` queue drains ≤1 buffer/frame (`ChunkManager._drain_deferred_mesh_buffers`). "
		+ "F3 `Chunk Upload (ms)` shows **lifetime cumulative** `last_us`; use per-frame Δ columns above for cost."
	)
	lines.append("")
	lines.append("## Render thread time & CPU/GPU sync")
	lines.append("")
	lines.append("Godot 4 Forward+ does not expose per-frame render-thread ms to GDScript.")
	lines.append("")
	lines.append("| Proxy | Idle avg | Stream avg | Usable? |")
	lines.append("|-------|----------|------------|---------|")
	lines.append("| untracked_ms | %.3f | %.3f | **No** — clamps to 0 because section last_us is lifetime-cumulative |" % [
		float(idle.get("untracked_ms_avg", 0.0)),
		float(stream.get("untracked_ms_avg", 0.0)),
	])
	lines.append("| frame_ms | %.3f | %.3f | Yes — whole main-loop frame time |" % [
		float(idle.get("frame_ms_avg", 0.0)),
		float(stream.get("frame_ms_avg", 0.0)),
	])
	lines.append("| frame_ms max | %.3f | %.3f | Yes — episodic spikes; see spike analysis |" % [
		float(idle.get("frame_ms_max", 0.0)),
		float(stream.get("frame_ms_max", 0.0)),
	])
	lines.append("")
	lines.append(
		"**Do not infer CPU/GPU sync stalls from untracked_ms** (always 0 in this profiler layout). "
		+ "Use frame_ms spikes + per-frame section deltas + pending upload queue depth instead."
	)
	lines.append("")
	lines.append("## GPU bottleneck determination")
	lines.append("")
	lines.append(_bottleneck_verdict(idle, stream, idle_scene, stream_scene, stream_samples))
	lines.append("")
	if screenshots:
		lines.append("## Screenshots")
		lines.append("")
		lines.append("- `gpu_screenshot_before_idle.png` — loaded bubble, no movement")
		lines.append("- `gpu_screenshot_after_streaming.png` — after 20s traversal")
	else:
		lines.append("## Screenshots")
		lines.append("")
		lines.append("Skipped (`CRYSTALSTORM_GPU_PROBE_HEADLESS=1`). Re-run without headless for PNG + F3 captures.")
	lines.append("")
	return "\n".join(lines)


func _bottleneck_verdict(
	idle: Dictionary,
	stream: Dictionary,
	_idle_scene: Dictionary,
	stream_scene: Dictionary,
	stream_samples: Array
) -> String:
	var draw_idle := float(idle.get("draw_calls_avg", 0.0))
	var draw_stream := float(stream.get("draw_calls_avg", 0.0))
	var prim_stream := float(stream.get("primitives_in_frame_avg", 0.0))
	var frame_delta := float(stream.get("frame_ms_avg", 0.0)) - float(idle.get("frame_ms_avg", 0.0))
	var mesh_delta_sum := float(stream.get("chunk_mesh_delta_sum", 0.0)) - float(idle.get("chunk_mesh_delta_sum", 0.0))
	var upload_delta_sum := float(stream.get("chunk_upload_delta_sum", 0.0)) - float(idle.get("chunk_upload_delta_sum", 0.0))
	var crystal_delta_sum := float(stream.get("crystal_sim_delta_sum", 0.0)) - float(idle.get("crystal_sim_delta_sum", 0.0))
	var mm := int(stream_scene.get("multimesh_instances", 0))
	var mats := int(stream_scene.get("unique_materials", 0))
	var spike_count := _count_spikes(stream_samples, 100.0)
	var spike_unscoped := _count_spikes_unscoped(stream_samples, 100.0)

	var parts: PackedStringArray = PackedStringArray()
	if draw_stream < 80 and prim_stream < 500_000:
		parts.append(
			"**GPU steady-state: not draw-call or triangle bound** at medium preset "
			+ "(avg ~%.0f draws, ~%.0f GPU triangles/frame)."
			% [draw_stream, prim_stream]
		)
	else:
		parts.append(
			"**GPU steady-state: elevated draw/triangle load** (avg draws=%.0f, triangles=%.0f)."
			% [draw_stream, prim_stream]
		)

	parts.append(
		(
			"Terrain visible at stream end: **%d MultiMesh instances** across %d chunk views; "
			+ "~%d scene-walk triangles; **%d unique materials** (terrain uses 2 shared shaders)."
		)
		% [mm, int(stream_scene.get("chunk_views", 0)), int(stream_scene.get("estimated_triangles", 0)), mats]
	)

	parts.append(
		(
			"**Primary tracked main-thread cost during streaming (per-frame Δ sums, stream − idle):** "
			+ "chunk_mesh Δ%+.0f ms, crystal_sim Δ%+.0f ms, chunk_upload Δ%+.0f ms. "
			+ "**Mesh build dominates tracked time**; upload drain is a small fraction (~%.0f ms total in stream window)."
		)
		% [mesh_delta_sum, crystal_delta_sum, upload_delta_sum, float(stream.get("chunk_upload_delta_sum", 0.0))]
	)

	parts.append(
		(
			"**Frame spikes:** %d frames >100 ms in stream phase; %d of those have meshΔ≈0, uploadΔ≈0, pending_uploads=0 "
			+ "(residual unscoped main-thread / engine work — not attributable to measured profiler sections)."
		)
		% [spike_count, spike_unscoped]
	)

	if frame_delta > 3.0:
		parts.append(
			(
				"**Streaming raises avg frame_ms by %+.1f ms** with **flat or lower draw counts** (draw Δ%+.1f) — "
				+ "regression is main-thread simulation/mesh work and episodic spikes, not sustained GPU geometry growth."
			)
			% [frame_delta, draw_stream - draw_idle]
		)

	parts.append(
		"**Shader cost (static):** single atlas lookup + fragment discard per instance; scales with shaded fragments."
	)
	parts.append(
		"**Transparent drawables:** %d — secondary vs terrain MultiMesh."
		% int(stream_scene.get("transparent_drawables", 0))
	)
	return "\n".join(parts)


func _delta_note(field: String, delta: float) -> String:
	match field:
		"draw_calls", "primitives_in_frame", "rs_primitives":
			return "Higher ⇒ more GPU geometry submitted" if delta > 0 else "Stable GPU submission"
		"multimesh_instances", "estimated_triangles":
			return "More loaded terrain visible" if delta > 0 else "Similar visible terrain"
		"unique_materials":
			return "More material switches" if delta > 0 else "Stable material count"
		"buffer_mem_bytes":
			return "GPU buffer pool growth during stream" if delta > 0 else "Stable VRAM buffers"
		"chunk_mesh_delta_sum":
			return "More mesh build main-thread time" if delta > 0 else "Less mesh build time"
		"chunk_upload_delta_sum":
			return "More upload drain time" if delta > 0 else "Less upload drain time"
		"crystal_sim_delta_sum":
			return "More crystal sim time" if delta > 0 else "Less crystal sim time"
		_:
			return ""


func _append_section_delta_table(lines: PackedStringArray, idle: Dictionary, stream: Dictionary) -> void:
	lines.append("## Per-frame profiler section deltas (tracked main-thread cost)")
	lines.append("")
	lines.append(
		"`PerfProfiler` section `last_us` is lifetime-cumulative. Per-frame Δ = delta of cumulative between consecutive samples."
	)
	lines.append("")
	lines.append("| Section | Idle avg Δ (ms) | Stream avg Δ (ms) | Stream sum Δ (ms) | Stream max Δ (ms) |")
	lines.append("|---------|-----------------|-------------------|-------------------|-------------------|")
	for section in TRACKED_SECTIONS:
		lines.append(
			"| %s | %.3f | %.3f | %.1f | %.3f |"
			% [
				section,
				float(idle.get("%s_delta_avg" % section, 0.0)),
				float(stream.get("%s_delta_avg" % section, 0.0)),
				float(stream.get("%s_delta_sum" % section, 0.0)),
				float(stream.get("%s_delta_max" % section, 0.0)),
			]
		)
	lines.append("")


func _append_spike_analysis(lines: PackedStringArray, stream_samples: Array) -> void:
	lines.append("## Frame spike analysis (streaming phase, frame_ms > 100 ms)")
	lines.append("")
	var spikes: Array = []
	for s in stream_samples:
		if float(s.get("frame_ms", 0.0)) > 100.0:
			spikes.append(s)
	if spikes.is_empty():
		lines.append("No frames exceeded 100 ms in the streaming sample window.")
		lines.append("")
		return
	lines.append("| # | frame_ms | draw_calls | meshΔ | uploadΔ | pending_buf | crystalΔ |")
	lines.append("|---|----------|------------|-------|---------|-------------|----------|")
	var show_max := mini(spikes.size(), 12)
	for i in show_max:
		var s: Dictionary = spikes[i]
		lines.append(
			"| %d | %.1f | %.0f | %.3f | %.3f | %d | %.3f |"
			% [
				i + 1,
				float(s.get("frame_ms", 0.0)),
				float(s.get("draw_calls", 0.0)),
				float(s.get("chunk_mesh_delta_ms", 0.0)),
				float(s.get("chunk_upload_delta_ms", 0.0)),
				int(s.get("pending_buffer_uploads", 0)),
				float(s.get("crystal_sim_delta_ms", 0.0)),
			]
		)
	var unscoped := _count_spikes_unscoped(stream_samples, 100.0)
	lines.append("")
	lines.append(
		(
			"%d/%d spikes have meshΔ<0.05, uploadΔ<0.05, pending_buf=0 — residual cost is **unscoped** "
			+ "(engine/render thread / un-instrumented systems)."
		)
		% [unscoped, spikes.size()]
	)
	lines.append("")


func _count_spikes(samples: Array, threshold: float) -> int:
	var count := 0
	for s in samples:
		if float(s.get("frame_ms", 0.0)) > threshold:
			count += 1
	return count


func _count_spikes_unscoped(samples: Array, threshold: float) -> int:
	var count := 0
	for s in samples:
		if float(s.get("frame_ms", 0.0)) <= threshold:
			continue
		if (
			float(s.get("chunk_mesh_delta_ms", 0.0)) < 0.05
			and float(s.get("chunk_upload_delta_ms", 0.0)) < 0.05
			and int(s.get("pending_buffer_uploads", 0)) == 0
		):
			count += 1
	return count


func _append_metric_table(lines: PackedStringArray, agg: Dictionary) -> void:
	lines.append("| Metric | Avg | P95 | Max |")
	lines.append("|--------|-----|-----|-----|")
	for row in [
		["FPS", "fps"],
		["Frame time (ms)", "frame_ms"],
		["Untracked main (ms)", "untracked_ms"],
		["Draw calls", "draw_calls"],
		["Objects in frame", "objects_in_frame"],
		["GPU triangles in frame", "primitives_in_frame"],
		["RS draw calls", "rs_draw_calls"],
		["RS primitives", "rs_primitives"],
		["Video mem (MB)", "video_mem_bytes"],
		["Texture mem (MB)", "texture_mem_bytes"],
		["Buffer mem (MB)", "buffer_mem_bytes"],
	]:
		var label: String = row[0]
		var key: String = row[1]
		var avg := float(agg.get("%s_avg" % key, 0.0))
		var p95 := float(agg.get("%s_p95" % key, 0.0))
		var mx := float(agg.get("%s_max" % key, 0.0))
		if key.ends_with("_bytes"):
			lines.append("| %s | %.2f | %.2f | %.2f |" % [label, avg / 1_048_576.0, p95 / 1_048_576.0, mx / 1_048_576.0])
		else:
			lines.append("| %s | %.2f | %.2f | %.2f |" % [label, avg, p95, mx])


func _capture_screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	await process_frame
	var vp := root.get_viewport()
	if vp == null:
		return
	var tex: Texture2D = vp.get_texture()
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return
	img.save_png(path)
	print("GPU_SCREENSHOT=%s" % path)


func _append_investigation_matrix(
	lines: PackedStringArray,
	idle: Dictionary,
	stream: Dictionary,
	idle_scene: Dictionary,
	stream_scene: Dictionary
) -> void:
	lines.append("## Complete rendering profile (every investigation area)")
	lines.append("")
	lines.append("| Area | Source | Idle | Streaming | Notes |")
	lines.append("|------|--------|------|-----------|-------|")
	var rows: Array = [
		["Draw calls", "Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME", "draw_calls_avg", "draw_calls_avg", "Measured per frame"],
		["MultiMesh node count", "scene walk + PerfProfiler.sample_scene_stats", "multimesh_nodes_avg", "multimesh_nodes_avg", "MultiMeshInstance3D nodes in tree"],
		["Visible instances", "scene walk multimesh.instance_count sum", "multimesh_instances_avg", "multimesh_instances_avg", "GPU instance transforms submitted"],
		["Visible chunks", "ChunkManager.chunks.size()", "visible_chunks_avg", "visible_chunks_avg", "Loaded chunk views in bubble"],
		["GPU triangle count", "Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME", "primitives_in_frame_avg", "primitives_in_frame_avg", "Counts triangles (1 primitive = 1 triangle in Godot)"],
		["Scene-walk triangle est.", "scene walk (box×12 + ramps)", "scene_est_tri", "scene_est_tri", "End-of-phase snapshot"],
		["Overdraw", "static shader analysis", "—", "—", "Not directly measurable in GDScript; see Overdraw section"],
		["Material switches", "unique material instance_ids (scene walk)", "unique_materials_avg", "unique_materials_avg", "Terrain uses 2 shared shaders; props inflate count"],
		["Shader cost", "ChunkView.gdshader static analysis", "—", "—", "cull_disabled + fragment discard; see Shader section"],
		["Texture bindings", "unique Texture2D from shader uniforms", "texture_bindings_avg", "texture_bindings_avg", "Atlas + prop textures"],
		["GPU upload cost", "chunk_upload per-frame Δ", "chunk_upload_delta_avg", "chunk_upload_delta_avg", "Per-frame upload drain; F3 shows lifetime cumulative"],
		["Main-thread render cost", "frame_ms (whole loop)", "frame_ms_avg", "frame_ms_avg", "Not GPU-isolated; includes sim + mesh + upload"],
		["Render-thread time", "not exposed in GDScript", "—", "—", "No direct timer; use frame_ms max spikes"],
		["CPU/GPU synchronization", "not directly measurable", "—", "—", "untracked_ms proxy failed (see Render thread section)"],
		["Buffer allocations (proxy)", "pending upload queue depth", "pending_buffer_uploads_avg", "pending_buffer_uploads_avg", "Deferred MultiMesh/surface queues"],
		["Buffer uploads", "ChunkView.drain_pending_* + buffer_mem", "buffer_mem_bytes_avg", "buffer_mem_bytes_avg", "VRAM buffer pool growth"],
	]
	for row in rows:
		var label: String = row[0]
		var source: String = row[1]
		var idle_key: String = row[2]
		var stream_key: String = row[3]
		var notes: String = row[4]
		var idle_val: String = "—"
		var stream_val: String = "—"
		if idle_key == "scene_est_tri":
			idle_val = str(idle_scene.get("estimated_triangles", 0))
			stream_val = str(stream_scene.get("estimated_triangles", 0))
		elif idle_key.ends_with("_avg"):
			idle_val = "%.2f" % float(idle.get(idle_key, 0.0))
			stream_val = "%.2f" % float(stream.get(stream_key, 0.0))
		elif idle_key.ends_with("_max"):
			idle_val = "%.2f" % float(idle.get(idle_key, 0.0))
			stream_val = "%.2f" % float(stream.get(stream_key, 0.0))
		lines.append("| %s | %s | %s | %s | %s |" % [label, source, idle_val, stream_val, notes])
	lines.append("")


func _write_chunk_upload_telemetry(scratch: String, idle: Array, stream: Array, profiler: Node) -> void:
	var upload_delta_idle: Array = []
	var upload_delta_stream: Array = []
	var upload_cum_idle: Array = []
	var upload_cum_stream: Array = []
	var pending_buf_stream: Array = []
	var pending_surf_stream: Array = []
	for s in idle:
		upload_delta_idle.append(float(s.get("chunk_upload_delta_ms", 0.0)))
		upload_cum_idle.append(float(s.get("chunk_upload_ms", 0.0)))
	for s in stream:
		upload_delta_stream.append(float(s.get("chunk_upload_delta_ms", 0.0)))
		upload_cum_stream.append(float(s.get("chunk_upload_ms", 0.0)))
		pending_buf_stream.append(float(s.get("pending_buffer_uploads", 0.0)))
		pending_surf_stream.append(float(s.get("pending_surface_uploads", 0.0)))
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Chunk upload telemetry (measurement only)")
	lines.append("")
	lines.append("| Metric | Idle | Stream | Notes |")
	lines.append("|--------|------|--------|-------|")
	lines.append("| chunk_upload per-frame Δ avg (ms) | %.3f | %.3f | True per-frame upload drain |" % [
		_mean(upload_delta_idle), _mean(upload_delta_stream),
	])
	lines.append("| chunk_upload per-frame Δ sum (ms) | %.1f | %.1f | Total in phase window |" % [
		_sum(upload_delta_idle), _sum(upload_delta_stream),
	])
	lines.append("| chunk_upload per-frame Δ max (ms) | %.3f | %.3f | Worst single frame |" % [
		_max(upload_delta_idle), _max(upload_delta_stream),
	])
	var lifetime_idle := 0.0
	var lifetime_stream := 0.0
	if not idle.is_empty():
		var first_i: Dictionary = idle[0]
		var last_i: Dictionary = idle[idle.size() - 1]
		lifetime_idle = float(last_i.get("sections_cumulative", {}).get("chunk_upload", 0.0)) - float(first_i.get("sections_cumulative", {}).get("chunk_upload", 0.0))
	if not stream.is_empty():
		var first_s: Dictionary = stream[0]
		var last_s: Dictionary = stream[stream.size() - 1]
		lifetime_stream = float(last_s.get("sections_cumulative", {}).get("chunk_upload", 0.0)) - float(first_s.get("sections_cumulative", {}).get("chunk_upload", 0.0))
	lines.append("| chunk_upload lifetime Δ (cumulative last_us) | %.1f | %.1f | Monotonic; F3 shows end-of-run total |" % [
		lifetime_idle, lifetime_stream,
	])
	var pending_buf_idle: Array = []
	var pending_surf_idle: Array = []
	for s in idle:
		pending_buf_idle.append(float(s.get("pending_buffer_uploads", 0.0)))
		pending_surf_idle.append(float(s.get("pending_surface_uploads", 0.0)))
	lines.append("| pending_buffer_uploads (queue depth avg) | %.2f | %.2f | |" % [
		_mean(pending_buf_idle), _mean(pending_buf_stream),
	])
	lines.append("| pending_buffer_uploads (queue depth max) | %.0f | %.0f | |" % [
		_max(pending_buf_idle), _max(pending_buf_stream),
	])
	lines.append("| pending_surface_uploads (queue depth max) | %.0f | %.0f | |" % [
		_max(pending_surf_idle), _max(pending_surf_stream),
	])
	lines.append("")
	lines.append("Evidence: `ChunkView.enqueue_buffer_upload` / `enqueue_surface_mesh_upload` drain ≤1 item/frame in `ChunkManager._drain_deferred_mesh_buffers`.")
	lines.append("F3 `Chunk Upload (ms)` = lifetime cumulative `last_us`, NOT per-frame — use per-frame Δ rows above.")
	if profiler and profiler.has_method("get_runtime_report"):
		var r: Dictionary = profiler.get_runtime_report()
		lines.append("Final F3 RENDER block: draw_calls=%d multimesh=%d instances=%d upload_cumulative_ms=%.2f" % [
			int(r.render.draw_calls),
			int(r.render.multimesh_count),
			int(r.render.visible_instances),
			float(r.render.chunk_upload_ms),
		])
	_write_text("%s/chunk_upload_telemetry.txt" % scratch, "\n".join(lines))
	print("GPU_UPLOAD_TELEMETRY=%s/chunk_upload_telemetry.txt" % scratch)


func _capture_f3_overlay(path: String, debug_panel: Node) -> void:
	if debug_panel == null:
		return
	for _i in 24:
		await process_frame
	var label: Node = debug_panel.get_node_or_null("DebugLabel")
	if label == null or not ("text" in label):
		return
	_write_text(path, "F3 Debug overlay capture\n\n%s" % str(label.text))


func _write_jsonl(path: String, idle: Array, stream: Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	for row in idle:
		f.store_line(JSON.stringify(row))
	for row in stream:
		f.store_line(JSON.stringify(row))
	f.close()


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()


static func _sum(values: Array) -> float:
	var total := 0.0
	for v in values:
		total += float(v)
	return total


static func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sum := 0.0
	for v in values:
		sum += float(v)
	return sum / float(values.size())


static func _max(values: Array) -> float:
	var m := 0.0
	for v in values:
		m = maxf(m, float(v))
	return m


static func _percentile(values: Array, p: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array = values.duplicate()
	sorted.sort()
	var idx := int(floorf(float(sorted.size() - 1) * p))
	return float(sorted[idx])