extends Node
## Permanent runtime profiler for Crystal Storm.
## Exposes per-frame subsystem timings, worker/stream gauges, memory, and
## bottleneck ranking for in-game debug + headless probes.
## Autoload: PerfProfiler. Does not change gameplay — measurement only.

const FRAME_BUDGET_MS: float = 16.6
const HISTORY_LEN: int = 120
## Worker-attributed stages (completed off-main). Must NOT reduce main-thread untracked.
const WORKER_STAGE_SECTIONS := {
	"chunk_mesh": true,
	"chunk_column": true,
	"chunk_buffer": true,
	"worker_total": true,
}

var enabled: bool = true

## Active timing stacks / accumulation for the *current* frame.
var _sections: Dictionary = {}  # name -> {active, start, cur_us, last_us, max_us, total_us, worker, exclusive_us, last_exclusive_us, calls, last_calls}
var _funcs: Dictionary = {}  # Class::method -> same shape + calls
var _frame_us: int = 0
var _frame_start: int = 0
var _worker_us: int = 0
var _worker_frame_us: int = 0
var _gauges: Dictionary = {}
var _frame_counters: Dictionary = {}
var _report_frame_counters: Dictionary = {}
var _rate_accum: Dictionary = {}
var _rate_per_sec: Dictionary = {}
var _rate_last_msec: int = 0
var _scene_stats: Dictionary = {
	"multimesh_nodes": 0,
	"multimesh_instances": 0,
	"mesh_instances": 0,
	"texture_bindings": 0,
	"unique_materials": 0,
	"draw_calls": 0.0,
	"objects_in_frame": 0.0,
	"primitives_in_frame": 0.0,
}
var _frame_history_ms: PackedFloat32Array = PackedFloat32Array()
var _spike_count: int = 0
var _frames_seen: int = 0
var _mem_current_mb: float = 0.0
var _mem_peak_mb: float = 0.0
var _engine_time_process_ms: float = 0.0
var _engine_time_physics_ms: float = 0.0
## Exclusive nested section stack (main-thread attribution without double-count).
var _section_stack: Array = []  # section names, bottom→top
var _exclusive_open_us: Dictionary = {}  # section -> usec when exclusive slice started
## Last closed frame attribution (set in _process rotate).
var _last_attribution: Dictionary = {}


func _enter_tree() -> void:
	add_to_group("perf_profiler")
	_frame_start = Time.get_ticks_usec()


func _ready() -> void:
	# Run late so section accumulation for the frame is complete before rotation.
	process_priority = 100000
	set_process(true)
	call_deferred("_register_monitors_if_in_game")


func _register_monitors_if_in_game() -> void:
	if get_tree().get_first_node_in_group("config_service") == null:
		return
	_register_monitors()


func _process(_delta: float) -> void:
	if not enabled:
		return
	# Close process envelope and schedule frame finalize after MessageQueue flush
	# (call_deferred), so MainLoop_deferred exclusive is not cut short by rotate.
	var probe = get_node_or_null("/root/MainThreadFrameProbe")
	if probe and probe.has_method("close_process_envelope"):
		probe.close_process_envelope()
	else:
		# No probe: finalize immediately (tests / stripped boots).
		finalize_frame()


## End-of-frame accounting. Prefer calling after deferred MessageQueue work.
## full_wall = mark_frame_work_start → here (physics+process+deferred MQ only).
func finalize_frame() -> void:
	if not enabled:
		return
	var now := Time.get_ticks_usec()
	if _frame_work_started:
		_frame_us = maxi(now - _frame_start, 1)
	else:
		# No phase marker (tests): fall back to prior finalize clock.
		_frame_us = maxi(now - _frame_start, 1)
	_frame_work_started = false
	# Next work window starts on mark_frame_work_start; keep a fallback clock.
	_frame_start = now
	_worker_frame_us = _worker_us
	_worker_us = 0
	_report_frame_counters = _frame_counters.duplicate()
	_frame_counters.clear()
	_engine_time_process_ms = float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	_engine_time_physics_ms = float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	_rotate_section_frame()
	_last_attribution = _build_attribution_snapshot()
	_sample_memory()
	_push_frame_history(float(_frame_us) / 1000.0)
	_update_rate_counters()
	_frames_seen += 1


func _rotate_section_frame() -> void:
	# Close any open exclusive slices (shouldn't happen if begin/end balanced).
	var now := Time.get_ticks_usec()
	if not _section_stack.is_empty():
		var top: String = str(_section_stack.back())
		if _exclusive_open_us.has(top):
			_add_exclusive(top, now - int(_exclusive_open_us[top]))
		_section_stack.clear()
		_exclusive_open_us.clear()
	for key in _sections.keys():
		var s: Dictionary = _sections[key]
		var cur: int = int(s.get("cur_us", 0))
		s.last_us = cur
		if cur > int(s.get("max_us", 0)):
			s.max_us = cur
		s.last_exclusive_us = int(s.get("exclusive_us", 0))
		s.last_calls = int(s.get("calls", 0))
		s.cur_us = 0
		s.exclusive_us = 0
		s.calls = 0
		_sections[key] = s
	for key in _funcs.keys():
		var f: Dictionary = _funcs[key]
		var fcur: int = int(f.get("cur_us", 0))
		f.last_us = fcur
		if fcur > int(f.get("max_us", 0)):
			f.max_us = fcur
		f.last_calls = int(f.get("cur_calls", 0))
		f.cur_us = 0
		f.cur_calls = 0
		_funcs[key] = f


func _push_frame_history(frame_ms: float) -> void:
	if _frame_history_ms.size() >= HISTORY_LEN:
		# Shift left cheaply by rebuilding when full (HISTORY_LEN is small).
		var next := PackedFloat32Array()
		next.resize(HISTORY_LEN - 1)
		for i in range(1, _frame_history_ms.size()):
			next[i - 1] = _frame_history_ms[i]
		_frame_history_ms = next
	_frame_history_ms.append(frame_ms)
	if frame_ms > FRAME_BUDGET_MS:
		_spike_count += 1


