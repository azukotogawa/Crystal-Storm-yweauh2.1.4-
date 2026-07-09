class_name CrystalChunkLayer
extends Node3D

const _CrystalClusterMesh = preload("res://helpers/crystal_cluster_mesh.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

var chunk_coord: Vector2i = Vector2i.ZERO
var _mm_instance: MultiMeshInstance3D
var _material: Material
var _pos_to_index: Dictionary = {}


func has_cell(pos: Vector2i) -> bool:
	return _pos_to_index.has(pos)


func setup(coord: Vector2i, material: Material) -> void:
	chunk_coord = coord
	_material = material
	var ws = _WorldSettings.get_active()
	position = Vector3(
		ws.column_to_world(float(coord.x * ChunkData.SIZE)),
		0.0,
		ws.column_to_world(float(coord.y * ChunkData.SIZE))
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
		mm.mesh = _CrystalClusterMesh.get_mesh()
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


func _cell_yaw(pos: Vector2i) -> float:
	var seed_val := pos.x * 92837111 ^ pos.y * 1234567
	return float(seed_val & 0xffff) / 65535.0 * TAU


func _apply_cell_transform(mm: MultiMesh, idx: int, cell: CrystalCell) -> void:
	var ws = _WorldSettings.get_active()
	var voxel_s: float = ws.voxel_scale
	var depth := maxf(cell.depth, 0.12)
	var layer_h: float = ws.layer_height()
	var visual_depth := maxf(depth, layer_h * 0.55)
	var footprint := voxel_s * 0.96
	var scale_y := visual_depth / voxel_s
	var center_y := cell.terrain_y + visual_depth * 0.5
	var chunk_origin_x: float = ws.column_to_world(float(chunk_coord.x * ChunkData.SIZE))
	var chunk_origin_z: float = ws.column_to_world(float(chunk_coord.y * ChunkData.SIZE))
	var local_x: float = ws.column_to_world(float(cell.world_pos.x) + 0.5) - chunk_origin_x
	var local_z: float = ws.column_to_world(float(cell.world_pos.y) + 0.5) - chunk_origin_z
	var yaw := _cell_yaw(cell.world_pos)
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3(footprint, scale_y, footprint))
	mm.set_instance_transform(
		idx,
		Transform3D(
			basis,
			Vector3(local_x, center_y, local_z)
		)
	)