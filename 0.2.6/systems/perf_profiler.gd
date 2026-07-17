extends Node
## Lightweight CPU profiler — shows up in Godot Monitor (Debugger → Monitors)
## and in the debug panel via get_snapshot().

var enabled: bool = true

var _sections: Dictionary = {}  # name -> {active: int, total_us: int, last_us: int, max_us: int}
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


func _enter_tree() -> void:
	add_to_group("perf_profiler")
	_frame_start = Time.get_ticks_usec()


func _ready() -> void:
	set_process(true)
	call_deferred("_register_monitors_if_in_game")


func _register_monitors_if_in_game() -> void:
	if get_tree().get_first_node_in_group("config_service") == null:
		return
	_register_monitors()


func _process(_delta: float) -> void:
	if not enabled:
		return
	_frame_us = Time.get_ticks_usec() - _frame_start
	_frame_start = Time.get_ticks_usec()
	_worker_frame_us = _worker_us
	_worker_us = 0
	_report_frame_counters = _frame_counters.duplicate()
	_frame_counters.clear()
	_update_rate_counters()


var _monitors_registered: bool = false


func _register_monitors() -> void:
	if _monitors_registered:
		return
	_monitors_registered = true
	var names := [
		"main_thread", "worker_total",
		"chunk_mesh", "chunk_buffer", "chunk_upload", "crystal_sim", "crystal_mesh",
		"map_build", "entity_physics", "entity_navigation", "vegetation_growth", "debug_panel",
		"crystal_cells", "crystal_new_cells", "crystal_changed_cells",
	]
	for n in names:
		var key := "crystalstorm/%s_ms" % n
		Performance.add_custom_monitor(key, _make_monitor_callback(n))


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


func get_runtime_report() -> Dictionary:
	var snap := get_snapshot()
	var secs: Dictionary = snap.sections
	var chunk_mesh_ms := float(secs.get("chunk_mesh", {}).get("last_ms", 0.0))
	var chunk_upload_ms := float(secs.get("chunk_upload", {}).get("last_ms", 0.0))
	var crystal_ms := float(secs.get("crystal_sim", {}).get("last_ms", 0.0))
	var entity_ms := float(secs.get("entity_physics", {}).get("last_ms", 0.0))
	var nav_ms := float(secs.get("entity_navigation", {}).get("last_ms", 0.0))
	var terrain_queries := int(_report_frame_counters.get("terrain_queries", 0))
	if terrain_queries <= 0:
		terrain_queries = int(_frame_counters.get("terrain_queries", 0))
	var terrain_edits := int(_report_frame_counters.get("terrain_edits", 0))
	if terrain_edits <= 0:
		terrain_edits = int(_frame_counters.get("terrain_edits", 0))
	var dirty_regions := int(_gauges.get("dirty_regions", 0.0))
	if dirty_regions <= 0:
		dirty_regions = int(_report_frame_counters.get("dirty_regions", 0))
	return {
		"frame": {
			"fps": float(Engine.get_frames_per_second()),
			"frame_ms": float(snap.frame_ms),
		},
		"chunks": {
			"visible": int(_gauges.get("chunks_visible", 0.0)),
			"generated_per_sec": float(_rate_per_sec.get("chunks_generated", 0.0)),
			"rebuilt_per_sec": float(_rate_per_sec.get("chunks_rebuilt", 0.0)),
			"mesh_build_ms": chunk_mesh_ms,
		},
		"crystal": {
			"update_ms": crystal_ms,
			"cells_updated": float(_gauges.get("crystal_new_cells", 0.0)),
			"dirty_cells": float(_gauges.get("crystal_changed_cells", 0.0)),
			"frontier_size": float(_gauges.get("crystal_new_cells", 0.0)),
		},
		"entities": {
			"update_ms": entity_ms,
			"navigation_ms": nav_ms,
			"ai_count": int(_gauges.get("ai_count", 0.0)),
		},
		"render": {
			"draw_calls": int(_scene_stats.get("draw_calls", 0.0)),
			"multimesh_count": int(_scene_stats.get("multimesh_nodes", 0)),
			"visible_instances": int(_scene_stats.get("multimesh_instances", 0)),
			"primitives_in_frame": int(_scene_stats.get("primitives_in_frame", 0.0)),
			"texture_bindings": int(_scene_stats.get("texture_bindings", 0)),
			"unique_materials": int(_scene_stats.get("unique_materials", 0)),
			"chunk_upload_ms": chunk_upload_ms,
		},
		"world": {
			"terrain_queries": terrain_queries,
			"terrain_edits": terrain_edits,
			"dirty_regions": dirty_regions,
		},
	}