func _sample_memory() -> void:
	# Godot 4 Performance monitors (bytes).
	var static_bytes := float(Performance.get_monitor(Performance.MEMORY_STATIC))
	var static_max := float(Performance.get_monitor(Performance.MEMORY_STATIC_MAX))
	_mem_current_mb = static_bytes / (1024.0 * 1024.0)
	_mem_peak_mb = maxf(_mem_peak_mb, static_max / (1024.0 * 1024.0))
	set_gauge("mem_current_mb", _mem_current_mb)
	set_gauge("mem_peak_mb", _mem_peak_mb)


var _monitors_registered: bool = false
## Monitor ids registered with Performance — must be removed before autoload free
## or Godot double-frees the Callable lambdas on engine shutdown
## ("double free or corruption (!prev)" / "free(): invalid pointer").
const _MONITOR_SECTIONS := [
	"main_thread", "worker_total",
	"chunk_mesh", "chunk_buffer", "chunk_upload", "chunk_column", "chunk_apply",
	"stream_schedule",
	"crystal_sim", "crystal_mesh",
	"map_build", "entity_physics", "entity_navigation", "entity_combat",
	"vegetation_growth", "debug_panel", "ui_overlay",
	"crystal_cells", "crystal_new_cells", "crystal_changed_cells",
]


func _exit_tree() -> void:
	# Drop custom monitors while this node is still valid. Leaving lambdas
	# registered in Performance after PerfProfiler is freed corrupts the heap
	# on quit (proven: register→crash, register+remove→clean).
	_unregister_monitors()


func _register_monitors() -> void:
	if _monitors_registered:
		return
	_monitors_registered = true
	for n in _MONITOR_SECTIONS:
		var key := "crystalstorm/%s_ms" % n
		if Performance.has_custom_monitor(key):
			continue
		Performance.add_custom_monitor(key, _make_monitor_callback(n))


func _unregister_monitors() -> void:
	if not _monitors_registered:
		# Still best-effort clear in case flag desynced.
		pass
	for n in _MONITOR_SECTIONS:
		var key := "crystalstorm/%s_ms" % n
		if Performance.has_custom_monitor(key):
			Performance.remove_custom_monitor(key)
	_monitors_registered = false


func _make_monitor_callback(section: String) -> Callable:
	if section == "main_thread":
		return func() -> float:
			return float(_frame_us) / 1000.0
	if section == "worker_total":
		return func() -> float:
			return float(_worker_frame_us) / 1000.0
	if section in ["crystal_cells", "crystal_new_cells", "crystal_changed_cells"]:
		return func() -> float:
			return float(_gauges.get(section, 0.0))
	return func() -> float:
		var s: Dictionary = _sections.get(section, {})
		return float(s.get("last_us", 0)) / 1000.0


func set_gauge(name: String, value: float) -> void:
	if not enabled:
		return
	_gauges[name] = value


## Worker job completion hook — tracks avg/longest job (ms).
func note_worker_job_ms(job_ms: float) -> void:
	if not enabled or job_ms <= 0.0:
		return
	var n: float = float(_gauges.get("worker_job_samples", 0.0))
	var avg: float = float(_gauges.get("worker_avg_job_ms", 0.0))
	var new_n: float = n + 1.0
	_gauges["worker_job_samples"] = new_n
	_gauges["worker_avg_job_ms"] = (avg * n + job_ms) / new_n
	_gauges["worker_longest_job_ms"] = maxf(float(_gauges.get("worker_longest_job_ms", 0.0)), job_ms)


func inc_frame(counter: String, amount: int = 1) -> void:
	if not enabled:
		return
	_frame_counters[counter] = int(_frame_counters.get(counter, 0)) + amount


func inc_rate(counter: String, amount: int = 1) -> void:
	if not enabled:
		return
	_rate_accum[counter] = int(_rate_accum.get(counter, 0)) + amount


func _update_rate_counters() -> void:
	var now := Time.get_ticks_msec()
	if _rate_last_msec <= 0:
		_rate_last_msec = now
		return
	var elapsed := now - _rate_last_msec
	if elapsed < 1000:
		return
	for key in _rate_accum.keys():
		_rate_per_sec[key] = float(_rate_accum[key]) * 1000.0 / float(elapsed)
	_rate_accum.clear()
	_rate_last_msec = now


