class_name TerrainVertexAO
extends RefCounted

const _WorldSettings = preload("res://config/world_settings.gd")

const AO_EXPOSED := 1.0
const AO_ENCLOSED := 0.50
const HEIGHT_MISSING := -9000.0
const _STEP := 0.16

static var bake_enabled: bool = true


static func corner_ao(side_a: bool, side_b: bool, corner: bool) -> float:
	if side_a and side_b:
		return AO_ENCLOSED
	var level := int(side_a) + int(side_b) + int(corner)
	return clampf(AO_EXPOSED - float(level) * _STEP, AO_ENCLOSED, AO_EXPOSED)


static func neighbor_solid(neighbor: float, face_surface: float, layer: float) -> bool:
	if neighbor <= HEIGHT_MISSING:
		return false
	return neighbor >= face_surface + layer * 0.75


## Halo when it is filled, otherwise an in-chunk map read. Never calls the world.
static func sample_surface(data: ChunkData, lx: int, lz: int) -> float:
	if data == null:
		return HEIGHT_MISSING
	var halo := data.get_halo_surface_y(lx, lz)
	if halo > HEIGHT_MISSING:
		return halo
	if lx < 0 or lz < 0 or lx >= ChunkData.SIZE or lz >= ChunkData.SIZE:
		return HEIGHT_MISSING
	if not _column_readable(data):
		return HEIGHT_MISSING
	return data.get_surface_y(lx, lz)


static func top_corner_ao(
	data: ChunkData,
	col_x: int,
	col_z: int,
	dim_x: int,
	dim_z: int,
	face_surface: float
) -> Vector4:
	if not bake_enabled or data == null:
		return Vector4.ONE
	var dx := maxi(dim_x, 1)
	var dz := maxi(dim_z, 1)
	var layer := _layer()
	var a0 := _occ(data, col_x - 1, col_z, face_surface, layer)
	var b0 := _occ(data, col_x, col_z - 1, face_surface, layer)
	var c0 := _occ(data, col_x - 1, col_z - 1, face_surface, layer)
	var a1 := _occ(data, col_x + dx, col_z, face_surface, layer)
	var b1 := _occ(data, col_x + dx - 1, col_z - 1, face_surface, layer)
	var c1 := _occ(data, col_x + dx, col_z - 1, face_surface, layer)
	var a2 := _occ(data, col_x + dx, col_z + dz - 1, face_surface, layer)
	var b2 := _occ(data, col_x + dx - 1, col_z + dz, face_surface, layer)
	var c2 := _occ(data, col_x + dx, col_z + dz, face_surface, layer)
	var a3 := _occ(data, col_x - 1, col_z + dz - 1, face_surface, layer)
	var b3 := _occ(data, col_x, col_z + dz, face_surface, layer)
	var c3 := _occ(data, col_x - 1, col_z + dz, face_surface, layer)
	return Vector4(
		corner_ao(a0, b0, c0),
		corner_ao(a1, b1, c1),
		corner_ao(a2, b2, c2),
		corner_ao(a3, b3, c3)
	)


static func _occ(data: ChunkData, lx: int, lz: int, face_surface: float, layer: float) -> bool:
	return neighbor_solid(sample_surface(data, lx, lz), face_surface, layer)


static func _layer() -> float:
	var ws = _WorldSettings.get_active()
	if ws == null:
		return 2.0
	return maxf(ws.layer_height(), 0.001)


static func _column_readable(data: ChunkData) -> bool:
	if data.maps_materialized():
		return true
	if data.has_method("_has_resident_column_maps") and data._has_resident_column_maps():
		return true
	if data.has_method("_macro_active") and data._macro_active():
		return true
	return false
