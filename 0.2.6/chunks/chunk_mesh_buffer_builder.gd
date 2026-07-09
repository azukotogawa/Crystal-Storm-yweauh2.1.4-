class_name ChunkMeshBufferBuilder
extends RefCounted

const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _VoxelGeometryKind = preload("res://helpers/voxel_geometry_kind.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const FACE_RAMP := 7
const FACE_RAMP_CORNER := 8
const FACE_RAMP_SIDE := 9
const STRIDE := 16


static func build_mesh_payload(data: ChunkData, quads: Array) -> Dictionary:
	var grouped: Dictionary = {}
	for group_name in _VoxelGeometryKind.MESH_GROUP_ORDER:
		grouped[group_name] = []

	for q in quads:
		var group_name: StringName = _VoxelGeometryKind.mesh_group_for_quad(q)
		grouped[group_name].append(q)

	var mesh_groups: Array = []
	for group_name in _VoxelGeometryKind.MESH_GROUP_ORDER:
		var group_quads: Array = grouped[group_name]
		if group_quads.is_empty():
			continue
		var buffer: PackedFloat32Array
		if group_name == _VoxelGeometryKind.MESH_FULL_CUBE:
			buffer = _build_box_buffer(data, group_quads)
		else:
			buffer = _build_primitive_buffer(data, group_quads, group_name)
		mesh_groups.append({
			"kind": group_name,
			"count": group_quads.size(),
			"buffer": buffer,
		})

	return {
		"quads": quads,
		"count": quads.size(),
		"mesh_groups": mesh_groups,
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

		ChunkView._write_atlas_custom(buffer, base, q)

	return buffer


static func _build_primitive_buffer(data: ChunkData, quads: Array, group_name: StringName) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	if quads.is_empty():
		return buffer

	buffer.resize(quads.size() * STRIDE)
	var face_code := FACE_RAMP
	if str(group_name).begins_with("concave_"):
		face_code = FACE_RAMP_SIDE
	elif str(group_name).begins_with("corner_"):
		face_code = FACE_RAMP_CORNER

	for i in quads.size():
		var q = quads[i]
		var base: int = i * STRIDE
		var world_x := float(q["x"]) + float(data.position.x * ChunkData.SIZE)
		var world_z := float(q["z"]) + float(data.position.y * ChunkData.SIZE)
		var surface_y: float = float(q["y"])
		var xform: Transform3D
		xform = _TerrainRamps.voxel_transform(world_x, world_z, surface_y)
		var b := xform.basis
		var o := xform.origin

		buffer[base + 0] = b.x.x; buffer[base + 1] = b.y.x; buffer[base + 2] = b.z.x; buffer[base + 3] = o.x
		buffer[base + 4] = b.x.y; buffer[base + 5] = b.y.y; buffer[base + 6] = b.z.y; buffer[base + 7] = o.y
		buffer[base + 8] = b.x.z; buffer[base + 9] = b.y.z; buffer[base + 10] = b.z.z; buffer[base + 11] = o.z

		ChunkView._write_atlas_custom(buffer, base, q, face_code)

	return buffer