func format_runtime_report() -> String:
	var r: Dictionary = get_runtime_report()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("FRAME")
	lines.append("FPS: %.0f" % float(r.frame.fps))
	lines.append("Frame Time (ms): %.2f" % float(r.frame.frame_ms))
	lines.append("CHUNKS")
	lines.append("Chunks Visible: %d" % int(r.chunks.visible))
	lines.append("Chunks Generated/sec: %.1f" % float(r.chunks.generated_per_sec))
	lines.append("Chunks Rebuilt/sec: %.1f" % float(r.chunks.rebuilt_per_sec))
	lines.append("Mesh Build Time (ms): %.2f" % float(r.chunks.mesh_build_ms))
	lines.append("CRYSTAL")
	lines.append("Crystal Update Time: %.2f ms" % float(r.crystal.update_ms))
	lines.append("Cells Updated: %.0f" % float(r.crystal.cells_updated))
	lines.append("Dirty Cells: %.0f" % float(r.crystal.dirty_cells))
	lines.append("Frontier Size: %.0f" % float(r.crystal.frontier_size))
	lines.append("ENTITIES")
	lines.append("Entity Update Time: %.2f ms" % float(r.entities.update_ms))
	lines.append("Navigation Time (ms): %.2f" % float(r.entities.navigation_ms))
	lines.append("AI Count: %d" % int(r.entities.ai_count))
	lines.append("RENDER")
	lines.append("Draw Calls: %d" % int(r.render.draw_calls))
	lines.append("MultiMesh Nodes: %d" % int(r.render.multimesh_count))
	lines.append("Visible Instances: %d" % int(r.render.visible_instances))
	lines.append("Primitives/Frame: %d" % int(r.render.primitives_in_frame))
	lines.append("Texture Bindings: %d" % int(r.render.texture_bindings))
	lines.append("Unique Materials: %d" % int(r.render.unique_materials))
	lines.append("Chunk Upload (ms): %.2f" % float(r.render.chunk_upload_ms))
	lines.append("WORLD")
	lines.append("Terrain Query Count: %d" % int(r.world.terrain_queries))
	lines.append("Terrain Edits: %d" % int(r.world.terrain_edits))
	lines.append("Dirty Regions: %d" % int(r.world.dirty_regions))
	return "\n".join(lines)


func record_worker_us(elapsed_us: int) -> void:
	if not enabled or elapsed_us <= 0:
		return
	_worker_us += elapsed_us


func begin(section: String) -> void:
	if not enabled:
		return
	var s: Dictionary = _sections.get(section, {
		"active": 0, "total_us": 0, "last_us": 0, "max_us": 0, "start": 0,
	})
	s.active = int(s.active) + 1
	s.start = Time.get_ticks_usec()
	_sections[section] = s


func record_us(section: String, elapsed_us: int) -> void:
	if not enabled or elapsed_us <= 0:
		return
	var s: Dictionary = _sections.get(section, {
		"active": 0, "total_us": 0, "last_us": 0, "max_us": 0, "start": 0,
	})
	s.last_us = int(s.get("last_us", 0)) + elapsed_us
	s.total_us = int(s.total_us) + elapsed_us
	s.max_us = maxi(int(s.max_us), elapsed_us)
	_sections[section] = s


func end(section: String) -> void:
	if not enabled:
		return
	var s: Dictionary = _sections.get(section, {})
	if int(s.get("active", 0)) <= 0:
		return
	var elapsed: int = Time.get_ticks_usec() - int(s.get("start", 0))
	s.active = int(s.active) - 1
	s.last_us = int(s.get("last_us", 0)) + elapsed
	s.total_us = int(s.total_us) + elapsed
	s.max_us = maxi(int(s.max_us), elapsed)
	_sections[section] = s


func scope(section: String) -> RefCounted:
	return _Scope.new(self, section)


func get_snapshot() -> Dictionary:
	var main_us := _frame_us
	var worker_us := _worker_frame_us
	var tracked_main := 0
	for key in _sections.keys():
		tracked_main += int(_sections[key].get("last_us", 0))
	var untracked := maxi(main_us - tracked_main, 0)
	return {
		"frame_ms": float(main_us) / 1000.0,
		"worker_ms": float(worker_us) / 1000.0,
		"untracked_ms": float(untracked) / 1000.0,
		"sections": _snapshot_sections(),
		"frame_counters": _report_frame_counters.duplicate(),
		"scene_stats": _scene_stats.duplicate(),
	}


func _snapshot_sections() -> Dictionary:
	var out := {}
	for key in _sections.keys():
		var s: Dictionary = _sections[key]
		out[key] = {
			"last_ms": float(s.get("last_us", 0)) / 1000.0,
			"max_ms": float(s.get("max_us", 0)) / 1000.0,
		}
	return out


func format_debug_line() -> String:
	var snap := get_snapshot()
	var parts: PackedStringArray = []
	parts.append("main %.1fms" % snap.frame_ms)
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
		"chunk_upload", "crystal_sim", "crystal_mesh", "map_build", "entity_navigation",
	]:
		if secs.has(key):
			var e: Dictionary = secs[key]
			if float(e.last_ms) > 0.05:
				parts.append("%s %.1f" % [key, e.last_ms])
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