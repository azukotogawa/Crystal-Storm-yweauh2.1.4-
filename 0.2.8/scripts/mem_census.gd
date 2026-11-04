extends RefCounted
## Rough memory census for item 12. Walks script variables and estimates bytes
## per owner. Numbers are estimates (Variant ~24 B, Dictionary entry ~80 B),
## good for ranking owners, not exact accounting.

const VARIANT_B := 24
const DICT_ENTRY_B := 80
const OBJ_B := 200

var _seen: Dictionary = {}
var _skip_fields: Dictionary = {"world": true, "_plan_world": true, "_plan_host": true, "_fill_world": true, "_fill_host": true, "macro_grid": true, "micro_grid": true}


func reset() -> void:
	_seen.clear()


static func packed_bytes(v) -> int:
	match typeof(v):
		TYPE_PACKED_BYTE_ARRAY: return v.size()
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY: return v.size() * 4
		TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT64_ARRAY: return v.size() * 8
		TYPE_PACKED_VECTOR2_ARRAY: return v.size() * 8
		TYPE_PACKED_VECTOR3_ARRAY: return v.size() * 12
		TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY: return v.size() * 16
		TYPE_PACKED_STRING_ARRAY:
			var n := 0
			for s in v:
				n += 32 + s.length() * 4
			return n
	return -1


## Bytes for a value. Shared objects are counted once per census (first owner wins).
func est(v, depth: int = 0) -> int:
	var pb := packed_bytes(v)
	if pb >= 0:
		return pb + 16
	match typeof(v):
		TYPE_STRING, TYPE_STRING_NAME:
			return 32 + str(v).length() * 4
		TYPE_ARRAY:
			var n: int = 16 + v.size() * VARIANT_B
			if depth < 8:
				for e in v:
					n += est_heap(e, depth + 1)
			return n
		TYPE_DICTIONARY:
			var n: int = 64 + v.size() * DICT_ENTRY_B
			if depth < 8:
				for k in v:
					n += est_heap(k, depth + 1) + est_heap(v[k], depth + 1)
			return n
		TYPE_OBJECT:
			return est_object(v, depth)
	return 0


## Heap bytes beyond the Variant slot itself.
func est_heap(v, depth: int) -> int:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_COLOR, TYPE_RECT2I, TYPE_RECT2, TYPE_RID:
			return 0
	return est(v, depth)


func est_object(o, depth: int) -> int:
	if o == null or not is_instance_valid(o):
		return 0
	if o is Node:
		return 0
	var id: int = o.get_instance_id()
	if _seen.has(id):
		return 0
	_seen[id] = true
	if o.get_script() == null:
		return OBJ_B
	if depth >= 8:
		return OBJ_B
	var n := OBJ_B
	for p in o.get_property_list():
		if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		if _skip_fields.has(p.name):
			continue
		n += est_heap(o.get(p.name), depth + 1)
	return n


## Per-field bytes of one object's script vars, added into acc[prefix + field].
func fields_into(o, prefix: String, acc: Dictionary) -> void:
	if o == null or not is_instance_valid(o):
		return
	var id: int = o.get_instance_id()
	if _seen.has(id):
		return
	_seen[id] = true
	for p in o.get_property_list():
		if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		if _skip_fields.has(p.name):
			continue
		var b := est_heap(o.get(p.name), 1)
		if b > 0:
			acc[prefix + p.name] = int(acc.get(prefix + p.name, 0)) + b


static func multimesh_bytes(mm: MultiMesh) -> int:
	if mm == null:
		return 0
	var floats := 12 if mm.transform_format == MultiMesh.TRANSFORM_3D else 8
	if mm.use_colors:
		floats += 4
	if mm.use_custom_data:
		floats += 4
	return mm.instance_count * floats * 4


static func mesh_bytes(m: Mesh) -> int:
	if not (m is ArrayMesh):
		return 0
	var am := m as ArrayMesh
	var n := 0
	for s in am.get_surface_count():
		n += am.surface_get_array_len(s) * 48 + am.surface_get_array_index_len(s) * 4
	return n


