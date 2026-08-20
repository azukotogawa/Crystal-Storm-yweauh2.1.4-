class_name ChunkSurfaceMeshBuilder
extends RefCounted
## Consolidated face-only terrain mesh from greedy quads (replaces per-quad box MultiMesh).

const _WorldSettings = preload("res://config/world_settings.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")

const FACE_TOP := 0
const FACE_BOTTOM := 2
const FACE_NEG_X := 3
const FACE_POS_X := 4
const FACE_NEG_Z := 5
const FACE_POS_Z := 6
const FACE_RAMP := 7


static func attach_surface_only_payload(data: ChunkData, terrain_quads: Array, payload: Dictionary) -> void:
	var built := build_surface_arrays_from_terrain_quads(data, terrain_quads)
	payload["surface_vertices"] = built.vertices
	payload["surface_normals"] = built.normals
	payload["surface_uvs"] = built.uvs
	payload["surface_colors"] = built.colors
	payload["surface_indices"] = built.indices
	payload["surface_triangle_count"] = built.triangle_count
	payload["surface_draw_calls"] = 1 if built.triangle_count > 0 else 0


static func attach_surface_from_terrain_buffer_payload(payload: Dictionary) -> void:
	var buffer: PackedFloat32Array = payload.get("terrain_buffer", PackedFloat32Array())
	var terrain_count: int = int(payload.get("terrain_count", 0))
	var built := build_surface_arrays_from_terrain_buffer(buffer, terrain_count)
	payload["surface_vertices"] = built.vertices
	payload["surface_normals"] = built.normals
	payload["surface_uvs"] = built.uvs
	payload["surface_colors"] = built.colors
	payload["surface_indices"] = built.indices
	payload["surface_triangle_count"] = built.triangle_count
	payload["surface_draw_calls"] = 1 if built.triangle_count > 0 else 0


static func attach_fused_terrain_payload(data: ChunkData, terrain_quads: Array, payload: Dictionary) -> void:
	var fused := build_fused_terrain_buffers(data, terrain_quads, false)
	payload["terrain_buffer"] = PackedFloat32Array()
	payload["surface_vertices"] = fused.vertices
	payload["surface_normals"] = fused.normals
	payload["surface_uvs"] = fused.uvs
	payload["surface_colors"] = fused.colors
	payload["surface_indices"] = fused.indices
	payload["surface_triangle_count"] = fused.triangle_count
	payload["surface_draw_calls"] = 1 if fused.triangle_count > 0 else 0
	if fused.triangle_count > 0:
		payload["surface_mesh_resource"] = build_array_mesh(fused)


static func build_fused_terrain_buffers(
	data: ChunkData, terrain_quads: Array, include_terrain_buffer: bool = true
) -> Dictionary:
	var empty := {
		"terrain_buffer": PackedFloat32Array(),
		"vertices": PackedVector3Array(),
		"normals": PackedVector3Array(),
		"uvs": PackedVector2Array(),
		"colors": PackedColorArray(),
		"indices": PackedInt32Array(),
		"triangle_count": 0,
	}
	if terrain_quads.is_empty() or data == null:
		return empty

	var face_count := terrain_quads.size()
	var ws = _WorldSettings.get_active()
	var voxel_s: float = ws.voxel_scale
	var chunk_ox: float = ws.column_to_world(float(data.position.x * ChunkData.SIZE))
	var chunk_oz: float = ws.column_to_world(float(data.position.y * ChunkData.SIZE))
	var stride := 16

	var buffer := PackedFloat32Array()
	if include_terrain_buffer:
		buffer.resize(face_count * stride)
	var vert_count := face_count * 4
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.resize(vert_count)
	normals.resize(vert_count)
	uvs.resize(vert_count)
	colors.resize(vert_count)
	indices.resize(face_count * 6)

	var vi := 0
	var ii := 0
	for i in face_count:
		var q: Dictionary = terrain_quads[i]
		var base: int = i * stride
		var dim_x: float = float(q.get("dim_x", 1.0))
		var dim_y: float = float(q.get("dim_y", 1.0))
		var dim_z: float = float(q.get("dim_z", 1.0))
		var surface_y: float = float(q["y"])
		var ox: float = chunk_ox + ws.column_to_world(float(q["x"]))
		var oz: float = chunk_oz + ws.column_to_world(float(q["z"]))
		var sx: float = dim_x * voxel_s
		var sy: float = dim_y * voxel_s
		var sz: float = dim_z * voxel_s
		var cx: float = ox + sx * 0.5
		var cy: float = surface_y + sy * 0.5
		var cz: float = oz + sz * 0.5

		var face_code := int(q.get("face_code", 0))
		var tile_type: int = int(q.get("type", _VoxelTypes.AIR))
		var atlas: Vector2i = _VoxelTypes.get_atlas_coord_for_face(tile_type, face_code)
		var shade: float = _face_shade(face_code)
		var uv_w: float = float(q.get("uv_w", dim_x))
		var uv_h: float = float(q.get("uv_h", dim_z))
		if include_terrain_buffer:
			buffer[base + 0] = sx; buffer[base + 1] = 0.0; buffer[base + 2] = 0.0; buffer[base + 3] = cx
			buffer[base + 4] = 0.0; buffer[base + 5] = sy; buffer[base + 6] = 0.0; buffer[base + 7] = cy
			buffer[base + 8] = 0.0; buffer[base + 9] = 0.0; buffer[base + 10] = sz; buffer[base + 11] = cz
			var encoded: float = float(face_code) + (uv_h / 100.0)
			buffer[base + 12] = float(atlas.x) / 255.0
			buffer[base + 13] = float(atlas.y) / 255.0
			buffer[base + 14] = encoded
			buffer[base + 15] = uv_w

		_write_face_quad(
			vertices, normals, uvs, colors, indices,
			vi, ii, face_code, ox, oz, sx, sy, sz, surface_y, atlas, shade, uv_w, uv_h
		)
		vi += 4
		ii += 6

	return {
		"terrain_buffer": buffer,
		"vertices": vertices,
		"normals": normals,
		"uvs": uvs,
		"colors": colors,
		"indices": indices,
		"triangle_count": face_count * 2,
	}


