class_name TerrainSurfaceCache
extends RefCounted
## Canonical face-only terrain geometry cache. Incremental edits patch O(dirty rect), not full chunk.

const _ChunkSurfaceMeshBuilder = preload("res://helpers/chunk_surface_mesh_builder.gd")

const STRIDE := 16


static func quad_key(q: Dictionary) -> int:
	return (
		"%d:%d:%.3f:%d:%.3f:%.3f:%.3f:%d:%.3f:%.3f"
		% [
			int(q.get("x", 0)), int(q.get("z", 0)), float(q.get("y", 0.0)),
			int(q.get("face_code", 0)), float(q.get("dim_x", 1.0)), float(q.get("dim_z", 1.0)),
			float(q.get("dim_y", 1.0)), int(q.get("type", 0)),
			float(q.get("uv_w", 1.0)), float(q.get("uv_h", 1.0)),
		]
	).hash()


static func is_terrain_quad(q: Dictionary) -> bool:
	return int(q.get("face_code", 99)) < 7


static func filter_terrain_quads(quads: Array) -> Array:
	var out: Array = []
	for q_variant in quads:
		var q: Dictionary = q_variant
		if is_terrain_quad(q):
			out.append(q)
	return out


static func pack_from_terrain_buffer(buffer: PackedFloat32Array, terrain_count: int) -> Dictionary:
	return {
		"terrain_buffer": buffer,
		"terrain_count": terrain_count,
		"vertices": PackedVector3Array(),
		"normals": PackedVector3Array(),
		"uvs": PackedVector2Array(),
		"colors": PackedColorArray(),
		"indices": PackedInt32Array(),
		"triangle_count": 0,
		"face_keys": PackedInt64Array(),
		"materialized": false,
	}


static func build_from_quads(data: ChunkData, terrain_quads: Array) -> Dictionary:
	var built := _ChunkSurfaceMeshBuilder.build_surface_arrays_from_terrain_quads(data, terrain_quads)
	return _cache_from_built(built, terrain_quads)


static func incremental_patch_needed(
	prior: Dictionary,
	patch_quads: Array,
	keep_quads: Array
) -> bool:
	if prior.is_empty() or not prior.get("materialized", false):
		return true
	var patch_terrain := filter_terrain_quads(patch_quads)
	var keep_terrain := filter_terrain_quads(keep_quads)
	if patch_terrain.is_empty():
		return true
	var old_keys: PackedInt64Array = prior.get("face_keys", PackedInt64Array())
	if keep_terrain.size() + patch_terrain.size() != old_keys.size():
		return true
	var key_to_index := {}
	for i in old_keys.size():
		key_to_index[int(old_keys[i])] = i
	for q in patch_terrain:
		if not key_to_index.has(quad_key(q)):
			return true
	return false


static func patch_region(
	prior: Dictionary,
	data: ChunkData,
	patch_quads: Array,
	keep_quads: Array
) -> Dictionary:
	var patch_terrain := filter_terrain_quads(patch_quads)
	var keep_terrain := filter_terrain_quads(keep_quads)
	if prior.is_empty() or not prior.get("materialized", false):
		var merged: Array = keep_terrain.duplicate()
		for q in patch_terrain:
			merged.append(q)
		return build_from_quads(data, merged)

	var keep_keys := {}
	for q in keep_terrain:
		keep_keys[quad_key(q)] = true

	var old_keys: PackedInt64Array = prior.get("face_keys", PackedInt64Array())
	var key_to_index := {}
	for i in old_keys.size():
		key_to_index[int(old_keys[i])] = i

	if patch_terrain.is_empty():
		var kept_only: Array = []
		for i in old_keys.size():
			var key: int = int(old_keys[i])
			if keep_keys.has(key):
				kept_only.append({"key": key, "vi": i * 4})
		return _cache_from_kept_faces(prior, kept_only)

	var patch_keys := {}
	for q in patch_terrain:
		patch_keys[quad_key(q)] = q

	var needs_merge := incremental_patch_needed(prior, patch_quads, keep_quads)

	if not needs_merge:
		# Full quad_key covers geometry inputs; existing keys imply identical faces.
		return prior

	var kept_faces: Array = []
	for i in old_keys.size():
		var key: int = int(old_keys[i])
		if keep_keys.has(key):
			kept_faces.append({"key": key, "vi": i * 4})

	var built_merge := _ChunkSurfaceMeshBuilder.build_surface_arrays_from_terrain_quads(
		data, patch_terrain
	)
	return _merge_face_slices(prior, kept_faces, built_merge, patch_terrain)