func sample_scene_stats(tree: SceneTree) -> void:
	if not enabled or tree == null:
		return
	var mm_nodes := 0
	var mm_instances := 0
	var mesh_instances := 0
	var material_ids: Dictionary = {}
	var texture_ids: Dictionary = {}
	var ai_count := 0

	var walk_root: Node = tree.root.get_node_or_null("Game")
	if walk_root == null:
		walk_root = tree.root
	var stack: Array[Node] = [walk_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is MultiMeshInstance3D:
			mm_nodes += 1
			var mm_i: MultiMeshInstance3D = node as MultiMeshInstance3D
			var mm: MultiMesh = mm_i.multimesh
			mm_instances += mm.instance_count if mm else 0
			_register_render_material(material_ids, texture_ids, mm_i.material_override)
		elif node is MeshInstance3D:
			mesh_instances += 1
			var mi: MeshInstance3D = node as MeshInstance3D
			var mi_mat: Material = mi.material_override
			if mi_mat == null and mi.mesh and mi.mesh.get_surface_count() > 0:
				mi_mat = mi.mesh.surface_get_material(0)
			_register_render_material(material_ids, texture_ids, mi_mat)
		elif node is Sprite3D:
			var spr: Sprite3D = node as Sprite3D
			_register_render_material(material_ids, texture_ids, spr.material_override)
		if node.is_in_group("world_entity") or node.is_in_group("crystal_enemy"):
			ai_count += 1

	var chunk_manager = tree.get_first_node_in_group("chunk_manager")
	var chunks_visible := 0
	if chunk_manager != null:
		if chunk_manager.has_method("get_chunk_count"):
			chunks_visible = chunk_manager.get_chunk_count()
		elif "chunks" in chunk_manager:
			var chunks_prop = chunk_manager.get("chunks")
			if chunks_prop is Dictionary:
				chunks_visible = chunks_prop.size()

	_scene_stats = {
		"multimesh_nodes": mm_nodes,
		"multimesh_instances": mm_instances,
		"mesh_instances": mesh_instances,
		"texture_bindings": texture_ids.size(),
		"unique_materials": material_ids.size(),
		"draw_calls": float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects_in_frame": float(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"primitives_in_frame": float(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
	}
	set_gauge("chunks_visible", float(chunks_visible))
	set_gauge("ai_count", float(ai_count))


func _register_render_material(
	material_ids: Dictionary,
	texture_ids: Dictionary,
	mat: Material
) -> void:
	if mat == null:
		return
	material_ids[mat.get_instance_id()] = true
	if mat is ShaderMaterial:
		var shader_mat := mat as ShaderMaterial
		var shader: Shader = shader_mat.shader
		if shader == null:
			return
		for uni_variant in shader.get_shader_uniform_list():
			var uni: Dictionary = uni_variant
			var uname: String = str(uni.get("name", ""))
			var val: Variant = shader_mat.get_shader_parameter(uname)
			if val is Texture2D:
				texture_ids[(val as Texture2D).get_instance_id()] = true
	elif mat is StandardMaterial3D:
		var std := mat as StandardMaterial3D
		for tex in [std.albedo_texture, std.normal_texture, std.orm_texture]:
			if tex is Texture2D:
				texture_ids[tex.get_instance_id()] = true


func _section_ms(name: String) -> float:
	var s: Dictionary = _sections.get(name, {})
	return float(s.get("last_us", 0)) / 1000.0


func _history_stats() -> Dictionary:
	if _frame_history_ms.is_empty():
		return {"avg_ms": 0.0, "max_ms": 0.0, "p95_ms": 0.0, "spike_pct": 0.0}
	var sum := 0.0
	var mx := 0.0
	var sorted: Array = []
	for i in _frame_history_ms.size():
		var v: float = _frame_history_ms[i]
		sum += v
		mx = maxf(mx, v)
		sorted.append(v)
	sorted.sort()
	var p95_i := clampi(int(floor(float(sorted.size() - 1) * 0.95)), 0, sorted.size() - 1)
	var spikes := 0
	for v2 in sorted:
		if float(v2) > FRAME_BUDGET_MS:
			spikes += 1
	return {
		"avg_ms": sum / float(sorted.size()),
		"max_ms": mx,
		"p95_ms": float(sorted[p95_i]),
		"spike_pct": 100.0 * float(spikes) / float(sorted.size()),
	}


func is_worker_section(section: String) -> bool:
	return WORKER_STAGE_SECTIONS.has(section) or bool(_sections.get(section, {}).get("worker", false))


## Ranked list of hottest *main-thread* sections last frame (ms desc).
func get_bottlenecks(limit: int = 5) -> Array:
	var rows: Array = []
	for key in _sections.keys():
		if is_worker_section(str(key)):
			continue
		var ms := _section_ms(str(key))
		if ms < 0.05:
			continue
		rows.append({"name": str(key), "ms": ms})
	rows.sort_custom(func(a, b): return float(a.ms) > float(b.ms))
	if rows.size() > limit:
		return rows.slice(0, limit)
	return rows


## Hottest functions by last-frame ms (and max for hitch hunting).
func get_hot_functions(limit: int = 10, by_max: bool = false) -> Array:
	var rows: Array = []
	for key in _funcs.keys():
		var f: Dictionary = _funcs[key]
		var last_ms := float(f.get("last_us", 0)) / 1000.0
		var max_ms := float(f.get("max_us", 0)) / 1000.0
		var score := max_ms if by_max else last_ms
		if score < 0.05 and last_ms < 0.05:
			continue
		rows.append({
			"name": str(key),
			"ms": last_ms,
			"max_ms": max_ms,
			"calls": int(f.get("last_calls", 0)),
			"total_ms": float(f.get("total_us", 0)) / 1000.0,
		})
	if by_max:
		rows.sort_custom(func(a, b): return float(a.max_ms) > float(b.max_ms))
	else:
		rows.sort_custom(func(a, b): return float(a.ms) > float(b.ms))
	if rows.size() > limit:
		return rows.slice(0, limit)
	return rows


## Main-thread attribution ms last frame (excludes worker-stage sections).
func get_main_tracked_ms() -> float:
	var tracked := 0
	for key in _sections.keys():
		if is_worker_section(str(key)):
			continue
		tracked += int(_sections[key].get("last_us", 0))
	return float(tracked) / 1000.0


func get_main_untracked_ms() -> float:
	return maxf(float(_frame_us) / 1000.0 - get_main_tracked_ms(), 0.0)


func get_runtime_report() -> Dictionary:
	var snap := get_snapshot()
	var secs: Dictionary = snap.sections
	var chunk_mesh_ms := float(secs.get("chunk_mesh", {}).get("last_ms", 0.0))
	var chunk_upload_ms := float(secs.get("chunk_upload", {}).get("last_ms", 0.0))
	var chunk_column_ms := float(secs.get("chunk_column", {}).get("last_ms", 0.0))
	var chunk_buffer_ms := float(secs.get("chunk_buffer", {}).get("last_ms", 0.0))
	var chunk_apply_ms := float(secs.get("chunk_apply", {}).get("last_ms", 0.0))
	var stream_sched_ms := float(secs.get("stream_schedule", {}).get("last_ms", 0.0))
	var crystal_ms := float(secs.get("crystal_sim", {}).get("last_ms", 0.0))
	var crystal_mesh_ms := float(secs.get("crystal_mesh", {}).get("last_ms", 0.0))
	var entity_ms := float(secs.get("entity_physics", {}).get("last_ms", 0.0))
	var nav_ms := float(secs.get("entity_navigation", {}).get("last_ms", 0.0))
	var combat_ms := float(secs.get("entity_combat", {}).get("last_ms", 0.0))
	var ui_ms := float(secs.get("debug_panel", {}).get("last_ms", 0.0))
	ui_ms += float(secs.get("ui_overlay", {}).get("last_ms", 0.0))
	var terrain_queries := int(_report_frame_counters.get("terrain_queries", 0))
	if terrain_queries <= 0:
		terrain_queries = int(_frame_counters.get("terrain_queries", 0))
	var terrain_edits := int(_report_frame_counters.get("terrain_edits", 0))
	if terrain_edits <= 0:
		terrain_edits = int(_frame_counters.get("terrain_edits", 0))
	var dirty_regions := int(_gauges.get("dirty_regions", 0.0))
	if dirty_regions <= 0:
		dirty_regions = int(_report_frame_counters.get("dirty_regions", 0))
	var hist := _history_stats()
	var bottlenecks := get_bottlenecks(5)
	return {
		"frame": {
			"fps": float(Engine.get_frames_per_second()),
			"frame_ms": float(snap.frame_ms),
			"budget_ms": FRAME_BUDGET_MS,
			"over_budget": float(snap.frame_ms) > FRAME_BUDGET_MS,
			"avg_ms": float(hist.avg_ms),
			"max_ms": float(hist.max_ms),
			"p95_ms": float(hist.p95_ms),
			"spike_pct": float(hist.spike_pct),
			"untracked_ms": float(snap.untracked_ms),
			"main_tracked_ms": get_main_tracked_ms(),
			"engine_process_ms": _engine_time_process_ms,
			"engine_physics_ms": _engine_time_physics_ms,
		},
		"hot_functions": get_hot_functions(10, false),
		"hot_functions_by_max": get_hot_functions(10, true),
		"chunks": {
			"visible": int(_gauges.get("chunks_visible", 0.0)),
			"generated_per_sec": float(_rate_per_sec.get("chunks_generated", 0.0)),
			"rebuilt_per_sec": float(_rate_per_sec.get("chunks_rebuilt", 0.0)),
			"mesh_build_ms": chunk_mesh_ms,
			"snapshot_ms": float(secs.get("chunk_snapshot", {}).get("last_ms", 0.0)),
			"column_ms": chunk_column_ms,
			"buffer_ms": chunk_buffer_ms,
			"upload_ms": chunk_upload_ms,
			"apply_ms": chunk_apply_ms,
		},
		"streaming": {
			"schedule_ms": stream_sched_ms,
			"queue_depth": int(_gauges.get("stream_queue_depth", 0.0)),
			"mesh_queue_depth": int(_gauges.get("mesh_queue_depth", 0.0)),
			"inflight": int(_gauges.get("chunk_tasks_inflight", 0.0)),
			"apply_ms": chunk_apply_ms + chunk_upload_ms,
		},
		"crystal": {
			"update_ms": crystal_ms,
			"presentation_ms": crystal_mesh_ms,
			"cells_updated": float(_gauges.get("crystal_new_cells", 0.0)),
			"dirty_cells": float(_gauges.get("crystal_changed_cells", 0.0)),
			"frontier_size": float(_gauges.get("crystal_new_cells", 0.0)),
			"cells": float(_gauges.get("crystal_cells", 0.0)),
		},
		"entities": {
			"update_ms": entity_ms,
			"navigation_ms": nav_ms,
			"combat_ms": combat_ms,
			"ai_count": int(_gauges.get("ai_count", 0.0)),
		},
		"world": {
			"terrain_queries": terrain_queries,
			"terrain_edits": terrain_edits,
			"dirty_regions": dirty_regions,
			"features_ms": float(secs.get("world_features", {}).get("last_ms", 0.0)),
			"worldstate_ms": float(secs.get("world_state", {}).get("last_ms", 0.0)),
		},
		"render": {
			"draw_calls": int(_scene_stats.get("draw_calls", 0.0)),
			"multimesh_count": int(_scene_stats.get("multimesh_nodes", 0)),
			"visible_instances": int(_scene_stats.get("multimesh_instances", 0)),
			"primitives_in_frame": int(_scene_stats.get("primitives_in_frame", 0.0)),
			"texture_bindings": int(_scene_stats.get("texture_bindings", 0)),
			"unique_materials": int(_scene_stats.get("unique_materials", 0)),
			"chunk_upload_ms": chunk_upload_ms,
			"draw_prep_ms": float(secs.get("draw_prep", {}).get("last_ms", 0.0)),
		},
		"ui": {
			"update_ms": ui_ms,
		},
		"memory": {
			"current_mb": float(_gauges.get("mem_current_mb", _mem_current_mb)),
			"peak_mb": float(_gauges.get("mem_peak_mb", _mem_peak_mb)),
			"chunk_cache": int(_gauges.get("chunk_pool_free", 0.0)),
		},
		"workers": {
			"worker_ms": float(snap.worker_ms),
			"active": int(_gauges.get("workers_active", 0.0)),
			"queue_depth": int(_gauges.get("chunk_tasks_inflight", 0.0)),
			"avg_job_ms": float(_gauges.get("worker_avg_job_ms", 0.0)),
			"longest_job_ms": float(_gauges.get("worker_longest_job_ms", 0.0)),
		},
		"bottlenecks": bottlenecks,
	}


func format_runtime_report() -> String:
	return _format_runtime_report_v2(get_runtime_report())


func _format_runtime_report_v2(r: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	var frame_ms: float = float(r.frame.frame_ms)
	var over: String = " **OVER BUDGET**" if bool(r.frame.over_budget) else ""
	lines.append("FRAME")
	lines.append("FPS: %.0f" % float(r.frame.fps))
	lines.append("Frame Time (ms): %.2f%s" % [frame_ms, over])
	lines.append("Frame avg/p95/max: %.2f / %.2f / %.2f  spikes %.1f%%" % [
		float(r.frame.avg_ms), float(r.frame.p95_ms), float(r.frame.max_ms), float(r.frame.spike_pct)
	])
	lines.append("Untracked (ms): %.2f" % float(r.frame.untracked_ms))
	lines.append("CHUNKS")
	lines.append("Chunks Visible: %d" % int(r.chunks.visible))
	lines.append("Chunks Generated/sec: %.1f" % float(r.chunks.generated_per_sec))
	lines.append("Chunks Rebuilt/sec: %.1f" % float(r.chunks.rebuilt_per_sec))
	lines.append("Mesh Build Time (ms): %.2f" % float(r.chunks.mesh_build_ms))
	lines.append("Snapshot/Column/Buffer (ms): %.2f / %.2f / %.2f" % [
		float(r.chunks.snapshot_ms), float(r.chunks.column_ms), float(r.chunks.buffer_ms)
	])
	lines.append("Upload/Apply (ms): %.2f / %.2f" % [float(r.chunks.upload_ms), float(r.chunks.apply_ms)])
	lines.append("STREAMING")
	lines.append("Schedule (ms): %.2f  queue %d  meshQ %d  inflight %d" % [
		float(r.streaming.schedule_ms), int(r.streaming.queue_depth),
		int(r.streaming.mesh_queue_depth), int(r.streaming.inflight),
	])
	lines.append("CRYSTAL")
	lines.append("Crystal Update Time: %.2f ms" % float(r.crystal.update_ms))
	lines.append("Presentation (ms): %.2f" % float(r.crystal.presentation_ms))
	lines.append("Cells Updated: %.0f" % float(r.crystal.cells_updated))
	lines.append("Dirty Cells: %.0f" % float(r.crystal.dirty_cells))
	lines.append("Frontier Size: %.0f" % float(r.crystal.frontier_size))
	lines.append("ENTITIES")
	lines.append("Entity Update Time: %.2f ms" % float(r.entities.update_ms))
	lines.append("Navigation Time (ms): %.2f" % float(r.entities.navigation_ms))
	lines.append("Combat (ms): %.2f" % float(r.entities.combat_ms))
	lines.append("AI Count: %d" % int(r.entities.ai_count))
	lines.append("WORLD")
	lines.append("Terrain Query Count: %d" % int(r.world.terrain_queries))
	lines.append("Terrain Edits: %d" % int(r.world.terrain_edits))
	lines.append("Dirty Regions: %d" % int(r.world.dirty_regions))
	lines.append("RENDER")
	lines.append("Draw Calls: %d" % int(r.render.draw_calls))
	lines.append("MultiMesh Nodes: %d" % int(r.render.multimesh_count))
	lines.append("Visible Instances: %d" % int(r.render.visible_instances))
	lines.append("Primitives/Frame: %d" % int(r.render.primitives_in_frame))
	lines.append("Texture Bindings: %d" % int(r.render.texture_bindings))
	lines.append("Unique Materials: %d" % int(r.render.unique_materials))
	lines.append("Chunk Upload (ms): %.2f" % float(r.render.chunk_upload_ms))
	lines.append("UI")
	lines.append("UI Update (ms): %.2f" % float(r.ui.update_ms))
	lines.append("MEMORY")
	lines.append("Current (MB): %.2f" % float(r.memory.current_mb))
	lines.append("Peak (MB): %.2f" % float(r.memory.peak_mb))
	lines.append("Chunk Cache Free: %d" % int(r.memory.chunk_cache))
	lines.append("WORKERS")
	lines.append("Worker Total (ms): %.2f" % float(r.workers.worker_ms))
	lines.append("Active Workers: %d" % int(r.workers.active))
	lines.append("Queue Depth: %d" % int(r.workers.queue_depth))
	lines.append("Avg Job (ms): %.2f" % float(r.workers.avg_job_ms))
	lines.append("Longest Job (ms): %.2f" % float(r.workers.longest_job_ms))
	var bots: Array = r.get("bottlenecks", [])
	if not bots.is_empty():
		lines.append("HOTTEST")
		for b in bots:
			lines.append("  %s: %.2f ms" % [str(b.get("name", "?")), float(b.get("ms", 0.0))])
	var hots: Array = r.get("hot_functions", [])
	if not hots.is_empty():
		lines.append("HOT FUNCTIONS")
		for h in hots:
			lines.append("  %s: %.2f ms (max %.2f, n=%d)" % [
				str(h.get("name", "?")), float(h.get("ms", 0.0)),
				float(h.get("max_ms", 0.0)), int(h.get("calls", 0)),
			])
	lines.append("Main tracked (ms): %.2f" % float(r.frame.get("main_tracked_ms", 0.0)))
	lines.append("Engine process/physics (ms): %.2f / %.2f" % [
		float(r.frame.get("engine_process_ms", 0.0)),
		float(r.frame.get("engine_physics_ms", 0.0)),
	])
	# Frame budget queues (Phase 3)
	var fbs = Engine.get_main_loop()
	if fbs is SceneTree:
		var sched = (fbs as SceneTree).root.get_node_or_null("/root/FrameBudgetScheduler")
		if sched and sched.has_method("format_budget_report"):
			lines.append(sched.format_budget_report())
	return "\n".join(lines)


func record_worker_us(elapsed_us: int) -> void:
	if not enabled or elapsed_us <= 0:
		return
	_worker_us += elapsed_us


func _ensure_section(section: String) -> Dictionary:
	if _sections.has(section):
		return _sections[section]
	var s := {
		"active": 0,
		"total_us": 0,
		"last_us": 0,
		"cur_us": 0,
		"max_us": 0,
		"start": 0,
		"exclusive_us": 0,
		"last_exclusive_us": 0,
		"calls": 0,
		"last_calls": 0,
		"worker": WORKER_STAGE_SECTIONS.has(section),
	}
	_sections[section] = s
	return s


## Single exclusive path: only the named section receives exclusive time.
## No remap / divert / promote to a different section name.
func _add_exclusive(section: String, us: int) -> void:
	if us <= 0:
		return
	var s: Dictionary = _ensure_section(section)
	s.exclusive_us = int(s.get("exclusive_us", 0)) + us
	_sections[section] = s


func begin(section: String) -> void:
	if not enabled:
		return
	var now := Time.get_ticks_usec()
	# Pause parent exclusive slice.
	if not _section_stack.is_empty():
		var parent: String = str(_section_stack.back())
		if _exclusive_open_us.has(parent):
			_add_exclusive(parent, now - int(_exclusive_open_us[parent]))
			_exclusive_open_us.erase(parent)
	var s: Dictionary = _ensure_section(section)
	s.active = int(s.active) + 1
	s.start = now
	s.calls = int(s.get("calls", 0)) + 1
	_sections[section] = s
	_section_stack.append(section)
	_exclusive_open_us[section] = now


func record_us(section: String, elapsed_us: int) -> void:
	if not enabled or elapsed_us <= 0:
		return
	var now := Time.get_ticks_usec()
	# Leaf record: pause parent exclusive so we don't double-count wall into parent.
	var parent := ""
	if not _section_stack.is_empty():
		parent = str(_section_stack.back())
		if _exclusive_open_us.has(parent):
			_add_exclusive(parent, now - int(_exclusive_open_us[parent]))
			_exclusive_open_us.erase(parent)
	var s: Dictionary = _ensure_section(section)
	s.cur_us = int(s.get("cur_us", 0)) + elapsed_us
	s.total_us = int(s.total_us) + elapsed_us
	s.last_us = int(s.cur_us)
	s.max_us = maxi(int(s.max_us), elapsed_us)
	s.exclusive_us = int(s.get("exclusive_us", 0)) + elapsed_us
	s.calls = int(s.get("calls", 0)) + 1
	if WORKER_STAGE_SECTIONS.has(section):
		s.worker = true
	_sections[section] = s
	if parent != "":
		_exclusive_open_us[parent] = Time.get_ticks_usec()


## Attribute completed worker-stage time (does not reduce main untracked).
func record_worker_stage(section: String, elapsed_us: int) -> void:
	if not enabled or elapsed_us <= 0:
		return
	var s: Dictionary = _ensure_section(section)
	s.worker = true
	s.cur_us = int(s.get("cur_us", 0)) + elapsed_us
	s.total_us = int(s.total_us) + elapsed_us
	s.last_us = int(s.cur_us)
	s.max_us = maxi(int(s.max_us), elapsed_us)
	# Worker exclusive is tracked separately and excluded from main wall %.
	s.exclusive_us = int(s.get("exclusive_us", 0)) + elapsed_us
	s.calls = int(s.get("calls", 0)) + 1
	_sections[section] = s
	record_worker_us(elapsed_us)


func end(section: String) -> void:
	if not enabled:
		return
	var s: Dictionary = _sections.get(section, {})
	if int(s.get("active", 0)) <= 0:
		return
	var now := Time.get_ticks_usec()
	var elapsed: int = now - int(s.get("start", 0))
	# Exclusive slice for this section first (mutates _sections[section]).
	if _exclusive_open_us.has(section):
		_add_exclusive(section, now - int(_exclusive_open_us[section]))
		_exclusive_open_us.erase(section)
	s = _sections.get(section, s)
	s.active = int(s.active) - 1
	s.cur_us = int(s.get("cur_us", 0)) + elapsed
	s.total_us = int(s.total_us) + elapsed
	s.last_us = int(s.cur_us)
	s.max_us = maxi(int(s.max_us), elapsed)
	_sections[section] = s
	# Pop stack (tolerate mis-order by scanning).
	if not _section_stack.is_empty() and str(_section_stack.back()) == section:
		_section_stack.pop_back()
	else:
		var idx := _section_stack.rfind(section)
		if idx >= 0:
			_section_stack.remove_at(idx)
	# Resume parent exclusive.
	if not _section_stack.is_empty():
		var parent: String = str(_section_stack.back())
		_exclusive_open_us[parent] = Time.get_ticks_usec()


## Function-level hotspot (e.g. "ChunkManager::_on_chunk_ready").
func begin_func(func_name: String) -> void:
	if not enabled:
		return
	var f: Dictionary = _funcs.get(func_name, {
		"active": 0, "start": 0, "cur_us": 0, "last_us": 0, "max_us": 0,
		"total_us": 0, "cur_calls": 0, "last_calls": 0,
	})
	f.active = int(f.active) + 1
	f.start = Time.get_ticks_usec()
	_funcs[func_name] = f


func end_func(func_name: String) -> void:
	if not enabled:
		return
	var f: Dictionary = _funcs.get(func_name, {})
	if int(f.get("active", 0)) <= 0:
		return
	var elapsed: int = Time.get_ticks_usec() - int(f.get("start", 0))
	f.active = int(f.active) - 1
	f.cur_us = int(f.get("cur_us", 0)) + elapsed
	f.total_us = int(f.get("total_us", 0)) + elapsed
	f.last_us = int(f.cur_us)
	f.max_us = maxi(int(f.get("max_us", 0)), elapsed)
	f.cur_calls = int(f.get("cur_calls", 0)) + 1
	_funcs[func_name] = f


func record_func(func_name: String, elapsed_us: int) -> void:
	if not enabled or elapsed_us <= 0:
		return
	var f: Dictionary = _funcs.get(func_name, {
		"active": 0, "start": 0, "cur_us": 0, "last_us": 0, "max_us": 0,
		"total_us": 0, "cur_calls": 0, "last_calls": 0,
	})
	f.cur_us = int(f.get("cur_us", 0)) + elapsed_us
	f.total_us = int(f.get("total_us", 0)) + elapsed_us
	f.last_us = int(f.cur_us)
	f.max_us = maxi(int(f.get("max_us", 0)), elapsed_us)
	f.cur_calls = int(f.get("cur_calls", 0)) + 1
	_funcs[func_name] = f


func scope(section: String) -> RefCounted:
	return _Scope.new(self, section)


func scope_func(func_name: String) -> RefCounted:
	return _FuncScope.new(self, func_name)


func get_snapshot() -> Dictionary:
	var main_us := _frame_us
	var worker_us := _worker_frame_us
	# Inclusive sum (legacy; may double-count nested). Prefer exclusive / attribution.
	var tracked_main := 0
	var exclusive_main := 0
	for key in _sections.keys():
		if is_worker_section(str(key)):
			continue
		tracked_main += int(_sections[key].get("last_us", 0))
		exclusive_main += int(_sections[key].get("last_exclusive_us", 0))
	var untracked := maxi(main_us - exclusive_main, 0)
	var attr: Dictionary = _last_attribution if not _last_attribution.is_empty() else _build_attribution_snapshot()
	return {
		"frame_ms": float(main_us) / 1000.0,
		"worker_ms": float(worker_us) / 1000.0,
		"untracked_ms": float(untracked) / 1000.0,
		"main_tracked_ms": float(exclusive_main) / 1000.0,
		"main_tracked_inclusive_ms": float(tracked_main) / 1000.0,
		"sections": _snapshot_sections(),
		"funcs": _snapshot_funcs(),
		"frame_counters": _report_frame_counters.duplicate(),
		"scene_stats": _scene_stats.duplicate(),
		"gauges": _gauges.duplicate(),
		"engine_process_ms": _engine_time_process_ms,
		"engine_physics_ms": _engine_time_physics_ms,
		"attribution": attr,
	}


## Full main-thread wall attribution for the last completed frame.
## Named exclusive leaf call sites only; residual is Unknown. Denominator = full_wall_us.
func get_attribution() -> Dictionary:
	if not _last_attribution.is_empty():
		return _last_attribution.duplicate(true)
	return _build_attribution_snapshot()


## Legacy MainLoop_* names are never gate=named (forbidden residual dumps).
## Live path uses physics_callbacks / process_callbacks with real begin/end instead.
const ENVELOPE_SECTIONS := {
	"MainLoop_process": true,
	"MainLoop_physics": true,
	"MainLoop_deferred": true,
	"MainLoop_idle": true,
}
## Names forbidden as gate=named (residual dumps). physics_callbacks / process_callbacks
## are ordinary named sections with real begin/end call sites — not listed here.
const FORBIDDEN_NAMED_SECTIONS := {
	"Unknown": true,
	"Engine_process_unscoped": true,
	"Engine_physics_unscoped": true,
	"Engine_idle_or_message_queue": true,
	"Main_thread_waiting": true,
	"Main_thread_waiting_untracked": true,
	"MainLoop_process": true,
	"MainLoop_physics": true,
	"MainLoop_deferred": true,
	"MainLoop_idle": true,
	"physics_server_step": true,
}

## Last inter-frame gap (usec) after previous finalize until next phase start.
## Not part of full_wall; diagnostic only.
var _last_inter_frame_gap_us: int = 0
var _frame_work_started: bool = false


## Mark the start of this frame's main-thread work window (first physics/process).
## Call after closing any inter-frame gap. Measurement only.
func mark_frame_work_start() -> void:
	if not enabled:
		return
	if _frame_work_started:
		return
	_frame_start = Time.get_ticks_usec()
	_frame_work_started = true


## Record pure inter-frame gap (not main-thread work). Does not enter section map.
func note_inter_frame_gap_us(gap_us: int) -> void:
	if gap_us > 0:
		_last_inter_frame_gap_us = gap_us


## Pure attribution contract (unit-testable). No wall shrinking, no residual renames.
## section_map: name -> {exclusive_us, calls?, worker?}
## Returns categories + named/unknown against full_wall_us only.
## Stateless w.r.t. instance fields — safe to call on autoload for unit tests.
func account_main_thread_frame(section_map: Dictionary, full_wall_us: int) -> Dictionary:
	var wall: int = maxi(full_wall_us, 1)
	var categories: Dictionary = {}
	var named_us := 0
	var envelope_residual_us := 0
	for key in section_map.keys():
		var raw = section_map[key]
		var ex := 0
		var calls := 0
		var worker := false
		if raw is Dictionary:
			# Prefer exclusive only. Do not fall back to inclusive last_us for
			# envelopes (inclusive would double-count nested leaves into Unknown).
			if raw.has("exclusive_us") or raw.has("last_exclusive_us"):
				ex = int(raw.get("exclusive_us", raw.get("last_exclusive_us", 0)))
			else:
				ex = int(raw.get("last_us", raw.get("us", 0)))
			calls = int(raw.get("calls", raw.get("last_calls", 0)))
			worker = bool(raw.get("worker", false))
		else:
			ex = int(raw)
		if worker or WORKER_STAGE_SECTIONS.has(str(key)):
			continue
		if ex <= 0:
			continue
		var name: String = str(key)
		var entry := {
			"ms": float(ex) / 1000.0,
			"exclusive_us": ex,
			"calls": calls,
			"worker": false,
		}
		if ENVELOPE_SECTIONS.has(name) or FORBIDDEN_NAMED_SECTIONS.has(name):
			# Phase bracket exclusive remainder — diagnostic only; counts in Unknown.
			envelope_residual_us += ex
			entry["gate"] = "unknown_envelope_residual"
			categories[name] = entry
			continue
		named_us += ex
		entry["gate"] = "named"
		categories[name] = entry
	# Cap named to wall (mis-nested timers must not invent >100%).
	if named_us > wall:
		named_us = wall
	var unknown_us: int = maxi(0, wall - named_us)
	if unknown_us > 0:
		categories["Unknown"] = {
			"ms": float(unknown_us) / 1000.0,
			"exclusive_us": unknown_us,
			"calls": 0,
			"worker": false,
			"gate": "unknown",
			"envelope_residual_us": envelope_residual_us,
		}
	var named_pct: float = 100.0 * float(named_us) / float(wall)
	var unknown_pct: float = 100.0 * float(unknown_us) / float(wall)
	return {
		"wall_us": wall,
		"wall_ms": float(wall) / 1000.0,
		"named_us": named_us,
		"named_ms": float(named_us) / 1000.0,
		"named_pct": named_pct,
		"unknown_us": unknown_us,
		"unknown_ms": float(unknown_us) / 1000.0,
		"unknown_pct": unknown_pct,
		"envelope_residual_us": envelope_residual_us,
		"categories": categories,
		"gate_wall": "full_wall_us",
	}


func _build_attribution_snapshot() -> Dictionary:
	## Denominator = full_wall_us (frame work window only; see mark_frame_work_start).
	## Named = exclusive times for sections with real begin/end (or record_us) only.
	## No remapping: raw section_map is what account_main_thread_frame sees.
	## Unknown = max(0, full_wall − named). MainLoop_* if present → envelope residual.
	var full_wall_us: int = maxi(_frame_us, 1)
	var section_map: Dictionary = {}
	for key in _sections.keys():
		var s: Dictionary = _sections[key]
		section_map[key] = {
			"exclusive_us": int(s.get("last_exclusive_us", 0)),
			"last_us": int(s.get("last_us", 0)),
			"calls": int(s.get("last_calls", 0)),
			"worker": bool(s.get("worker", false)),
		}
	var acct: Dictionary = account_main_thread_frame(section_map, full_wall_us)
	var categories: Dictionary = acct.get("categories", {})
	var named_us: int = int(acct.get("named_us", 0))
	var unknown_us: int = int(acct.get("unknown_us", 0))
	var worst_site := ""
	var worst_site_ms := 0.0
	for fk in _funcs.keys():
		var fms: float = float(_funcs[fk].get("last_us", 0)) / 1000.0
		if fms > worst_site_ms:
			worst_site_ms = fms
			worst_site = str(fk)
	return {
		"wall_ms": float(full_wall_us) / 1000.0,
		"wall_us": full_wall_us,
		"named_ms": float(named_us) / 1000.0,
		"named_pct": float(acct.get("named_pct", 0.0)),
		"unknown_ms": float(unknown_us) / 1000.0,
		"unknown_pct": float(acct.get("unknown_pct", 0.0)),
		"inter_frame_gap_ms": float(_last_inter_frame_gap_us) / 1000.0,
		"section_map": section_map.duplicate(true),
		"gdscript_exclusive_ms": float(named_us) / 1000.0,
		"engine_process_ms": _engine_time_process_ms,
		"engine_physics_ms": _engine_time_physics_ms,
		"hints": {
			"engine_time_process_ms": _engine_time_process_ms,
			"engine_time_physics_ms": _engine_time_physics_ms,
			"gate_wall": "full_wall_us",
			"named_policy": "exclusive_from_begin_end_record_us_only",
			"envelope_policy": "MainLoop_* if present → Unknown; no remapping",
		},
		"categories": categories,
		"worst_call_site": worst_site,
		"worst_call_site_ms": worst_site_ms,
		"worker_ms": float(_worker_frame_us) / 1000.0,
		"frame_counters": _report_frame_counters.duplicate(),
		"funcs": _snapshot_funcs(),
	}


func _snapshot_funcs() -> Dictionary:
	var out := {}
	for key in _funcs.keys():
		var f: Dictionary = _funcs[key]
		out[key] = {
			"last_ms": float(f.get("last_us", 0)) / 1000.0,
			"max_ms": float(f.get("max_us", 0)) / 1000.0,
			"calls": int(f.get("last_calls", 0)),
			"total_ms": float(f.get("total_us", 0)) / 1000.0,
		}
	return out


func _snapshot_sections() -> Dictionary:
	var out := {}
	for key in _sections.keys():
		var s: Dictionary = _sections[key]
		out[key] = {
			"last_ms": float(s.get("last_us", 0)) / 1000.0,
			"max_ms": float(s.get("max_us", 0)) / 1000.0,
			"exclusive_ms": float(s.get("last_exclusive_us", 0)) / 1000.0,
			"calls": int(s.get("last_calls", 0)),
			"worker": bool(s.get("worker", false)) or WORKER_STAGE_SECTIONS.has(str(key)),
		}
	return out


func format_debug_line() -> String:
	var snap := get_snapshot()
	var parts: PackedStringArray = []
	parts.append("main %.1fms" % snap.frame_ms)
	if float(snap.frame_ms) > FRAME_BUDGET_MS:
		parts.append("SPIKE")
	if float(snap.worker_ms) > 0.05:
		parts.append("worker %.1f" % snap.worker_ms)
	if float(snap.untracked_ms) > 0.5:
		parts.append("other %.1f" % snap.untracked_ms)
	var secs: Dictionary = snap.sections
	var cell_count: float = float(_gauges.get("crystal_cells", 0.0))
	if cell_count > 0.0:
		parts.append("cells %.0f" % cell_count)
	var new_cells: float = float(_gauges.get("crystal_new_cells", 0.0))
	if new_cells > 0.0:
		parts.append("new %.0f" % new_cells)
	var mesh_dirty: float = float(_gauges.get("crystal_changed_cells", 0.0))
	if mesh_dirty > 0.0:
		parts.append("mesh %.0f" % mesh_dirty)
	for key in [
		"chunk_upload", "chunk_mesh", "chunk_column", "stream_schedule",
		"crystal_sim", "crystal_mesh", "map_build", "entity_navigation",
	]:
		if secs.has(key):
			var e: Dictionary = secs[key]
			if float(e.last_ms) > 0.05:
				parts.append("%s %.1f" % [key, e.last_ms])
	var q: int = int(_gauges.get("mesh_queue_depth", 0.0))
	if q > 0:
		parts.append("meshQ %d" % q)
	return " | ".join(parts)


class _Scope:
	var _profiler: Node
	var _section: String

	func _init(profiler: Node, section: String) -> void:
		_profiler = profiler
		_section = section
		if _profiler:
			_profiler.begin(_section)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and _profiler:
			_profiler.end(_section)


class _FuncScope:
	var _profiler: Node
	var _fname: String

	func _init(profiler: Node, func_name: String) -> void:
		_profiler = profiler
		_fname = func_name
		if _profiler:
			_profiler.begin_func(_fname)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and _profiler:
			_profiler.end_func(_fname)