static func monitors() -> Dictionary:
	return {
		"static_mb": OS.get_static_memory_usage() / 1048576.0,
		"peak_mb": OS.get_static_memory_peak_usage() / 1048576.0,
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"video_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"tex_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"buf_mb": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
	}


static func monitors_line(tag: String) -> String:
	var m := monitors()
	return "MEM %s static_mb=%.1f peak_mb=%.1f objects=%d resources=%d nodes=%d video_mb=%.1f tex_mb=%.1f buf_mb=%.1f" % [
		tag, m.static_mb, m.peak_mb, m.objects, m.resources, m.nodes, m.video_mb, m.tex_mb, m.buf_mb]


## Owner table for a running game tree. Returns {owner: bytes}.
func census_tree(tree: SceneTree) -> Dictionary:
	reset()
	var acc: Dictionary = {}
	var cm = tree.get_first_node_in_group("chunk_manager")
	var view_mm := 0
	var view_mesh := 0
	if cm != null:
		var views: Dictionary = cm.chunks
		acc["#views"] = views.size()
		for k in views:
			var v = views[k]
			if v == null or not is_instance_valid(v):
				continue
			if v.chunk_data != null:
				fields_into(v.chunk_data, "chunk_data.", acc)
				for g in ["macro_grid", "micro_grid"]:
					var go = v.chunk_data.get(g)
					if go is Object:
						fields_into(go, "chunk_data.%s." % g, acc)
			var md: Dictionary = v.mesh_data if v.mesh_data != null else {}
			for mk in md:
				acc["view.mesh_data." + str(mk)] = int(acc.get("view.mesh_data." + str(mk), 0)) + est_heap(md[mk], 1)
		fields_into(cm, "chunk_manager.", acc)
		for n in _all_nodes(cm):
			if n is MultiMeshInstance3D:
				view_mm += multimesh_bytes((n as MultiMeshInstance3D).multimesh)
			elif n is MeshInstance3D:
				view_mesh += mesh_bytes((n as MeshInstance3D).mesh)
	acc["gpu.chunk_multimesh_buffers"] = view_mm
	acc["gpu.chunk_array_meshes"] = view_mesh
	var other_mm := 0
	var other_mesh := 0
	for n in _all_nodes(tree.root):
		if cm != null and (n == cm or cm.is_ancestor_of(n)):
			continue
		if n is MultiMeshInstance3D:
			other_mm += multimesh_bytes((n as MultiMeshInstance3D).multimesh)
		elif n is MeshInstance3D:
			other_mesh += mesh_bytes((n as MeshInstance3D).mesh)
	acc["gpu.other_multimesh_buffers(vegetation,props)"] = other_mm
	acc["gpu.other_array_meshes"] = other_mesh
	if cm != null and (cm.chunks as Dictionary).size() > 0:
		var any = (cm.chunks as Dictionary).values()[0]
		if any.chunk_data != null and any.chunk_data.world != null:
			fields_into(any.chunk_data.world, "world.", acc)
	census_services(acc)
	return acc


func census_services(acc: Dictionary) -> void:
	var S = load("res://world/world_bake_service.gd")
	var bake = S.get_active()
	if bake != null:
		fields_into(bake, "bake.", acc)
	var MPC = load("res://world/mesh_plan_cache.gd")
	var mpc = MPC.get_active()
	if mpc != null:
		fields_into(mpc, "mesh_plan_cache.", acc)


static func _all_nodes(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


static func table_lines(tag: String, acc: Dictionary, top: int = 40) -> PackedStringArray:
	var keys: Array = acc.keys()
	keys.sort_custom(func(a, b): return int(acc[a]) > int(acc[b]))
	var out := PackedStringArray()
	var total := 0
	for k in keys:
		if not str(k).begins_with("#") and not str(k).begins_with("gpu."):
			total += int(acc[k])
	out.append("MEMOWN %s cpu_est_total_mb=%.2f views=%d" % [tag, total / 1048576.0, int(acc.get("#views", 0))])
	var i := 0
	for k in keys:
		if str(k).begins_with("#"):
			continue
		if i >= top:
			break
		if int(acc[k]) < 4096:
			continue
		out.append("MEMOWN %s %s mb=%.2f" % [tag, k, int(acc[k]) / 1048576.0])
		i += 1
	return out
