class_name ChunkMeshBufferBuilder
extends RefCounted

const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const FACE_RAMP := 7
const FACE_RAMP_SIDE := 9
const STRIDE := 16


static func build_mesh_payload(data: ChunkData, quads: Array) -> Dictionary:
	var terrain_quads: Array = []
	var ramp_quads: Array = []
	var diagonal_quads: Array = []

	for q in quads:
		var face_code := int(q.get("face_code", 0))
		if face_code == FACE_RAMP:
			ramp_quads.append(q)
		elif face_code == FACE_RAMP_SIDE:
			diagonal_quads.append(q)
		else:
			terrain_quads.append(q)

	return {
		"quads": quads,
		"count": quads.size(),
		"terrain_buffer": _build_box_buffer(data, terrain_quads),
		"terrain_count": terrain_quads.size(),
		"ramp_buffer": _build_ramp_buffer(data, ramp_quads, "cardinal"),
		"ramp_count": ramp_quads.size(),
		"diagonal_buffer": _build_ramp_buffer(data, diagonal_quads, "diagonal"),
		"diagonal_count": diagonal_quads.size(),
	}


static func _build_box_buffer(data: ChunkData, quads: Array) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	if quads.is_empty():
		return buffer

	var ws = _WorldSettings.get_active()
	var voxel_s: float = ws.voxel_scale
	var chunk_offset_x: float = ws.column_to_world(float(data.position.x * ChunkData.SIZE))
	var chunk_offset_z: float = ws.column_to_world(float(data.position.y * ChunkData.SIZE))
	buffer.resize(quads.size() * STRIDE)

	for i in quads.size():
		var q = quads[i]
		var base: int = i * STRIDE
		var sx = q["dim_x"]
		var sy = q["dim_y"]
		var sz = q["dim_z"]
		var surface_y: float = float(q["y"])
		var ox = ws.column_to_world(float(q["x"])) + chunk_offset_x + sx * voxel_s * 0.5
		var oy = surface_y + sy * voxel_s * 0.5
		var oz = ws.column_to_world(float(q["z"])) + chunk_offset_z + sz * voxel_s * 0.5

		buffer[base + 0] = sx * voxel_s; buffer[base + 1] = 0;  buffer[base + 2] = 0;  buffer[base + 3] = ox
		buffer[base + 4] = 0;  buffer[base + 5] = sy * voxel_s; buffer[base + 6] = 0;  buffer[base + 7] = oy
		buffer[base + 8] = 0;  buffer[base + 9] = 0;  buffer[base + 10] = sz * voxel_s; buffer[base + 11] = oz

		var atlas = VoxelTypes.ATLAS_COORDS.get(q["type"], Vector2i(6, 0))
		var encoded = float(q["face_code"]) + (q["uv_h"] / 100.0)
		buffer[base + 12] = float(atlas.x) / 255.0
		buffer[base + 13] = float(atlas.y) / 255.0
		buffer[base + 14] = encoded
		buffer[base + 15] = q["uv_w"]

	return buffer


static func _build_ramp_buffer(data: ChunkData, quads: Array, ramp_kind: String) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	if quads.is_empty():
		return buffer

	var ws = _WorldSettings.get_active()
	buffer.resize(quads.size() * STRIDE)
	var face_code := FACE_RAMP
	if ramp_kind == "diagonal":
		face_code = FACE_RAMP_SIDE

	for i in quads.size():
		var q = quads[i]
		var base: int = i * STRIDE
		var dir := Vector2i(int(q.get("ramp_dir_x", 1)), int(q.get("ramp_dir_z", 0)))
		var world_x := float(q["x"]) + float(data.position.x * ChunkData.SIZE)
		var world_z := float(q["z"]) + float(data.position.y * ChunkData.SIZE)
		var surface_y: float = float(q["y"])
		var xform: Transform3D
		if ramp_kind == "diagonal":
			var leg_x: int = int(q.get("ramp_dir_x", 1))
			var leg_z: int = int(q.get("ramp_dir2_z", 1))
			xform = _TerrainRamps.concave_corner_prism_transform(world_x, world_z, surface_y, leg_x, leg_z)
		else:
			xform = _TerrainRamps.wedge_transform(world_x, world_z, surface_y, dir)
		var b := xform.basis
		var o := xform.origin

		buffer[base + 0] = b.x.x; buffer[base + 1] = b.y.x; buffer[base + 2] = b.z.x; buffer[base + 3] = o.x
		buffer[base + 4] = b.x.y; buffer[base + 5] = b.y.y; buffer[base + 6] = b.z.y; buffer[base + 7] = o.y
		buffer[base + 8] = b.x.z; buffer[base + 9] = b.y.z; buffer[base + 10] = b.z.z; buffer[base + 11] = o.z

		var atlas = VoxelTypes.ATLAS_COORDS.get(q["type"], Vector2i(6, 0))
		var encoded: float = float(face_code) + (q["uv_h"] / 100.0)
		buffer[base + 12] = float(atlas.x) / 255.0
		buffer[base + 13] = float(atlas.y) / 255.0
		buffer[base + 14] = encoded
		buffer[base + 15] = q["uv_w"]

	return buffer