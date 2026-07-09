# Inside ChunkView.gd
extends Node3D
class_name ChunkView

const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _VoxelGeometryKind = preload("res://helpers/voxel_geometry_kind.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkMeshBufferBuilder = preload("res://chunks/chunk_mesh_buffer_builder.gd")
const _CHUNK_MATERIAL_RES: ShaderMaterial = preload("res://shaders/ChunkView.tres")
const _ATLAS_TEX: Texture2D = preload("res://assets/tiles/Cube.png")

@export var chunk_material: ShaderMaterial
@onready var layer_container: Node3D = $LayerContainer

var chunk_data: ChunkData
var mesh_data: Dictionary

static var _shared_box_mesh: BoxMesh
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

	if mesh_data.has("mesh_groups"):
		_upload_mesh_groups(mesh_data.get("mesh_groups", []))
		return

	var quads: Array = mesh_data.get("quads", [])
	if quads.is_empty():
		return
	var payload: Dictionary = _ChunkMeshBufferBuilder.build_mesh_payload(chunk_data, quads)
	_upload_mesh_groups(payload.get("mesh_groups", []))


func _upload_mesh_groups(groups: Array) -> void:
	for group in groups:
		var kind: StringName = group.get("kind", _VoxelGeometryKind.MESH_FULL_CUBE)
		var count: int = int(group.get("count", 0))
		var buffer: PackedFloat32Array = group.get("buffer", PackedFloat32Array())
		if count <= 0 or buffer.is_empty():
			continue
		var node_name := "mm_instance" if kind == _VoxelGeometryKind.MESH_FULL_CUBE else str(kind)
		_assign_buffer_multimesh(buffer, count, node_name, kind)


func _assign_buffer_multimesh(
	buffer: PackedFloat32Array,
	count: int,
	node_name: String,
	mesh_kind: StringName
) -> void:
	if count <= 0 or buffer.is_empty():
		return

	var mm_instance := MultiMeshInstance3D.new()
	mm_instance.name = node_name
	layer_container.add_child(mm_instance)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	match mesh_kind:
		_VoxelGeometryKind.MESH_HALF_CUBE:
			mm.mesh = _TerrainRamps.get_half_cube_mesh()
		_VoxelGeometryKind.MESH_RAMP_E:
			mm.mesh = _TerrainRamps.get_cardinal_ramp_mesh(Vector2i(1, 0))
		_VoxelGeometryKind.MESH_RAMP_W:
			mm.mesh = _TerrainRamps.get_cardinal_ramp_mesh(Vector2i(-1, 0))
		_VoxelGeometryKind.MESH_RAMP_S:
			mm.mesh = _TerrainRamps.get_cardinal_ramp_mesh(Vector2i(0, 1))
		_VoxelGeometryKind.MESH_RAMP_N:
			mm.mesh = _TerrainRamps.get_cardinal_ramp_mesh(Vector2i(0, -1))
		_VoxelGeometryKind.MESH_CORNER_ES:
			mm.mesh = _TerrainRamps.get_corner_ramp_mesh(Vector2i(1, 0), Vector2i(0, 1))
		_VoxelGeometryKind.MESH_CORNER_EN:
			mm.mesh = _TerrainRamps.get_corner_ramp_mesh(Vector2i(1, 0), Vector2i(0, -1))
		_VoxelGeometryKind.MESH_CORNER_WS:
			mm.mesh = _TerrainRamps.get_corner_ramp_mesh(Vector2i(-1, 0), Vector2i(0, 1))
		_VoxelGeometryKind.MESH_CORNER_WN:
			mm.mesh = _TerrainRamps.get_corner_ramp_mesh(Vector2i(-1, 0), Vector2i(0, -1))
		_VoxelGeometryKind.MESH_CONCAVE_PP:
			mm.mesh = _TerrainRamps.get_concave_corner_prism_mesh(1, 1)
		_VoxelGeometryKind.MESH_CONCAVE_PN:
			mm.mesh = _TerrainRamps.get_concave_corner_prism_mesh(1, -1)
		_VoxelGeometryKind.MESH_CONCAVE_NP:
			mm.mesh = _TerrainRamps.get_concave_corner_prism_mesh(-1, 1)
		_VoxelGeometryKind.MESH_CONCAVE_NN:
			mm.mesh = _TerrainRamps.get_concave_corner_prism_mesh(-1, -1)
		_:
			if _shared_box_mesh == null:
				_shared_box_mesh = BoxMesh.new()
				_shared_box_mesh.size = Vector3.ONE
			mm.mesh = _shared_box_mesh
	mm.instance_count = count
	mm.buffer = buffer
	mm_instance.multimesh = mm

	if chunk_material:
		mm_instance.material_override = chunk_material


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