class_name CrystalChunkLayer
extends Node3D

var chunk_coord: Vector2i = Vector2i.ZERO
var _mm_instance: MultiMeshInstance3D
var _material: StandardMaterial3D
var _pos_to_index: Dictionary = {}
static var _shared_box_mesh: BoxMesh


func has_cell(pos: Vector2i) -> bool:
	return _pos_to_index.has(pos)


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
		_pos_to_index.clear()
		visible = false
		return

	visible = true
	if mm.instance_count != count:
		mm.instance_count = count

	_pos_to_index.clear()
	for i in count:
		var cell: CrystalCell = cells[i]
		_pos_to_index[cell.world_pos] = i
		_apply_cell_transform(mm, i, cell)


func patch_cells(cells: Array) -> bool:
	if cells.is_empty():
		return true
	if _mm_instance == null:
		return false
	var mm := _mm_instance.multimesh
	if mm == null or mm.instance_count <= 0:
		return false

	var patched := 0
	for cell_variant in cells:
		var cell: CrystalCell = cell_variant
		var idx: int = int(_pos_to_index.get(cell.world_pos, -1))
		if idx < 0:
			return false
		_apply_cell_transform(mm, idx, cell)
		patched += 1
	return patched > 0


func _apply_cell_transform(mm: MultiMesh, idx: int, cell: CrystalCell) -> void:
	var depth := maxf(cell.depth, 0.12)
	var scale_y := depth
	var center_y := cell.terrain_y + depth * 0.5
	var pulse := 0.94 + clampf(depth / 4.0, 0.0, 1.0) * 0.06
	var basis := Basis.IDENTITY.scaled(Vector3(pulse, scale_y, pulse))
	mm.set_instance_transform(
		idx,
		Transform3D(
			basis,
			Vector3(float(cell.world_pos.x) + 0.5, center_y, float(cell.world_pos.y) + 0.5)
		)
	)
