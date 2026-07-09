# Inside ChunkView.gd
extends Node3D
class_name ChunkView

const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _CHUNK_MATERIAL_RES: ShaderMaterial = preload("res://shaders/ChunkView.tres")
const _ATLAS_TEX: Texture2D = preload("res://assets/tiles/Cube.png")

@export var chunk_material: ShaderMaterial
@onready var layer_container: Node3D = $LayerContainer

var chunk_data: ChunkData
var mesh_data: Dictionary

const FACE_RAMP := 7
const FACE_RAMP_CORNER := 8
const FACE_RAMP_SIDE := 9

static var _shared_box_mesh: BoxMesh
static var _shared_ramp_material: ShaderMaterial
static var _shared_chunk_material: ShaderMaterial


func _ready() -> void:
	_ensure_chunk_material()


func _ensure_chunk_material() -> void:
	if _shared_chunk_material == null:
		var seed_mat: ShaderMaterial = null
		if chunk_material != null and chunk_material.shader != null:
			seed_mat = chunk_material
		else:
			seed_mat = _CHUNK_MATERIAL_RES
		_shared_chunk_material = seed_mat.duplicate() as ShaderMaterial
	_bind_chunk_atlas(_shared_chunk_material)
	chunk_material = _shared_chunk_material


static func _bind_chunk_atlas(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	var atlas: Texture2D = _ATLAS_TEX
	if atlas == null or atlas.get_width() <= 0:
		atlas = _CHUNK_MATERIAL_RES.get_shader_parameter("texture_atlas") as Texture2D
	if atlas != null:
		mat.set_shader_parameter("texture_atlas", atlas)
	mat.set_shader_parameter("atlas_grid", _VoxelTypes.atlas_grid_vec2())


func setup(data: ChunkData, mesh_data: Dictionary):
	layer_container = $LayerContainer if $LayerContainer else get_node_or_null("LayerContainer")
	_ensure_chunk_material()

	chunk_data = data
	self.mesh_data = mesh_data
	emit_quads()


func _exit_tree() -> void:
	if layer_container and is_instance_valid(layer_container):
		for child in layer_container.get_children():
			if is_instance_valid(child):
				layer_container.remove_child(child)
				child.queue_free()


func emit_quads():
	_ensure_chunk_material()
	if layer_container == null:
		return
	for child in layer_container.get_children():
		if is_instance_valid(child):
			layer_container.remove_child(child)
			child.queue_free()

	if mesh_data.get("count", 0) == 0:
		return

	if mesh_data.has("terrain_buffer"):
		_upload_prebuilt_buffers()
		return

	var quads: Array = mesh_data["quads"]
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

	_emit_box_multimesh(terrain_quads)
	_emit_ramp_multimesh(ramp_quads, "cardinal")
	_emit_ramp_multimesh(corner_quads, "corner")
	_emit_ramp_multimesh(diagonal_quads, "diagonal")


func _upload_prebuilt_buffers() -> void:
	var terrain_count: int = int(mesh_data.get("terrain_count", 0))
	if terrain_count > 0:
		_assign_buffer_multimesh(
			mesh_data.get("terrain_buffer", PackedFloat32Array()),
			terrain_count,
			"mm_instance",
			"box"
		)
	var ramp_count: int = int(mesh_data.get("ramp_count", 0))
	if ramp_count > 0:
		_assign_buffer_multimesh(
			mesh_data.get("ramp_buffer", PackedFloat32Array()),
			ramp_count,
			"cardinal_mm_instance",
			"cardinal"
		)
	var corner_count: int = int(mesh_data.get("corner_count", 0))
	if corner_count > 0:
		_assign_buffer_multimesh(
			mesh_data.get("corner_buffer", PackedFloat32Array()),
			corner_count,
			"corner_mm_instance",
			"corner"
		)
	var diagonal_count: int = int(mesh_data.get("diagonal_count", 0))
	if diagonal_count > 0:
		_assign_buffer_multimesh(
			mesh_data.get("diagonal_buffer", PackedFloat32Array()),
			diagonal_count,
			"diagonal_mm_instance",
			"diagonal"
		)


func _assign_buffer_multimesh(
	buffer: PackedFloat32Array,
	count: int,
	node_name: String,
	mesh_kind: String
) -> void:
	if count <= 0 or buffer.is_empty():
		return

	var mm_instance := MultiMeshInstance3D.new()
	mm_instance.name = node_name
	if mesh_kind != "box":
		mm_instance.sorting_offset = 1.0
	layer_container.add_child(mm_instance)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	match mesh_kind:
		"diagonal":
			mm.mesh = _TerrainRamps.get_concave_corner_prism_mesh()
		"corner":
			mm.mesh = _TerrainRamps.get_corner_step_mesh()
		"cardinal":
			mm.mesh = _TerrainRamps.get_wedge_mesh()
		_:
			if _shared_box_mesh == null:
				_shared_box_mesh = BoxMesh.new()
				_shared_box_mesh.size = Vector3.ONE
			mm.mesh = _shared_box_mesh
	mm.instance_count = count
	mm.buffer = buffer
	mm_instance.multimesh = mm

	if chunk_material:
		if mesh_kind == "box":
			mm_instance.material_override = chunk_material
		else:
			if _shared_ramp_material == null:
				_shared_ramp_material = chunk_material.duplicate()
				_bind_chunk_atlas(_shared_ramp_material)
			mm_instance.material_override = _shared_ramp_material


func _emit_box_multimesh(quads: Array) -> void:
	if quads.is_empty():
		return

	var mm_instance := MultiMeshInstance3D.new()
	mm_instance.name = "mm_instance"
	layer_container.add_child(mm_instance)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var ws = _WorldSettings.get_active()
	var voxel_s: float = ws.voxel_scale
	if _shared_box_mesh == null:
		_shared_box_mesh = BoxMesh.new()
		_shared_box_mesh.size = Vector3.ONE
	mm.mesh = _shared_box_mesh
	mm.instance_count = quads.size()
	mm_instance.multimesh = mm

	if chunk_material:
		mm_instance.material_override = chunk_material

	var chunk_offset_x: float = ws.column_to_world(float(chunk_data.position.x * ChunkData.SIZE))
	var chunk_offset_z: float = ws.column_to_world(float(chunk_data.position.y * ChunkData.SIZE))
	var stride := 16
	var buffer := PackedFloat32Array()
	buffer.resize(quads.size() * stride)

	for i in quads.size():
		var q = quads[i]
		var base: int = i * stride
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

		_write_atlas_custom(buffer, base, q)

	mm.buffer = buffer


func _emit_ramp_multimesh(quads: Array, ramp_kind: String = "cardinal") -> void:
	if quads.is_empty():
		return

	var mm_instance := MultiMeshInstance3D.new()
	mm_instance.name = "%s_mm_instance" % ramp_kind
	mm_instance.sorting_offset = 1.0
	layer_container.add_child(mm_instance)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	match ramp_kind:
		"diagonal":
			mm.mesh = _TerrainRamps.get_concave_corner_prism_mesh()
		"corner":
			mm.mesh = _TerrainRamps.get_corner_step_mesh()
		_:
			mm.mesh = _TerrainRamps.get_wedge_mesh()
	mm.instance_count = quads.size()
	mm_instance.multimesh = mm

	if chunk_material:
		if _shared_ramp_material == null:
			_shared_ramp_material = chunk_material.duplicate()
			_bind_chunk_atlas(_shared_ramp_material)
			_shared_ramp_material.render_priority = 1
		mm_instance.material_override = _shared_ramp_material

	var ws = _WorldSettings.get_active()
	var chunk_offset_x: float = ws.column_to_world(float(chunk_data.position.x * ChunkData.SIZE))
	var chunk_offset_z: float = ws.column_to_world(float(chunk_data.position.y * ChunkData.SIZE))
	var stride := 16
	var buffer := PackedFloat32Array()
	buffer.resize(quads.size() * stride)
	var face_code := FACE_RAMP
	if ramp_kind == "diagonal":
		face_code = FACE_RAMP_SIDE
	elif ramp_kind == "corner":
		face_code = FACE_RAMP_CORNER

	for i in quads.size():
		var q = quads[i]
		var base: int = i * stride
		var dir := Vector2i(int(q.get("ramp_dir_x", 1)), int(q.get("ramp_dir_z", 0)))
		var world_x := float(q["x"]) + float(chunk_data.position.x * ChunkData.SIZE)
		var world_z := float(q["z"]) + float(chunk_data.position.y * ChunkData.SIZE)
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

		_write_atlas_custom(buffer, base, q, face_code)

	mm.buffer = buffer


static func _write_atlas_custom(
	buffer: PackedFloat32Array,
	base: int,
	quad: Dictionary,
	face_code_override: int = -1
) -> void:
	var face_code: int = face_code_override if face_code_override >= 0 else int(quad.get("face_code", 0))
	var tile_type: int = int(quad.get("type", _VoxelTypes.AIR))
	var atlas: Vector2i = _VoxelTypes.get_atlas_coord_for_face(tile_type, face_code)
	var encoded: float = float(face_code) + (float(quad.get("uv_h", 1.0)) / 100.0)
	buffer[base + 12] = float(atlas.x) / 255.0
	buffer[base + 13] = float(atlas.y) / 255.0
	buffer[base + 14] = encoded
	buffer[base + 15] = float(quad.get("uv_w", 1.0))