static func build_surface_arrays_from_terrain_buffer(buffer: PackedFloat32Array, terrain_count: int) -> Dictionary:
	var empty := {
		"vertices": PackedVector3Array(),
		"normals": PackedVector3Array(),
		"uvs": PackedVector2Array(),
		"colors": PackedColorArray(),
		"indices": PackedInt32Array(),
		"triangle_count": 0,
	}
	if terrain_count <= 0 or buffer.is_empty():
		return empty

	const STRIDE := 16
	var vert_count := terrain_count * 4
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.resize(vert_count)
	normals.resize(vert_count)
	uvs.resize(vert_count)
	colors.resize(vert_count)
	indices.resize(terrain_count * 6)

	var vi := 0
	var ii := 0
	for i in terrain_count:
		var base: int = i * STRIDE
		var sx: float = buffer[base + 0]
		var sy: float = buffer[base + 5]
		var sz: float = buffer[base + 10]
		var cx: float = buffer[base + 3]
		var cy: float = buffer[base + 7]
		var cz: float = buffer[base + 11]
		var encoded: float = buffer[base + 14]
		var face_code: int = int(floor(encoded + 0.1))
		var atlas := Vector2i(
			int(floor(buffer[base + 12] * 255.0 + 0.5)),
			int(floor(buffer[base + 13] * 255.0 + 0.5))
		)
		var uv_w: float = buffer[base + 15]
		var uv_h: float = round((encoded - float(face_code)) * 100.0)
		if uv_h <= 0.0:
			uv_h = 1.0
		var ox: float = cx - sx * 0.5
		var oz: float = cz - sz * 0.5
		var surface_y: float = cy - sy * 0.5
		_write_face_quad(
			vertices, normals, uvs, colors, indices,
			vi, ii, face_code, ox, oz, sx, sy, sz, surface_y, atlas, _face_shade(face_code),
			uv_w, uv_h, 1.0
		)
		vi += 4
		ii += 6

	return {
		"vertices": vertices,
		"normals": normals,
		"uvs": uvs,
		"colors": colors,
		"indices": indices,
		"triangle_count": terrain_count * 2,
	}


static func build_surface_arrays(data: ChunkData, quads: Array) -> Dictionary:
	var terrain_quads: Array = []
	for q_variant in quads:
		if int((q_variant as Dictionary).get("face_code", -1)) < FACE_RAMP:
			terrain_quads.append(q_variant)
	return build_surface_arrays_from_terrain_quads(data, terrain_quads)


