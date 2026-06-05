extends Node3D
class_name ChunkView

@export var chunk_material: ShaderMaterial
@onready var layer_container: Node3D = $LayerContainer

var chunk_data: ChunkData
var quads := []

const SIZE := ChunkData.SIZE
const HEIGHT := ChunkData.HEIGHT

# ─────────────────────────────────────────────
# PUBLIC ENTRY
# ─────────────────────────────────────────────
func setup(data: ChunkData, mesh_data: Array):
	chunk_data = data
	quads = mesh_data
	emit_quads()

# ─────────────────────────────────────────────
# RENDER
# ─────────────────────────────────────────────
func emit_quads():
	for child in layer_container.get_children():
		child.queue_free()

	if quads.is_empty():
		return

	var chunk_offset_x = chunk_data.position.x * ChunkData.SIZE
	var chunk_offset_y = chunk_data.position.y * ChunkData.SIZE

	var mm_instance := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()

	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.instance_count = quads.size()

	var mesh := BoxMesh.new()
	mesh.size = Vector3(1, 1, 1)

	mm.mesh = mesh
	mm_instance.multimesh = mm

	if chunk_material:
		mm_instance.material_override = chunk_material

	layer_container.add_child(mm_instance)

	for i in range(quads.size()):
		var q = quads[i]

		var world_x = float(q.x + chunk_offset_x)
		var world_y = float(q.y + chunk_offset_y)
		var world_z = float(q.z)

		var t := Transform3D.IDENTITY
		var basis := Basis()

		basis = basis.scaled(
			Vector3(
				q.w,
				1.0,
				q.h
			)
		)

		t.basis = basis
		
		t.origin = Vector3(
			world_x + q.w * 0.5,
			world_z,
			world_y + q.h * 0.5
		)

		mm.set_instance_transform(i, t)

		var atlas := get_atlas_coord(q.type)
		var face = q.face
		mm.set_instance_custom_data(
			i,
			Color(
				atlas.x / 255.0,
				atlas.y / 255.0,
				face,
				0.0
			)
		)

# ─────────────────────────────────────────────
# ATLAS LOOKUP
# ─────────────────────────────────────────────
func get_atlas_coord(voxel_type: int) -> Vector2i:
	if voxel_type == VoxelTypes.AIR:
		return Vector2i(6, 0)

	return VoxelTypes.ATLAS_COORDS.get(voxel_type, Vector2i(6, 0))