static func to_arrays(cache: Dictionary) -> Dictionary:
	if cache.get("materialized", false):
		return {
			"vertices": cache.get("vertices", PackedVector3Array()),
			"normals": cache.get("normals", PackedVector3Array()),
			"uvs": cache.get("uvs", PackedVector2Array()),
			"colors": cache.get("colors", PackedColorArray()),
			"indices": cache.get("indices", PackedInt32Array()),
			"triangle_count": int(cache.get("triangle_count", 0)),
		}
	var buffer: PackedFloat32Array = cache.get("terrain_buffer", PackedFloat32Array())
	var terrain_count: int = int(cache.get("terrain_count", 0))
	return _ChunkSurfaceMeshBuilder.build_surface_arrays_from_terrain_buffer(buffer, terrain_count)


static func to_array_mesh(cache: Dictionary) -> ArrayMesh:
	return _ChunkSurfaceMeshBuilder.build_array_mesh(to_arrays(cache))


static func attach_to_payload(cache: Dictionary, payload: Dictionary, materialize_mesh: bool = true) -> void:
	payload["surface_cache"] = cache
	payload["surface_triangle_count"] = int(cache.get("triangle_count", 0))
	payload["surface_draw_calls"] = 1 if int(cache.get("triangle_count", 0)) > 0 else 0
	if not materialize_mesh:
		return
	var arrays := to_arrays(cache)
	payload["surface_vertices"] = arrays.vertices
	payload["surface_normals"] = arrays.normals
	payload["surface_uvs"] = arrays.uvs
	payload["surface_colors"] = arrays.colors
	payload["surface_indices"] = arrays.indices
	if int(arrays.triangle_count) > 0:
		payload["surface_mesh_resource"] = _ChunkSurfaceMeshBuilder.build_array_mesh(arrays)


static func duplicate_cache(cache: Dictionary) -> Dictionary:
	if cache.is_empty():
		return {}
	return {
		"terrain_buffer": (cache.get("terrain_buffer", PackedFloat32Array()) as PackedFloat32Array).duplicate(),
		"terrain_count": int(cache.get("terrain_count", 0)),
		"vertices": (cache.get("vertices", PackedVector3Array()) as PackedVector3Array).duplicate(),
		"normals": (cache.get("normals", PackedVector3Array()) as PackedVector3Array).duplicate(),
		"uvs": (cache.get("uvs", PackedVector2Array()) as PackedVector2Array).duplicate(),
		"colors": (cache.get("colors", PackedColorArray()) as PackedColorArray).duplicate(),
		"indices": (cache.get("indices", PackedInt32Array()) as PackedInt32Array).duplicate(),
		"triangle_count": int(cache.get("triangle_count", 0)),
		"face_keys": (cache.get("face_keys", PackedInt64Array()) as PackedInt64Array).duplicate(),
		"materialized": bool(cache.get("materialized", false)),
	}


static func cache_from_payload(payload: Dictionary) -> Dictionary:
	if payload.has("surface_cache"):
		var cache: Dictionary = payload.get("surface_cache", {})
		return _ensure_face_keys_from_quads(cache, payload)
	if payload.has("surface_vertices"):
		var cache_from_arrays := {
			"vertices": payload.get("surface_vertices", PackedVector3Array()),
			"normals": payload.get("surface_normals", PackedVector3Array()),
			"uvs": payload.get("surface_uvs", PackedVector2Array()),
			"colors": payload.get("surface_colors", PackedColorArray()),
			"indices": payload.get("surface_indices", PackedInt32Array()),
			"triangle_count": int(payload.get("surface_triangle_count", 0)),
			"face_keys": PackedInt64Array(),
			"terrain_buffer": PackedFloat32Array(),
			"terrain_count": 0,
			"materialized": true,
		}
		return _ensure_face_keys_from_quads(cache_from_arrays, payload)
	return {}


static func triangle_count_matches_full_rebuild(data: ChunkData, cache: Dictionary, quads: Array) -> bool:
	var terrain_quads := filter_terrain_quads(quads)
	var full := build_from_quads(data, terrain_quads)
	return int(cache.get("triangle_count", -1)) == int(full.triangle_count)


static func _ensure_face_keys_from_quads(cache: Dictionary, payload: Dictionary) -> Dictionary:
	var face_keys: PackedInt64Array = cache.get("face_keys", PackedInt64Array())
	if face_keys.size() > 0:
		return cache
	var terrain_quads := filter_terrain_quads(payload.get("quads", []))
	var face_count: int = int(cache.get("triangle_count", 0)) / 2
	if terrain_quads.size() != face_count:
		return cache
	face_keys = PackedInt64Array()
	face_keys.resize(face_count)
	for i in face_count:
		face_keys[i] = quad_key(terrain_quads[i])
	cache["face_keys"] = face_keys
	return cache