static func build_surface_arrays_from_terrain_quads(data: ChunkData, terrain_quads: Array) -> Dictionary:
	var empty := {
		"vertices": PackedVector3Array(),
		"normals": PackedVector3Array(),
		"uvs": PackedVector2Array(),
		"colors": PackedColorArray(),
		"indices": PackedInt32Array(),
		"triangle_count": 0,
	}
	if terrain_quads.is_empty() or data == null:
		return empty

	var face_count := terrain_quads.size()
	if face_count <= 0:
		return empty

	var ws = _WorldSettings.get_active()
	var voxel_s: float = ws.voxel_scale
	var chunk_ox: float = ws.column_to_world(float(data.position.x * ChunkData.SIZE))
	var chunk_oz: float = ws.column_to_world(float(data.position.y * ChunkData.SIZE))

	var vert_count := face_count * 4
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.resize(vert_count)
	normals.resize(vert_count)
	uvs.resize(vert_count)
	colors.resize(vert_count)
	indices.resize(face_count * 6)

	var vi := 0
	var ii := 0
	for q_variant in terrain_quads:
		var q: Dictionary = q_variant
		var face_code := int(q.get("face_code", -1))
		var dim_x: float = float(q.get("dim_x", 1.0))
		var dim_y: float = float(q.get("dim_y", 1.0))
		var dim_z: float = float(q.get("dim_z", 1.0))
		var surface_y: float = float(q["y"])
		var ox: float = chunk_ox + ws.column_to_world(float(q["x"]))
		var oz: float = chunk_oz + ws.column_to_world(float(q["z"]))
		var sx: float = dim_x * voxel_s
		var sy: float = dim_y * voxel_s
		var sz: float = dim_z * voxel_s
		var tile_type: int = int(q.get("type", _VoxelTypes.AIR))
		var atlas: Vector2i = _VoxelTypes.get_atlas_coord_for_face(tile_type, face_code)
		_write_face_quad(
			vertices, normals, uvs, colors, indices,
			vi, ii, face_code, ox, oz, sx, sy, sz, surface_y, atlas, _face_shade(face_code),
			float(q.get("uv_w", dim_x)), float(q.get("uv_h", dim_z))
		)
		vi += 4
		ii += 6

	return {
		"vertices": vertices,
		"normals": normals,
		"uvs": uvs,
		"colors": colors,
		"indices": indices,
		"triangle_count": face_count * 2,
	}


static func patch_terrain_faces_into_cache(
	cache: Dictionary,
	data: ChunkData,
	patch_quads: Array,
	key_to_index: Dictionary
) -> void:
	if data == null or patch_quads.is_empty():
		return
	var vertices: PackedVector3Array = cache.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = cache.get("normals", PackedVector3Array())
	var uvs: PackedVector2Array = cache.get("uvs", PackedVector2Array())
	var colors: PackedColorArray = cache.get("colors", PackedColorArray())
	var indices: PackedInt32Array = cache.get("indices", PackedInt32Array())
	var ws = _WorldSettings.get_active()
	var voxel_s: float = ws.voxel_scale
	var chunk_ox: float = ws.column_to_world(float(data.position.x * ChunkData.SIZE))
	var chunk_oz: float = ws.column_to_world(float(data.position.y * ChunkData.SIZE))
	for q_variant in patch_quads:
		var q: Dictionary = q_variant
		var face_index: int = int(key_to_index.get(quad_key_from_dict(q), -1))
		if face_index < 0:
			continue
		var face_code := int(q.get("face_code", -1))
		var dim_x: float = float(q.get("dim_x", 1.0))
		var dim_y: float = float(q.get("dim_y", 1.0))
		var dim_z: float = float(q.get("dim_z", 1.0))
		var surface_y: float = float(q["y"])
		var ox: float = chunk_ox + ws.column_to_world(float(q["x"]))
		var oz: float = chunk_oz + ws.column_to_world(float(q["z"]))
		var sx: float = dim_x * voxel_s
		var sy: float = dim_y * voxel_s
		var sz: float = dim_z * voxel_s
		var tile_type: int = int(q.get("type", _VoxelTypes.AIR))
		var atlas: Vector2i = _VoxelTypes.get_atlas_coord_for_face(tile_type, face_code)
		var vi: int = face_index * 4
		var ii: int = face_index * 6
		_write_face_quad(
			vertices, normals, uvs, colors, indices,
			vi, ii, face_code, ox, oz, sx, sy, sz, surface_y, atlas, _face_shade(face_code),
			float(q.get("uv_w", dim_x)), float(q.get("uv_h", dim_z))
		)


static func quad_key_from_dict(q: Dictionary) -> int:
	return (
		"%d:%d:%.3f:%d:%.3f:%.3f:%.3f:%d:%.3f:%.3f"
		% [
			int(q.get("x", 0)), int(q.get("z", 0)), float(q.get("y", 0.0)),
			int(q.get("face_code", 0)), float(q.get("dim_x", 1.0)), float(q.get("dim_z", 1.0)),
			float(q.get("dim_y", 1.0)), int(q.get("type", 0)),
			float(q.get("uv_w", 1.0)), float(q.get("uv_h", 1.0)),
		]
	).hash()


