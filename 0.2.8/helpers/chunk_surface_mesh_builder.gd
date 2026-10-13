class_name ChunkSurfaceMeshBuilder
extends RefCounted
## Consolidated face-only terrain mesh from greedy quads (replaces per-quad box MultiMesh).

const _WorldSettings = preload("res://config/world_settings.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _TerrainAO = preload("res://helpers/terrain_vertex_ao.gd")

const FACE_TOP := 0
const FACE_BOTTOM := 2
const FACE_NEG_X := 3
const FACE_POS_X := 4
const FACE_NEG_Z := 5
const FACE_POS_Z := 6
const FACE_RAMP := 7
const FACE_RAMP_CORNER := 8
const FACE_RAMP_SIDE := 9


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
			vi, ii, face_code, ox, oz, sx, sy, sz, surface_y, atlas, shade, uv_w, uv_h,
			1.0, data, float(q["x"]), float(q["z"]), dim_x, dim_z
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
	return build_surface_arrays_from_terrain_quads(data, quads)


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

	var draw_quads: Array = []
	for q_variant in terrain_quads:
		var fc: int = int((q_variant as Dictionary).get("face_code", -1))
		if fc < FACE_RAMP or fc == FACE_RAMP or fc == FACE_RAMP_CORNER:
			draw_quads.append(q_variant)
	if draw_quads.is_empty():
		return empty

	var face_count := draw_quads.size()
	if face_count <= 0:
		return empty
	var extra_slots := 0
	for q_pre in draw_quads:
		var q0: Dictionary = q_pre
		var fc0: int = int(q0.get("face_code", -1))
		if fc0 == FACE_RAMP:
			# slope + floor under the wedge + optional vertical flanks
			extra_slots += 1 + int(q0.get("flank_a", 0)) + int(q0.get("flank_b", 0))
		elif fc0 == FACE_RAMP_CORNER:
			# triangular top + one diagonal vertical square
			extra_slots += 1

	var ws = _WorldSettings.get_active()
	var voxel_s: float = ws.voxel_scale
	var chunk_ox: float = ws.column_to_world(float(data.position.x * ChunkData.SIZE))
	var chunk_oz: float = ws.column_to_world(float(data.position.y * ChunkData.SIZE))

	var slot_count := face_count + extra_slots
	var vert_count := slot_count * 4
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.resize(vert_count)
	normals.resize(vert_count)
	uvs.resize(vert_count)
	colors.resize(vert_count)
	indices.resize(slot_count * 6)

	var vi := 0
	var ii := 0
	for q_variant in draw_quads:
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
		var atlas: Vector2i = _VoxelTypes.get_atlas_coord_for_face(tile_type, FACE_TOP if face_code >= FACE_RAMP else face_code)
		var shade: float = _face_shade(face_code)
		if face_code == FACE_RAMP:
			var dir := Vector2i(int(q.get("ramp_dir_x", 1)), int(q.get("ramp_dir_z", 0)))
			_write_cardinal_ramp(
				vertices, normals, uvs, colors, indices,
				vi, ii, ox, oz, sx, sy, sz, surface_y, dir, atlas, shade
			)
			vi += 4
			ii += 6
			_write_cardinal_floor(
				vertices, normals, uvs, colors, indices,
				vi, ii, ox, oz, sx, sz, surface_y, atlas, shade
			)
			vi += 4
			ii += 6
			var wrote := _write_cardinal_flanks(
				vertices, normals, uvs, colors, indices,
				vi, ii, ox, oz, sx, sy, sz, surface_y, dir, atlas, shade,
				int(q.get("flank_a", 0)) != 0, int(q.get("flank_b", 0)) != 0
			)
			vi += wrote * 4
			ii += wrote * 6
			continue
		elif face_code == FACE_RAMP_CORNER:
			var dir_a := Vector2i(int(q.get("ramp_dir_x", 1)), int(q.get("ramp_dir_z", 0)))
			var dir_b := Vector2i(int(q.get("ramp_dir2_x", 0)), int(q.get("ramp_dir2_z", 1)))
			_write_corner_ramp(
				vertices, normals, uvs, colors, indices,
				vi, ii, ox, oz, sx, sy, sz, surface_y, dir_a, dir_b, atlas, shade
			)
			vi += 8
			ii += 12
			continue
		else:
			_write_face_quad(
				vertices, normals, uvs, colors, indices,
				vi, ii, face_code, ox, oz, sx, sy, sz, surface_y, atlas, shade,
				float(q.get("uv_w", dim_x)), float(q.get("uv_h", dim_z)),
				1.0, data, float(q["x"]), float(q["z"]), dim_x, dim_z
			)
		vi += 4
		ii += 6

	return {
		"vertices": vertices,
		"normals": normals,
		"uvs": uvs,
		"colors": colors,
		"indices": indices,
		"triangle_count": slot_count * 2,
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
			float(q.get("uv_w", dim_x)), float(q.get("uv_h", dim_z)),
			1.0, data, float(q["x"]), float(q["z"]), dim_x, dim_z
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
	_unused: float = 1.0,
	data: ChunkData = null,
	col_x: float = 0.0,
	col_z: float = 0.0,
	col_dim_x: float = 1.0,
	col_dim_z: float = 1.0
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
	var ao := Vector4.ONE
	if face_code == FACE_TOP and data != null:
		ao = _TerrainAO.top_corner_ao(
			data,
			int(round(col_x)),
			int(round(col_z)),
			maxi(int(round(col_dim_x)), 1),
			maxi(int(round(col_dim_z)), 1),
			surface_y
		)

	normals[vi + 0] = normal
	normals[vi + 1] = normal
	normals[vi + 2] = normal
	normals[vi + 3] = normal
	uvs[vi + 0] = Vector2(0.0, 0.0)
	uvs[vi + 1] = Vector2(uv_w, 0.0)
	uvs[vi + 2] = Vector2(uv_w, uv_h)
	uvs[vi + 3] = Vector2(0.0, uv_h)
	colors[vi + 0] = Color(tint.r, tint.g, tint.b, ao.x)
	colors[vi + 1] = Color(tint.r, tint.g, tint.b, ao.y)
	colors[vi + 2] = Color(tint.r, tint.g, tint.b, ao.z)
	colors[vi + 3] = Color(tint.r, tint.g, tint.b, ao.w)

	indices[ii + 0] = vi
	indices[ii + 1] = vi + 1
	indices[ii + 2] = vi + 2
	indices[ii + 3] = vi
	indices[ii + 4] = vi + 2
	indices[ii + 5] = vi + 3


static func _write_cardinal_ramp(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	vi: int,
	ii: int,
	ox: float,
	oz: float,
	sx: float,
	sy: float,
	sz: float,
	surface_y: float,
	dir: Vector2i,
	atlas: Vector2i,
	shade: float
) -> void:
	# Landing column only. Low edge is toward `dir` (world-cell step-down).
	var yh: float = surface_y + sy
	var yl: float = surface_y
	var x0 := ox
	var x1 := ox + sx
	var z0 := oz
	var z1 := oz + sz
	if dir.x > 0:
		vertices[vi + 0] = Vector3(x0, yh, z0)
		vertices[vi + 1] = Vector3(x0, yh, z1)
		vertices[vi + 2] = Vector3(x1, yl, z1)
		vertices[vi + 3] = Vector3(x1, yl, z0)
	elif dir.x < 0:
		vertices[vi + 0] = Vector3(x1, yh, z1)
		vertices[vi + 1] = Vector3(x1, yh, z0)
		vertices[vi + 2] = Vector3(x0, yl, z0)
		vertices[vi + 3] = Vector3(x0, yl, z1)
	elif dir.y > 0:
		vertices[vi + 0] = Vector3(x1, yh, z0)
		vertices[vi + 1] = Vector3(x0, yh, z0)
		vertices[vi + 2] = Vector3(x0, yl, z1)
		vertices[vi + 3] = Vector3(x1, yl, z1)
	else:
		vertices[vi + 0] = Vector3(x0, yh, z1)
		vertices[vi + 1] = Vector3(x1, yh, z1)
		vertices[vi + 2] = Vector3(x1, yl, z0)
		vertices[vi + 3] = Vector3(x0, yl, z0)
	var shade_n := _slope_shade_normal(vertices, vi)
	_fill_face_attribs(vertices, normals, uvs, colors, indices, vi, ii, atlas, shade, shade_n, 1.0, 1.0)


static func _write_cardinal_floor(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	vi: int,
	ii: int,
	ox: float,
	oz: float,
	sx: float,
	sz: float,
	surface_y: float,
	atlas: Vector2i,
	shade: float
) -> void:
	# Solid under the wedge: the landing column's floor at the low edge (approach top).
	var yl: float = surface_y
	vertices[vi + 0] = Vector3(ox, yl, oz)
	vertices[vi + 1] = Vector3(ox + sx, yl, oz)
	vertices[vi + 2] = Vector3(ox + sx, yl, oz + sz)
	vertices[vi + 3] = Vector3(ox, yl, oz + sz)
	_fill_face_attribs(vertices, normals, uvs, colors, indices, vi, ii, atlas, shade, Vector3.UP, 1.0, 1.0)


static func _write_vertical_tri(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	vi: int,
	ii: int,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	atlas: Vector2i,
	shade: float
) -> void:
	vertices[vi + 0] = a
	vertices[vi + 1] = b
	vertices[vi + 2] = c
	vertices[vi + 3] = a
	var geom: Vector3 = (b - a).cross(c - a)
	var n: Vector3 = Vector3.UP
	if geom.length_squared() > 0.0001:
		n = geom.normalized()
	_fill_face_attribs(vertices, normals, uvs, colors, indices, vi, ii, atlas, shade, n, 1.0, 1.0)


static func _write_cardinal_flanks(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	vi: int,
	ii: int,
	ox: float,
	oz: float,
	sx: float,
	sy: float,
	sz: float,
	surface_y: float,
	dir: Vector2i,
	atlas: Vector2i,
	shade: float,
	flank_a: bool,
	flank_b: bool
) -> int:
	var yh: float = surface_y + sy
	var yl: float = surface_y
	var x0 := ox
	var x1 := ox + sx
	var z0 := oz
	var z1 := oz + sz
	var n := 0
	var sides: Array = []
	if flank_a:
		sides.append(Vector2i(-dir.y, dir.x))
	if flank_b:
		sides.append(Vector2i(dir.y, -dir.x))
	for side_v in sides:
		var side: Vector2i = side_v
		var a: Vector3
		var b: Vector3
		var c: Vector3
		if side.y != 0:
			var zf: float = z1 if side.y > 0 else z0
			var hx: float = x0 if dir.x > 0 else (x1 if dir.x < 0 else (x0 if dir.y < 0 else x1))
			var lx: float = x1 if dir.x > 0 else (x0 if dir.x < 0 else (x1 if dir.y < 0 else x0))
			if dir.x == 0:
				hx = x0 if ((dir.y > 0 and side.y < 0) or (dir.y < 0 and side.y > 0)) else x1
				lx = x1 if hx == x0 else x0
			a = Vector3(hx, yh, zf)
			b = Vector3(lx, yl, zf)
			c = Vector3(hx, yl, zf)
		else:
			var xf: float = x1 if side.x > 0 else x0
			var hz: float = z0 if dir.y > 0 else (z1 if dir.y < 0 else (z0 if dir.x < 0 else z1))
			var lz: float = z1 if dir.y > 0 else (z0 if dir.y < 0 else (z1 if dir.x < 0 else z0))
			if dir.y == 0:
				hz = z0 if ((dir.x > 0 and side.x < 0) or (dir.x < 0 and side.x > 0)) else z1
				lz = z1 if hz == z0 else z0
			a = Vector3(xf, yh, hz)
			b = Vector3(xf, yl, lz)
			c = Vector3(xf, yl, hz)
		var base: int = vi + n * 4
		var ibase: int = ii + n * 6
		_write_vertical_tri(vertices, normals, uvs, colors, indices, base, ibase, a, b, c, atlas, 0.68)
		n += 1
	return n


static func _write_corner_ramp(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	vi: int,
	ii: int,
	ox: float,
	oz: float,
	sx: float,
	sy: float,
	sz: float,
	surface_y: float,
	dir_a: Vector2i,
	dir_b: Vector2i,
	atlas: Vector2i,
	shade: float
) -> void:
	# Low cell FACE_TOP is at surface_y+sy. Plateau FACE_TOP is one layer above that.
	var yl: float = surface_y + sy
	var yh: float = surface_y + sy + sy
	var lx: int = 1 if (dir_a.x != 0 and dir_a.x > 0) or (dir_b.x != 0 and dir_b.x > 0) else -1
	if dir_a.x == 0 and dir_b.x == 0:
		lx = 1
	var lz: int = 1 if (dir_a.y != 0 and dir_a.y > 0) or (dir_b.y != 0 and dir_b.y > 0) else -1
	if dir_a.y == 0 and dir_b.y == 0:
		lz = 1
	var x0 := ox
	var x1 := ox + sx
	var z0 := oz
	var z1 := oz + sz
	var high_x := Vector3(x1 if lx > 0 else x0, yh, z0 if lz > 0 else z1)
	var high_z := Vector3(x0 if lx > 0 else x1, yh, z1 if lz > 0 else z0)
	var far_high := Vector3(x1 if lx > 0 else x0, yh, z1 if lz > 0 else z0)
	# Inner half-block: flat triangle at plateau height meeting both supporting tops.
	vertices[vi + 0] = high_x
	vertices[vi + 1] = far_high
	vertices[vi + 2] = high_z
	vertices[vi + 3] = high_x
	var top_n := _slope_shade_normal(vertices, vi)
	_fill_face_attribs(vertices, normals, uvs, colors, indices, vi, ii, atlas, 0.96, top_n, 1.0, 1.0)
	# One diagonal vertical square on the cut (the other diagonal of the cell).
	var hx_low := Vector3(high_x.x, yl, high_x.z)
	var hz_low := Vector3(high_z.x, yl, high_z.z)
	var vi2: int = vi + 4
	var ii2: int = ii + 6
	var outward := Vector3(float(-lx), 0.0, float(-lz))
	var n_try: Vector3 = (high_x - hx_low).cross(high_z - hx_low)
	if n_try.dot(outward) >= 0.0:
		vertices[vi2 + 0] = hx_low
		vertices[vi2 + 1] = high_x
		vertices[vi2 + 2] = high_z
		vertices[vi2 + 3] = hz_low
	else:
		vertices[vi2 + 0] = hx_low
		vertices[vi2 + 1] = hz_low
		vertices[vi2 + 2] = high_z
		vertices[vi2 + 3] = high_x
		n_try = -n_try
	if n_try.length_squared() < 0.0001:
		n_try = outward
	else:
		n_try = n_try.normalized()
	_fill_face_attribs(vertices, normals, uvs, colors, indices, vi2, ii2, atlas, 0.74, n_try, 1.0, 1.0)


## Keep +Y geometric winding; shade with the +Y slope normal. Visibility of
## sloped faces from the iso camera is handled by ChunkSurfaceMesh (cull_disabled).
static func _slope_shade_normal(vertices: PackedVector3Array, vi: int) -> Vector3:
	var e1: Vector3 = vertices[vi + 1] - vertices[vi + 0]
	var e2: Vector3 = vertices[vi + 2] - vertices[vi + 0]
	var geom: Vector3 = e1.cross(e2)
	if geom.y < 0.0:
		var tmp: Vector3 = vertices[vi + 1]
		vertices[vi + 1] = vertices[vi + 2]
		vertices[vi + 2] = tmp
		geom = -geom
	if geom.length_squared() < 0.0001:
		return Vector3.UP
	return geom.normalized()


static func _fill_face_attribs(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	vi: int,
	ii: int,
	atlas: Vector2i,
	shade: float,
	normal: Vector3,
	uv_w: float,
	uv_h: float
) -> void:
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