static func _cache_from_built(built: Dictionary, terrain_quads: Array) -> Dictionary:
	var face_keys := PackedInt64Array()
	face_keys.resize(terrain_quads.size())
	for i in terrain_quads.size():
		face_keys[i] = quad_key(terrain_quads[i])
	return {
		"terrain_buffer": PackedFloat32Array(),
		"terrain_count": terrain_quads.size(),
		"vertices": built.vertices,
		"normals": built.normals,
		"uvs": built.uvs,
		"colors": built.colors,
		"indices": built.indices,
		"triangle_count": int(built.triangle_count),
		"face_keys": face_keys,
		"materialized": true,
	}


static func _cache_from_kept_faces(prior: Dictionary, kept_faces: Array) -> Dictionary:
	if kept_faces.is_empty():
		return {
			"terrain_buffer": PackedFloat32Array(),
			"terrain_count": 0,
			"vertices": PackedVector3Array(),
			"normals": PackedVector3Array(),
			"uvs": PackedVector2Array(),
			"colors": PackedColorArray(),
			"indices": PackedInt32Array(),
			"triangle_count": 0,
			"face_keys": PackedInt64Array(),
			"materialized": true,
		}
	var empty_patch := {
		"vertices": PackedVector3Array(),
		"normals": PackedVector3Array(),
		"uvs": PackedVector2Array(),
		"colors": PackedColorArray(),
		"indices": PackedInt32Array(),
		"triangle_count": 0,
	}
	return _merge_face_slices(prior, kept_faces, empty_patch, [])


static func _merge_face_slices(
	prior: Dictionary,
	kept_faces: Array,
	patch_built: Dictionary,
	patch_quads: Array
) -> Dictionary:
	var kept_vert_count := kept_faces.size() * 4
	var patch_vert_count: int = patch_built.vertices.size()
	var total_faces := kept_faces.size() + patch_quads.size()
	if total_faces <= 0:
		return {
			"terrain_buffer": PackedFloat32Array(),
			"terrain_count": 0,
			"vertices": PackedVector3Array(),
			"normals": PackedVector3Array(),
			"uvs": PackedVector2Array(),
			"colors": PackedColorArray(),
			"indices": PackedInt32Array(),
			"triangle_count": 0,
			"face_keys": PackedInt64Array(),
			"materialized": true,
		}

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.resize(kept_vert_count + patch_vert_count)
	normals.resize(kept_vert_count + patch_vert_count)
	uvs.resize(kept_vert_count + patch_vert_count)
	colors.resize(kept_vert_count + patch_vert_count)
	indices.resize(total_faces * 6)

	var prior_verts: PackedVector3Array = prior.get("vertices", PackedVector3Array())
	var prior_normals: PackedVector3Array = prior.get("normals", PackedVector3Array())
	var prior_uvs: PackedVector2Array = prior.get("uvs", PackedVector2Array())
	var prior_colors: PackedColorArray = prior.get("colors", PackedColorArray())

	var vi := 0
	var ii := 0
	for kept in kept_faces:
		var src_vi: int = int(kept.get("vi", 0))
		for j in 4:
			vertices[vi + j] = prior_verts[src_vi + j]
			normals[vi + j] = prior_normals[src_vi + j]
			uvs[vi + j] = prior_uvs[src_vi + j]
			colors[vi + j] = prior_colors[src_vi + j]
		indices[ii + 0] = vi
		indices[ii + 1] = vi + 1
		indices[ii + 2] = vi + 2
		indices[ii + 3] = vi
		indices[ii + 4] = vi + 2
		indices[ii + 5] = vi + 3
		vi += 4
		ii += 6

	if patch_vert_count > 0:
		var patch_verts: PackedVector3Array = patch_built.vertices
		var patch_normals: PackedVector3Array = patch_built.normals
		var patch_uvs: PackedVector2Array = patch_built.uvs
		var patch_colors: PackedColorArray = patch_built.colors
		for j in patch_vert_count:
			vertices[vi + j] = patch_verts[j]
			normals[vi + j] = patch_normals[j]
			uvs[vi + j] = patch_uvs[j]
			colors[vi + j] = patch_colors[j]
		var patch_indices: PackedInt32Array = patch_built.indices
		for k in patch_indices.size():
			indices[ii + k] = patch_indices[k] + vi
		ii += patch_indices.size()

	var face_keys := PackedInt64Array()
	face_keys.resize(total_faces)
	var key_i := 0
	for kept in kept_faces:
		face_keys[key_i] = int(kept.get("key", 0))
		key_i += 1
	for q in patch_quads:
		face_keys[key_i] = quad_key(q)
		key_i += 1

	return {
		"terrain_buffer": PackedFloat32Array(),
		"terrain_count": total_faces,
		"vertices": vertices,
		"normals": normals,
		"uvs": uvs,
		"colors": colors,
		"indices": indices,
		"triangle_count": total_faces * 2,
		"face_keys": face_keys,
		"materialized": true,
	}