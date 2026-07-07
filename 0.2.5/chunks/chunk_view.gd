# Inside ChunkView.gd
extends Node3D
class_name ChunkView

const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

@export var chunk_material: ShaderMaterial
@onready var layer_container: Node3D = $LayerContainer

var chunk_data: ChunkData
var mesh_data: Dictionary

const FACE_RAMP := 7
const FACE_RAMP_CORNER := 8
const FACE_RAMP_SIDE := 9


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
	var diagonal_quads: Array = []

	for q in quads:
		var face_code := int(q.get("face_code", 0))
		if face_code == FACE_RAMP:
			ramp_quads.append(q)
		elif face_code == FACE_RAMP_SIDE:
			diagonal_quads.append(q)
		else:
			terrain_quads.append(q)

	_emit_box_multimesh(terrain_quads)
	_emit_ramp_multimesh(ramp_quads, "cardinal")
	_emit_ramp_multimesh(diagonal_quads, "diagonal")


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
	mm.mesh = BoxMesh.new()
	mm.mesh.size = Vector3.ONE
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

		var atlas = VoxelTypes.ATLAS_COORDS.get(q["type"], Vector2i(6, 0))
		var encoded = float(q["face_code"]) + (q["uv_h"] / 100.0)
		buffer[base + 12] = float(atlas.x) / 255.0
		buffer[base + 13] = float(atlas.y) / 255.0
		buffer[base + 14] = encoded
		buffer[base + 15] = q["uv_w"]

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
		_:
			mm.mesh = _TerrainRamps.get_wedge_mesh()
	mm.instance_count = quads.size()
	mm_instance.multimesh = mm

	if chunk_material:
		var mat: ShaderMaterial = chunk_material.duplicate()
		mat.render_priority = 1
		mm_instance.material_override = mat

	var ws = _WorldSettings.get_active()
	var chunk_offset_x: float = ws.column_to_world(float(chunk_data.position.x * ChunkData.SIZE))
	var chunk_offset_z: float = ws.column_to_world(float(chunk_data.position.y * ChunkData.SIZE))
	var stride := 16
	var buffer := PackedFloat32Array()
	buffer.resize(quads.size() * stride)
	var face_code := FACE_RAMP
	if ramp_kind == "diagonal":
		face_code = FACE_RAMP_SIDE

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

	mm.buffer = buffer
