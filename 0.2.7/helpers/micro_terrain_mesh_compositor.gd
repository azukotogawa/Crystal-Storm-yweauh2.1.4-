class_name MicroTerrainMeshCompositor
extends RefCounted
## Authoritative micro-column mesh emission; macro greedy defers via build_skip_set.


const FACE_NEG_X := 3
const FACE_POS_X := 4
const FACE_NEG_Z := 5
const FACE_POS_Z := 6


static func build_skip_set(data: ChunkData, rect: Rect2i) -> Dictionary:
	if data == null or not data.is_micro_terrain_enabled() or data.micro_grid == null:
		return {}
	var out: Dictionary = {}
	for cell_variant in data.micro_grid.micro_cells_in_rect(rect):
		out[cell_variant] = true
	return out


static func compose(
	data: ChunkData,
	rect: Rect2i,
	out_quads: Array,
	cm,
	skip_set: Dictionary
) -> int:
	if data == null or skip_set.is_empty() or cm == null:
		return 0
	var cells_meshed := 0
	for key_variant in skip_set.keys():
		var key: Vector2i = key_variant
		if emit_micro_column_mesh(data, key.x, key.y, out_quads, cm):
			cells_meshed += 1
	return cells_meshed


static func emit_micro_column_mesh(
	data: ChunkData,
	lx: int,
	lz: int,
	out_quads: Array,
	cm
) -> bool:
	if data == null or cm == null or data.has_ramp(lx, lz):
		return false
	var x1: int = lx + 1
	var z1: int = lz + 1
	cm._emit_dug_strata_region(data, out_quads, lx, lz, x1, z1)
	cm._emit_build_strata_region(data, out_quads, lx, lz, x1, z1)
	cm._emit_single_surface_top_quad(data, out_quads, lx, lz)
	cm._greedy_mesh_plane_region(data, Vector3i(0, -1, 0), 6, out_quads, lx, lz, x1, z1)
	cm._greedy_mesh_plane_region(data, Vector3i(0, -1, 0), 4, out_quads, lx, lz, x1, z1)
	cm._emit_surface_side_walls_region(data, Vector3i(-1, 0, 0), FACE_NEG_X, out_quads, lx, lz, x1, z1)
	cm._emit_surface_side_walls_region(data, Vector3i(1, 0, 0), FACE_POS_X, out_quads, lx, lz, x1, z1)
	cm._emit_surface_side_walls_region(data, Vector3i(0, 0, -1), FACE_NEG_Z, out_quads, lx, lz, x1, z1)
	cm._emit_surface_side_walls_region(data, Vector3i(0, 0, 1), FACE_POS_Z, out_quads, lx, lz, x1, z1)
	return true