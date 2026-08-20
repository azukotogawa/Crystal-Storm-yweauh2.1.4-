class_name CrystalChunkLayer
extends Node3D

const _WorldSettings = preload("res://config/world_settings.gd")
const _CrystalClusterMesh = preload("res://helpers/crystal_cluster_mesh.gd")

var chunk_coord: Vector2i = Vector2i.ZERO
var lod_tier: int = _CrystalClusterMesh.LOD_FULL
var _mm_instance: MultiMeshInstance3D
var _material: StandardMaterial3D
var _pos_to_index: Dictionary = {}
## Last terrain_y applied into MultiMesh for each cell (presentation diagnostics / verifies).
var _applied_terrain_y: Dictionary = {}
var _mesh_lod_cached: int = -1
var _legacy_mesh_cached: bool = false
static var _shared_box_mesh: BoxMesh


func has_cell(pos: Vector2i) -> bool:
	return _pos_to_index.has(pos)


## Presentation diagnostic: MultiMesh instance center Y for a crystal cell (local to layer).
## Returns -99999.0 if the cell is not currently instanced.
func get_cell_instance_center_y(pos: Vector2i) -> float:
	if _mm_instance == null or _mm_instance.multimesh == null:
		return -99999.0
	var idx: int = int(_pos_to_index.get(pos, -1))
	if idx < 0:
		return -99999.0
	return _mm_instance.multimesh.get_instance_transform(idx).origin.y


## Terrain floor last written into the MultiMesh transform path for this cell.
func get_applied_terrain_y(pos: Vector2i) -> float:
	return float(_applied_terrain_y.get(pos, -99999.0))


func setup(coord: Vector2i, material: StandardMaterial3D) -> void:
	chunk_coord = coord
	_material = material
	var ws = _WorldSettings.get_active()
	position = Vector3(
		ws.column_to_world(float(coord.x * ChunkData.SIZE)),
		0.0,
		ws.column_to_world(float(coord.y * ChunkData.SIZE))
	)


func rebuild(cells: Array, p_lod_tier: int = _CrystalClusterMesh.LOD_FULL) -> void:
	lod_tier = p_lod_tier
	if _mm_instance == null:
		_mm_instance = MultiMeshInstance3D.new()
		_mm_instance.name = "CrystalFluid"
		add_child(_mm_instance)

	var mm := _mm_instance.multimesh
	if mm == null:
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = false
		_mm_instance.multimesh = mm

	_ensure_mesh_for_mode(mm)

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


func uses_procedural_mesh() -> bool:
	return not _CrystalClusterMesh.use_legacy_renderer()


func _ensure_mesh_for_mode(mm: MultiMesh) -> void:
	var legacy := _CrystalClusterMesh.use_legacy_renderer()
	if legacy == _legacy_mesh_cached and (legacy or _mesh_lod_cached == lod_tier):
		return
	_legacy_mesh_cached = legacy
	_mesh_lod_cached = lod_tier
	if legacy:
		if _shared_box_mesh == null:
			_shared_box_mesh = BoxMesh.new()
			_shared_box_mesh.size = Vector3.ONE
		mm.mesh = _shared_box_mesh
	else:
		mm.mesh = _CrystalClusterMesh.get_mesh_for_lod(lod_tier)


func _apply_cell_transform(mm: MultiMesh, idx: int, cell: CrystalCell) -> void:
	var ws = _WorldSettings.get_active()
	var voxel_s: float = ws.voxel_scale
	var depth := maxf(cell.depth, 0.12)
	var layer_h: float = ws.layer_height()
	# Frontier cells read as a taller, wider purple front without changing sim depth.
	var frontier_boost: float = 1.0
	var footprint_mul: float = 1.0
	if cell.is_frontier:
		frontier_boost = 1.38
		footprint_mul = 1.16
	var visual_depth := maxf(depth, layer_h * 0.55) * frontier_boost
	var chunk_origin_x: float = ws.column_to_world(float(chunk_coord.x * ChunkData.SIZE))
	var chunk_origin_z: float = ws.column_to_world(float(chunk_coord.y * ChunkData.SIZE))
	var local_x: float = ws.column_to_world(float(cell.world_pos.x) + 0.5) - chunk_origin_x
	var local_z: float = ws.column_to_world(float(cell.world_pos.y) + 0.5) - chunk_origin_z
	_applied_terrain_y[cell.world_pos] = cell.terrain_y

	var basis: Basis
	if _CrystalClusterMesh.use_legacy_renderer():
		var footprint := voxel_s * 1.02 * footprint_mul
		var center_y := cell.terrain_y + visual_depth * 0.5
		basis = Basis.IDENTITY.scaled(Vector3(footprint, visual_depth, footprint))
		mm.set_instance_transform(idx, Transform3D(basis, Vector3(local_x, center_y, local_z)))
		return

	var natural_h := _CrystalClusterMesh.natural_height()
	var footprint := 1.02 * footprint_mul
	var scale_y := visual_depth / natural_h
	var rot_y := _CrystalClusterMesh.growth_rotation_y(cell.neighbor_mask)
	var center_y := cell.terrain_y + visual_depth * 0.5
	basis = Basis.from_euler(Vector3(0.0, rot_y, 0.0)).scaled(Vector3(footprint, scale_y, footprint))
	mm.set_instance_transform(idx, Transform3D(basis, Vector3(local_x, center_y, local_z)))