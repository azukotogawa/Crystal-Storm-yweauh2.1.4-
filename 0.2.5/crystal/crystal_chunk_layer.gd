class_name CrystalChunkLayer
extends Node3D

var chunk_coord: Vector2i = Vector2i.ZERO
var _mm_instance: MultiMeshInstance3D
var _material: StandardMaterial3D
static var _shared_box_mesh: BoxMesh


func setup(coord: Vector2i, material: StandardMaterial3D) -> void:
	chunk_coord = coord
	_material = material
	position = Vector3(
		float(coord.x * ChunkData.SIZE),
		0.0,
		float(coord.y * ChunkData.SIZE)
	)


func rebuild(cells: Array) -> void:
	if _mm_instance == null:
		_mm_instance = MultiMeshInstance3D.new()
		_mm_instance.name = "CrystalFluid"
		add_child(_mm_instance)

	var mm := _mm_instance.multimesh
	if mm == null:
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = false
		if _shared_box_mesh == null:
			_shared_box_mesh = BoxMesh.new()
			_shared_box_mesh.size = Vector3.ONE
		mm.mesh = _shared_box_mesh
		_mm_instance.multimesh = mm

	if _material:
		_mm_instance.material_override = _material

	var count := cells.size()
	if count == 0:
		mm.instance_count = 0
		visible = false
		return

	visible = true
	if mm.instance_count != count:
		mm.instance_count = count

	for i in count:
		var cell: CrystalCell = cells[i]
		var depth := maxf(cell.depth, 0.12)
		var scale_y := depth
		var center_y := cell.terrain_y + depth * 0.5
		var pulse := 0.94 + clampf(depth / 4.0, 0.0, 1.0) * 0.06
		var basis := Basis.IDENTITY.scaled(Vector3(pulse, scale_y, pulse))
		mm.set_instance_transform(
			i,
			Transform3D(
				basis,
				Vector3(float(cell.world_pos.x) + 0.5, center_y, float(cell.world_pos.y) + 0.5)
			)
		)