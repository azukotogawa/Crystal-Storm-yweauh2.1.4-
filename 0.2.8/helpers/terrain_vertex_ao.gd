class_name TerrainVertexAO
extends RefCounted

const _WorldSettings = preload("res://config/world_settings.gd")

const AO_EXPOSED := 1.0
const AO_ENCLOSED := 0.50
const HEIGHT_MISSING := -9000.0
const _STEP := 0.16
const FACE_TOP := 0
const FACE_NEG_X := 3
const FACE_POS_X := 4
const FACE_NEG_Z := 5
const FACE_POS_Z := 6

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


static func face_corner_ao(
	data: ChunkData,
	face_code: int,
	col_x: int,
	col_z: int,
	dim_x: int,
	dim_z: int,
	face_y: float,
	dim_y: float
) -> Vector4:
	if face_code == FACE_TOP:
		return top_corner_ao(data, col_x, col_z, dim_x, dim_z, face_y)
	if not bake_enabled or data == null:
		return Vector4.ONE
	if face_code < FACE_NEG_X or face_code > FACE_POS_Z:
		return Vector4.ONE
	var dx := maxi(dim_x, 1)
	var dz := maxi(dim_z, 1)
	var layer := _layer()
	var y0 := face_y
	var y1 := face_y + maxf(dim_y, 0.001) * layer
	var x0 := col_x
	var z0 := col_z
	var x1 := col_x + dx - 1
	var z1 := col_z + dz - 1
	if face_code == FACE_NEG_X:
		return Vector4(
			_side_corner(data, x0, z1, -1, 0, 0, 1, y0, layer),
			_side_corner(data, x0, z1, -1, 0, 0, 1, y1, layer),
			_side_corner(data, x0, z0, -1, 0, 0, -1, y1, layer),
			_side_corner(data, x0, z0, -1, 0, 0, -1, y0, layer)
		)
	if face_code == FACE_POS_X:
		return Vector4(
			_side_corner(data, x1, z0, 1, 0, 0, -1, y0, layer),
			_side_corner(data, x1, z0, 1, 0, 0, -1, y1, layer),
			_side_corner(data, x1, z1, 1, 0, 0, 1, y1, layer),
			_side_corner(data, x1, z1, 1, 0, 0, 1, y0, layer)
		)
	if face_code == FACE_NEG_Z:
		return Vector4(
			_side_corner(data, x0, z0, 0, -1, -1, 0, y0, layer),
			_side_corner(data, x0, z0, 0, -1, -1, 0, y1, layer),
			_side_corner(data, x1, z0, 0, -1, 1, 0, y1, layer),
			_side_corner(data, x1, z0, 0, -1, 1, 0, y0, layer)
		)
	return Vector4(
		_side_corner(data, x1, z1, 0, 1, 1, 0, y0, layer),
		_side_corner(data, x1, z1, 0, 1, 1, 0, y1, layer),
		_side_corner(data, x0, z1, 0, 1, -1, 0, y1, layer),
		_side_corner(data, x0, z1, 0, 1, -1, 0, y0, layer)
	)


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


static func _side_corner(
	data: ChunkData,
	owner_x: int,
	owner_z: int,
	out_x: int,
	out_z: int,
	along_x: int,
	along_z: int,
	height: float,
	layer: float
) -> float:
	var front := _reaches(data, owner_x + out_x, owner_z + out_z, height, layer)
	var side := _reaches(data, owner_x + along_x, owner_z + along_z, height, layer)
	var corner := _reaches(data, owner_x + out_x + along_x, owner_z + out_z + along_z, height, layer)
	return corner_ao(front, side, corner)


static func _reaches(data: ChunkData, lx: int, lz: int, height: float, layer: float) -> bool:
	var surface := sample_surface(data, lx, lz)
	if surface <= HEIGHT_MISSING:
		return false
	return surface + layer >= height - layer * 0.2


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
