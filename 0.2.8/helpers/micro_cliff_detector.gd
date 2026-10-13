class_name MicroCliffDetector
extends RefCounted
## Detect cliff-edge columns that need localized micro refinement.


const _ChunkData = preload("res://chunks/chunk_data.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const CLIFF_HEIGHT_RATIO := 0.85


static func columns_needing_micro(data: ChunkData, seed_cells: Array) -> Array:
	if data == null or seed_cells.is_empty():
		return []
	var layer_h: float = _WorldSettings.get_active().layer_height()
	if layer_h <= 0.001:
		return []
	var threshold: float = layer_h * CLIFF_HEIGHT_RATIO
	var out: Array = []
	var seen: Dictionary = {}
	for cell_variant in seed_cells:
		var cell: Vector2i = cell_variant
		for ox in [-1, 0, 1]:
			for oz in [-1, 0, 1]:
				if ox == 0 and oz == 0:
					continue
				var lx: int = cell.x + ox
				var lz: int = cell.y + oz
				if lx < 0 or lx >= _ChunkData.SIZE or lz < 0 or lz >= _ChunkData.SIZE:
					continue
				var key := Vector2i(lx, lz)
				if seen.has(key):
					continue
				if _is_cliff_column(data, lx, lz, threshold):
					seen[key] = true
					out.append(key)
	return out


static func _is_cliff_column(data: ChunkData, lx: int, lz: int, threshold: float) -> bool:
	var center_h: float = data.get_surface_y(lx, lz)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = lx + d.x
		var nz: int = lz + d.y
		if nx < 0 or nx >= _ChunkData.SIZE or nz < 0 or nz >= _ChunkData.SIZE:
			continue
		if absf(data.get_surface_y(nx, nz) - center_h) >= threshold:
			return true
	return false