class_name TerrainDirtyScope
extends RefCounted
## Dependency-aware dirty column scope for incremental terrain mesh updates.

const _ChunkData = preload("res://chunks/chunk_data.gd")
const _TerrainEditor = preload("res://world/terrain_editor.gd")

const DIRTY_HALO := 1
const MESH_MARGIN := 2


static func dirty_world_columns(wx: int, wz: int) -> Array:
	var out: Array = []
	for dx in range(-DIRTY_HALO, DIRTY_HALO + 1):
		for dz in range(-DIRTY_HALO, DIRTY_HALO + 1):
			out.append(Vector2i(wx + dx, wz + dz))
	return out


static func world_to_local(wx: int, wz: int) -> Dictionary:
	var cx := floori(float(wx) / float(_ChunkData.SIZE))
	var cz := floori(float(wz) / float(_ChunkData.SIZE))
	return {
		"coord": Vector2i(cx, cz),
		"local": Vector2i(wx - cx * _ChunkData.SIZE, wz - cz * _ChunkData.SIZE),
	}


static func compute_edit_scope(wx: int, wz: int, chunk_manager: Node = null) -> Dictionary:
	var dirty_world: Array = dirty_world_columns(wx, wz)
	var by_chunk: Dictionary = {}
	for col_variant in dirty_world:
		var col: Vector2i = col_variant
		var wl: Dictionary = world_to_local(col.x, col.y)
		var coord: Vector2i = wl["coord"]
		var local: Vector2i = wl["local"]
		if not by_chunk.has(coord):
			by_chunk[coord] = []
		var bucket: Array = by_chunk[coord]
		if local not in bucket:
			bucket.append(local)

	var cross: Dictionary = _cross_boundary_deps(by_chunk)
	for ncoord_variant in cross.keys():
		var ncoord: Vector2i = ncoord_variant
		var ncells: Array = cross[ncoord]
		if not by_chunk.has(ncoord):
			by_chunk[ncoord] = []
		var bucket: Array = by_chunk[ncoord]
		for cell_variant in ncells:
			var cell: Vector2i = cell_variant
			if cell not in bucket:
				bucket.append(cell)

	var rebuild_chunks: Array = []
	var skipped_chunks: Array = []
	var neighbor_chunks: Array = []
	for coord_variant in cross.keys():
		var ncoord: Vector2i = coord_variant
		if ncoord not in neighbor_chunks:
			neighbor_chunks.append(ncoord)

	for coord_variant in by_chunk.keys():
		var coord: Vector2i = coord_variant
		if _chunk_is_loaded(chunk_manager, coord):
			if coord not in rebuild_chunks:
				rebuild_chunks.append(coord)
		elif chunk_manager != null:
			if coord not in skipped_chunks:
				skipped_chunks.append(coord)

	return {
		"edit_wx": wx,
		"edit_wz": wz,
		"dirty_world": dirty_world,
		"dirty_columns": dirty_world.size(),
		"by_chunk": by_chunk,
		"rebuild_chunks": rebuild_chunks,
		"skipped_chunks": skipped_chunks,
		"neighbor_chunks": neighbor_chunks,
	}


static func mesh_patch_rect(local_cells: Array, margin: int = MESH_MARGIN) -> Rect2i:
	if local_cells.is_empty():
		return Rect2i(0, 0, _ChunkData.SIZE, _ChunkData.SIZE)
	var min_x := _ChunkData.SIZE
	var min_z := _ChunkData.SIZE
	var max_x := -1
	var max_z := -1
	for cell_variant in local_cells:
		var cell: Vector2i = cell_variant
		min_x = mini(min_x, cell.x)
		min_z = mini(min_z, cell.y)
		max_x = maxi(max_x, cell.x)
		max_z = maxi(max_z, cell.y)
	var x0 := maxi(0, min_x - margin)
	var z0 := maxi(0, min_z - margin)
	var x1 := mini(_ChunkData.SIZE, max_x + margin + 1)
	var z1 := mini(_ChunkData.SIZE, max_z + margin + 1)
	return Rect2i(x0, z0, x1 - x0, z1 - z0)


static func patch_cells_area(rect: Rect2i) -> int:
	return maxi(rect.size.x * rect.size.y, 0)


static func should_full_rebuild(local_cells: Array) -> bool:
	if local_cells.is_empty():
		return true
	if local_cells.size() >= _ChunkData.SIZE * _ChunkData.SIZE - 4:
		return true
	var rect := mesh_patch_rect(local_cells)
	return patch_cells_area(rect) >= int(float(_ChunkData.SIZE * _ChunkData.SIZE) * 0.75)


static func _chunk_is_loaded(chunk_manager: Node, coord: Vector2i) -> bool:
	if chunk_manager == null:
		return true
	if chunk_manager.has_method("is_chunk_loaded"):
		return chunk_manager.is_chunk_loaded(coord)
	return true


static func _cross_boundary_deps(by_chunk: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var band: int = _TerrainEditor.REBUILD_EDGE_BAND
	for coord_variant in by_chunk.keys():
		var coord: Vector2i = coord_variant
		var locals: Array = by_chunk[coord]
		for local_variant in locals:
			var local: Vector2i = local_variant
			if local.x < band:
				_add_neighbor_band(out, coord, Vector2i(-1, 0), local.y, band)
			if local.x >= _ChunkData.SIZE - band:
				_add_neighbor_band(out, coord, Vector2i(1, 0), local.y, band)
			if local.y < band:
				_add_neighbor_band(out, coord, Vector2i(0, -1), local.x, band)
			if local.y >= _ChunkData.SIZE - band:
				_add_neighbor_band(out, coord, Vector2i(0, 1), local.x, band)
	return out


static func _add_neighbor_band(
	out: Dictionary,
	coord: Vector2i,
	dir: Vector2i,
	along: int,
	band: int
) -> void:
	var ncoord := Vector2i(coord.x + dir.x, coord.y + dir.y)
	if not out.has(ncoord):
		out[ncoord] = []
	var bucket: Array = out[ncoord]
	for i in range(band):
		var lx: int
		var lz: int
		if dir.x != 0:
			lx = (_ChunkData.SIZE - 1 - i) if dir.x > 0 else i
			lz = clampi(along, 0, _ChunkData.SIZE - 1)
		else:
			lz = (_ChunkData.SIZE - 1 - i) if dir.y > 0 else i
			lx = clampi(along, 0, _ChunkData.SIZE - 1)
		var cell := Vector2i(lx, lz)
		if cell not in bucket:
			bucket.append(cell)