static func build_array_mesh(arrays: Dictionary) -> ArrayMesh:
	return build_array_mesh_into(arrays, ArrayMesh.new())


static func build_array_mesh_into(arrays: Dictionary, mesh: ArrayMesh) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if arrays.get("triangle_count", 0) <= 0:
		return mesh
	var surface := []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = arrays.get("vertices", PackedVector3Array())
	surface[Mesh.ARRAY_NORMAL] = arrays.get("normals", PackedVector3Array())
	surface[Mesh.ARRAY_TEX_UV] = arrays.get("uvs", PackedVector2Array())
	surface[Mesh.ARRAY_COLOR] = arrays.get("colors", PackedColorArray())
	surface[Mesh.ARRAY_INDEX] = arrays.get("indices", PackedInt32Array())
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	return mesh


static func _write_face_quad(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	vi: int,
	ii: int,
	face_code: int,
	ox: float,
	oz: float,
	sx: float,
	sy: float,
	sz: float,
	surface_y: float,
	atlas: Vector2i,
	shade: float,
	uv_w: float,
	uv_h: float,
	_unused: float = 1.0
) -> void:
	var y0: float = surface_y
	var y1: float = surface_y + sy

	var normal := Vector3.UP

	match face_code:
		FACE_TOP:
			normal = Vector3.UP
			vertices[vi + 0] = Vector3(ox, y1, oz)
			vertices[vi + 1] = Vector3(ox + sx, y1, oz)
			vertices[vi + 2] = Vector3(ox + sx, y1, oz + sz)
			vertices[vi + 3] = Vector3(ox, y1, oz + sz)
		FACE_BOTTOM:
			normal = Vector3.DOWN
			vertices[vi + 0] = Vector3(ox, y0, oz + sz)
			vertices[vi + 1] = Vector3(ox + sx, y0, oz + sz)
			vertices[vi + 2] = Vector3(ox + sx, y0, oz)
			vertices[vi + 3] = Vector3(ox, y0, oz)
		FACE_NEG_X:
			normal = Vector3.LEFT
			vertices[vi + 0] = Vector3(ox, y0, oz + sz)
			vertices[vi + 1] = Vector3(ox, y1, oz + sz)
			vertices[vi + 2] = Vector3(ox, y1, oz)
			vertices[vi + 3] = Vector3(ox, y0, oz)
		FACE_POS_X:
			normal = Vector3.RIGHT
			vertices[vi + 0] = Vector3(ox + sx, y0, oz)
			vertices[vi + 1] = Vector3(ox + sx, y1, oz)
			vertices[vi + 2] = Vector3(ox + sx, y1, oz + sz)
			vertices[vi + 3] = Vector3(ox + sx, y0, oz + sz)
		FACE_NEG_Z:
			normal = Vector3.FORWARD
			vertices[vi + 0] = Vector3(ox, y0, oz)
			vertices[vi + 1] = Vector3(ox, y1, oz)
			vertices[vi + 2] = Vector3(ox + sx, y1, oz)
			vertices[vi + 3] = Vector3(ox + sx, y0, oz)
		FACE_POS_Z:
			normal = Vector3.BACK
			vertices[vi + 0] = Vector3(ox + sx, y0, oz + sz)
			vertices[vi + 1] = Vector3(ox + sx, y1, oz + sz)
			vertices[vi + 2] = Vector3(ox, y1, oz + sz)
			vertices[vi + 3] = Vector3(ox, y0, oz + sz)
		_:
			return

	var tint := Color(float(atlas.x) / 255.0, float(atlas.y) / 255.0, shade, 1.0)

	normals[vi + 0] = normal
	normals[vi + 1] = normal
	normals[vi + 2] = normal
	normals[vi + 3] = normal
	uvs[vi + 0] = Vector2(0.0, 0.0)
	uvs[vi + 1] = Vector2(uv_w, 0.0)
	uvs[vi + 2] = Vector2(uv_w, uv_h)
	uvs[vi + 3] = Vector2(0.0, uv_h)
	colors[vi + 0] = tint
	colors[vi + 1] = tint
	colors[vi + 2] = tint
	colors[vi + 3] = tint

	indices[ii + 0] = vi
	indices[ii + 1] = vi + 1
	indices[ii + 2] = vi + 2
	indices[ii + 3] = vi
	indices[ii + 4] = vi + 2
	indices[ii + 5] = vi + 3


static func _face_shade(face_code: int) -> float:
	if face_code == FACE_BOTTOM:
		return 0.48
	if face_code > 0 and face_code < 7:
		return 0.68
	return 0.96