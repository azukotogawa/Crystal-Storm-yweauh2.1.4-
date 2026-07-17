class_name ChunkMeshBufferBuilder
extends RefCounted

const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _TerrainSurfaceCache = preload("res://helpers/terrain_surface_cache.gd")



const FACE_RAMP := 7
const FACE_RAMP_CORNER := 8
const FACE_RAMP_SIDE := 9
const STRIDE := 16


static func build_mesh_payload(
	data: ChunkData,
	quads: Array,
	use_surface_mesh: bool = false,
	prior_surface_cache: Dictionary = {},
	incremental: bool = false,
	keep_quads: Array = [],
	patch_quads: Array = []
) -> Dictionary:
	var terrain_quads: Array = []
	var ramp_quads: Array = []
	var corner_quads: Array = []
	var diagonal_quads: Array = []

	for q in quads:
		var face_code := int(q.get("face_code", 0))
		if face_code == FACE_RAMP:
			ramp_quads.append(q)
		elif face_code == FACE_RAMP_CORNER:
			corner_quads.append(q)
		elif face_code == FACE_RAMP_SIDE:
			diagonal_quads.append(q)
		else:
			terrain_quads.append(q)

	var payload := {
		"quads": quads,
		"count": quads.size(),
		"terrain_buffer": PackedFloat32Array(),
		"terrain_count": terrain_quads.size(),
		"ramp_buffer": _build_ramp_buffer(data, ramp_quads, "cardinal"),
		"ramp_count": ramp_quads.size(),
		"corner_buffer": _build_ramp_buffer(data, corner_quads, "corner"),
		"corner_count": corner_quads.size(),
		"diagonal_buffer": _build_ramp_buffer(data, diagonal_quads, "diagonal"),
		"diagonal_count": diagonal_quads.size(),
	}
	payload["representation"] = "surface_mesh" if use_surface_mesh else "multimesh_legacy"
	if use_surface_mesh and incremental and not prior_surface_cache.is_empty():
		payload["terrain_buffer"] = PackedFloat32Array()
		var cache: Dictionary = prior_surface_cache
		if _TerrainSurfaceCache.incremental_patch_needed(prior_surface_cache, patch_quads, keep_quads):
			cache = _TerrainSurfaceCache.patch_region(
				prior_surface_cache, data, patch_quads, keep_quads
			)
		# Defer ArrayMesh build to main-thread surface upload drain.
		_TerrainSurfaceCache.attach_to_payload(cache, payload, false)
	elif use_surface_mesh:
		payload["terrain_buffer"] = PackedFloat32Array()
		var cache_full := _TerrainSurfaceCache.build_from_quads(data, terrain_quads)
		_TerrainSurfaceCache.attach_to_payload(cache_full, payload, true)
	else:
		payload["terrain_buffer"] = _build_box_buffer(data, terrain_quads)
	return payload


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


static func _build_ramp_buffer(data: ChunkData, quads: Array, ramp_kind: String) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	if quads.is_empty():
		return buffer

	var ws = _WorldSettings.get_active()
	buffer.resize(quads.size() * STRIDE)
	var face_code := FACE_RAMP
	if ramp_kind == "diagonal":
		face_code = FACE_RAMP_SIDE
	elif ramp_kind == "corner":
		face_code = FACE_RAMP_CORNER

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
		elif ramp_kind == "corner":
			var dir_a := Vector2i(int(q.get("ramp_dir_x", 1)), int(q.get("ramp_dir_z", 0)))
			var dir_b := Vector2i(int(q.get("ramp_dir2_x", 0)), int(q.get("ramp_dir2_z", 1)))
			xform = _TerrainRamps.corner_ramp_transform(world_x, world_z, surface_y, dir_a, dir_b)
		else:
			xform = _TerrainRamps.wedge_transform(world_x, world_z, surface_y, dir)
		var b := xform.basis
		var o := xform.origin

		buffer[base + 0] = b.x.x; buffer[base + 1] = b.y.x; buffer[base + 2] = b.z.x; buffer[base + 3] = o.x
		buffer[base + 4] = b.x.y; buffer[base + 5] = b.y.y; buffer[base + 6] = b.z.y; buffer[base + 7] = o.y
		buffer[base + 8] = b.x.z; buffer[base + 9] = b.y.z; buffer[base + 10] = b.z.z; buffer[base + 11] = o.z

		ChunkView._write_atlas_custom(buffer, base, q, face_code)

	return buffer