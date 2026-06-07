# Inside ChunkView.gd
extends Node3D
class_name ChunkView

@export var chunk_material: ShaderMaterial
@onready var layer_container: Node3D = $LayerContainer

var chunk_data: ChunkData
var packed_data: Dictionary

# ─────────────────────────────────────────────
# PUBLIC ENTRY
# ─────────────────────────────────────────────
func setup(data: ChunkData, mesh_data: Dictionary):
	layer_container = $LayerContainer if $LayerContainer else get_node_or_null("LayerContainer")
	
	chunk_data = data
	packed_data = mesh_data
	emit_quads()

# ─────────────────────────────────────────────
# RENDER
# ─────────────────────────────────────────────
func emit_quads():
	for child in layer_container.get_children():
		child.queue_free()

	# If the background thread found zero visible solid quads, skip rendering
	if packed_data.get("count", 0) == 0:
		return

	var mm_instance := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()

	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	
	# 1. Initialize count bounds
	var instance_count = packed_data["count"]
	mm.instance_count = instance_count

	var mesh := BoxMesh.new()
	mesh.size = Vector3(1, 1, 1)
	mm.mesh = mesh
	mm_instance.multimesh = mm

	if chunk_material:
		mm_instance.material_override = chunk_material

	layer_container.add_child(mm_instance)

	# 2. Assign arrays instantly to hardware buffers (Zero loop stutters on Main Thread!)
	# We use native bulk array methods for optimal performance.
	for i in range(instance_count):
		mm.set_instance_transform(i, packed_data["transforms"][i])
		
	mm.custom_data_array = packed_data["custom_colors"]
