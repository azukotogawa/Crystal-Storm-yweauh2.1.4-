# Inside ChunkView.gd
extends Node3D
class_name ChunkView

@export var chunk_material: ShaderMaterial
@onready var layer_container: Node3D = $LayerContainer

var chunk_data: ChunkData
var mesh_data: Dictionary


func setup(data: ChunkData, mesh_data: Dictionary):
	layer_container = $LayerContainer if $LayerContainer else get_node_or_null("LayerContainer")

	chunk_data = data
	self.mesh_data = mesh_data
	emit_quads()


func emit_quads():
	for child in layer_container.get_children():
		child.queue_free()

	if mesh_data.get("count", 0) == 0:
		return

	var quads: Array = mesh_data["quads"]
	_emit_box_multimesh(quads)


func _emit_box_multimesh(quads: Array) -> void:
	if quads.is_empty():
		return

	var mm_instance := MultiMeshInstance3D.new()
	mm_instance.name = "mm_instance"
	layer_container.add_child(mm_instance)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = BoxMesh.new()
	mm.mesh.size = Vector3.ONE
	mm.instance_count = quads.size()
	mm_instance.multimesh = mm

	if chunk_material:
		mm_instance.material_override = chunk_material

	var chunk_offset_x := float(chunk_data.position.x * ChunkData.SIZE)
	var chunk_offset_z := float(chunk_data.position.y * ChunkData.SIZE)
	var stride := 16
	var buffer := PackedFloat32Array()
	buffer.resize(quads.size() * stride)

	for i in quads.size():
		var q = quads[i]
		var base: int = i * stride
		var sx = q["dim_x"]
		var sy = q["dim_y"]
		var sz = q["dim_z"]
		var ox = float(q["x"]) + chunk_offset_x + sx * 0.5
		var oy = float(q["y"]) + sy * 0.5
		var oz = float(q["z"]) + chunk_offset_z + sz * 0.5

		buffer[base + 0] = sx; buffer[base + 1] = 0;  buffer[base + 2] = 0;  buffer[base + 3] = ox
		buffer[base + 4] = 0;  buffer[base + 5] = sy; buffer[base + 6] = 0;  buffer[base + 7] = oy
		buffer[base + 8] = 0;  buffer[base + 9] = 0;  buffer[base + 10] = sz; buffer[base + 11] = oz

		var atlas = VoxelTypes.ATLAS_COORDS.get(q["type"], Vector2i(6, 0))
		var encoded = float(q["face_code"]) + (q["uv_h"] / 100.0)
		buffer[base + 12] = float(atlas.x) / 255.0
		buffer[base + 13] = float(atlas.y) / 255.0
		buffer[base + 14] = encoded
		buffer[base + 15] = q["uv_w"]

	mm.buffer = buffer
