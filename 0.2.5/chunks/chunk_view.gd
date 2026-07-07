# Inside ChunkView.gd
extends Node3D
class_name ChunkView

const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")

@export var chunk_material: ShaderMaterial
@onready var layer_container: Node3D = $LayerContainer

var chunk_data: ChunkData
var mesh_data: Dictionary

const FACE_RAMP := 7
const FACE_RAMP_CORNER := 8


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
	var terrain_quads: Array = []
	var ramp_quads: Array = []
	var corner_quads: Array = []

	for q in quads:
		var face_code := int(q.get("face_code", 0))
		if face_code == FACE_RAMP:
			ramp_quads.append(q)
		elif face_code == FACE_RAMP_CORNER:
			corner_quads.append(q)
		else:
			terrain_quads.append(q)

	_emit_box_multimesh(terrain_quads)
	_emit_ramp_multimesh(ramp_quads, false)
	_emit_ramp_multimesh(corner_quads, true)


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


func _emit_ramp_multimesh(quads: Array, is_corner: bool) -> void:
	if quads.is_empty():
		return

	var mm_instance := MultiMeshInstance3D.new()
	mm_instance.name = "corner_mm_instance" if is_corner else "ramp_mm_instance"
	mm_instance.sorting_offset = 1.0
	layer_container.add_child(mm_instance)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _TerrainRamps.get_corner_mesh() if is_corner else _TerrainRamps.get_wedge_mesh()
	mm.instance_count = quads.size()
	mm_instance.multimesh = mm

	if chunk_material:
		var mat: ShaderMaterial = chunk_material.duplicate()
		mat.render_priority = 1
		mm_instance.material_override = mat

	var chunk_offset_x := float(chunk_data.position.x * ChunkData.SIZE)
	var chunk_offset_z := float(chunk_data.position.y * ChunkData.SIZE)
	var stride := 16
	var buffer := PackedFloat32Array()
	buffer.resize(quads.size() * stride)
	var face_code := FACE_RAMP_CORNER if is_corner else FACE_RAMP

	for i in quads.size():
		var q = quads[i]
		var base: int = i * stride
		var dir := Vector2i(int(q.get("ramp_dir_x", 1)), int(q.get("ramp_dir_z", 0)))
		var wx := float(q["x"]) + chunk_offset_x
		var wz := float(q["z"]) + chunk_offset_z
		var base_y: float = float(q["y"])
		var xform: Transform3D
		if is_corner:
			var dir2 := Vector2i(int(q.get("ramp_dir2_x", 0)), int(q.get("ramp_dir2_z", 1)))
			xform = _TerrainRamps.corner_transform(wx, wz, base_y, dir, dir2)
		else:
			xform = _TerrainRamps.wedge_transform(wx, wz, base_y, dir)
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

	mm.buffer = buffer