class_name MicroLayerGrid
extends RefCounted
## Sparse per-chunk micro brick storage. Macro columns remain world authority.


const _MacroLayerGrid = preload("res://helpers/macro_layer_grid.gd")
const _MicroColumnBrick = preload("res://helpers/micro_column_brick.gd")
const _MicroCliffDetector = preload("res://helpers/micro_cliff_detector.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _WorldSettings = preload("res://config/world_settings.gd")


## Prefer frozen ChunkData worker overlays when present (worker-safe). Live TerrainEdits only on main-thread fallbacks.
static func _overlay_build_tile(data, lx: int, lz: int, wx: int, wz: int) -> int:
	if data != null and data.has_method("has_worker_overlay_snapshot") and data.has_worker_overlay_snapshot():
		return int(data.get_worker_build_tile(lx, lz))
	return _TerrainEdits.get_build_tile(wx, wz)


static func _overlay_height_delta(data, lx: int, lz: int, wx: int, wz: int) -> float:
	if data != null and data.has_method("has_worker_overlay_snapshot") and data.has_worker_overlay_snapshot():
		return float(data.get_worker_height_delta(lx, lz))
	return _TerrainEdits.get_height_delta(wx, wz)

const SIZE := 16
const SCHEMA_VERSION := 1

var schema_version: int = SCHEMA_VERSION
var _bricks: Dictionary = {}  # Vector2i(lx,lz) -> MicroColumnBrick
var last_examined: int = 0
var last_allocated: int = 0

static var _pool: Array = []
static var _enabled_env_raw: String = ""
static var _enabled_cached: bool = true


static func enabled() -> bool:
	var raw := OS.get_environment("CRYSTALSTORM_MICRO_TERRAIN").strip_edges().to_lower()
	if raw != _enabled_env_raw:
		_enabled_env_raw = raw
		_enabled_cached = not (raw == "0" or raw == "false" or raw == "off")
	return _enabled_cached


static func acquire():
	if _pool.is_empty():
		return load("res://helpers/micro_layer_grid.gd").new()
	return _pool.pop_back()


static func release(grid) -> void:
	if grid == null:
		return
	grid.prepare_for_reuse()
	if _pool.size() < 32:
		_pool.append(grid)


func prepare_for_reuse() -> void:
	clear()


func clear() -> void:
	_bricks.clear()
	last_examined = 0
	last_allocated = 0


func brick_count() -> int:
	return _bricks.size()


func has_brick(lx: int, lz: int) -> bool:
	return _bricks.has(Vector2i(lx, lz))


func get_brick(lx: int, lz: int):
	if not has_brick(lx, lz):
		return null
	return _bricks[Vector2i(lx, lz)]


func allocate_brick(lx: int, lz: int, surface_y: float, surface_tile: int, reason: int, dug_layers: int = 0):
	if lx < 0 or lx >= SIZE or lz < 0 or lz >= SIZE:
		return null
	var key := Vector2i(lx, lz)
	var brick = _bricks.get(key, null)
	if brick == null:
		brick = _MicroColumnBrick.new()
		_bricks[key] = brick
		last_allocated += 1
	brick.copy_from_macro(surface_y, surface_tile, reason, dug_layers)
	return brick


func evict_brick(lx: int, lz: int) -> void:
	_bricks.erase(Vector2i(lx, lz))


func get_surface_y(lx: int, lz: int) -> float:
	var brick = get_brick(lx, lz)
	if brick == null:
		return -9999.0
	return float(brick.surface_y)


func get_surface_tile(lx: int, lz: int) -> int:
	var brick = get_brick(lx, lz)
	if brick == null:
		return -1
	return int(brick.surface_tile)


func sync_micro_flags(macro_grid, local_cells: Array = []) -> void:
	if macro_grid == null or not macro_grid.is_ready():
		return
	macro_grid.ensure_extended_storage()
	if local_cells.is_empty():
		for x in SIZE:
			for z in SIZE:
				macro_grid.set_micro_flag(x, z, has_brick(x, z))
		return
	var seen: Dictionary = {}
	for cell_variant in local_cells:
		var cell: Vector2i = cell_variant
		if seen.has(cell):
			continue
		seen[cell] = true
		macro_grid.set_micro_flag(cell.x, cell.y, has_brick(cell.x, cell.y))


func update_dirty_columns(data, local_cells: Array, include_cliff_edges: bool = true) -> int:
	last_examined = 0
	last_allocated = 0
	if data == null or local_cells.is_empty():
		return 0
	var work: Array = local_cells.duplicate()
	if include_cliff_edges:
		for cliff_cell in _MicroCliffDetector.columns_needing_micro(data, local_cells):
			if cliff_cell not in work:
				work.append(cliff_cell)
	var layer_h: float = _WorldSettings.get_active().layer_height()
	var cliff_threshold: float = layer_h * _MicroCliffDetector.CLIFF_HEIGHT_RATIO
	var seen: Dictionary = {}
	for cell_variant in work:
		var cell: Vector2i = cell_variant
		if seen.has(cell):
			continue
		seen[cell] = true
		var lx: int = cell.x
		var lz: int = cell.y
		if lx < 0 or lx >= SIZE or lz < 0 or lz >= SIZE:
			continue
		last_examined += 1
		var surface_y: float = float(data.surface_map[lx][lz])
		var surface_tile: int = int(data.tile_map[lx][lz])
		var wx: int = data.position.x * SIZE + lx
		var wz: int = data.position.y * SIZE + lz
		var reason: int = _MicroColumnBrick.REASON_NONE
		var dug: int = 0
		var layer_h_safe: float = maxf(layer_h, 0.001)
		var hdelta: float = _overlay_height_delta(data, lx, lz, wx, wz)
		if _overlay_build_tile(data, lx, lz, wx, wz) >= 0:
			reason = _MicroColumnBrick.REASON_BUILD
		elif int(hdelta / layer_h_safe) != 0:
			reason = _MicroColumnBrick.REASON_EDIT
			dug = maxi(0, -int(hdelta / layer_h_safe))
		elif cliff_threshold > 0.001 and _MicroCliffDetector._is_cliff_column(data, lx, lz, cliff_threshold):
			reason = _MicroColumnBrick.REASON_CLIFF
		if reason == _MicroColumnBrick.REASON_NONE:
			if has_brick(lx, lz):
				evict_brick(lx, lz)
			continue
		var existing = get_brick(lx, lz)
		if existing != null and existing.matches_macro(surface_y, surface_tile) and existing.reason == reason:
			continue
		allocate_brick(lx, lz, surface_y, surface_tile, reason, dug)
	if data.macro_grid != null:
		sync_micro_flags(data.macro_grid, local_cells)
	return last_examined


func derive_from_terrain_edits(data) -> void:
	if data == null or data.world == null:
		return
	clear()
	data.ensure_column_maps()
	var local_edits: Array = []
	for lx in SIZE:
		for lz in SIZE:
			var wx: int = data.position.x * SIZE + lx
			var wz: int = data.position.y * SIZE + lz
			if _overlay_build_tile(data, lx, lz, wx, wz) >= 0 \
					or absf(_overlay_height_delta(data, lx, lz, wx, wz)) > 0.001:
				local_edits.append(Vector2i(lx, lz))
	if local_edits.is_empty():
		return
	update_dirty_columns(data, local_edits, true)


func micro_cells_in_rect(rect: Rect2i) -> Array:
	var out: Array = []
	var x0: int = rect.position.x
	var z0: int = rect.position.y
	var x1: int = x0 + rect.size.x
	var z1: int = z0 + rect.size.y
	for key_variant in _bricks.keys():
		var key: Vector2i = key_variant
		if key.x >= x0 and key.x < x1 and key.y >= z0 and key.y < z1:
			out.append(key)
	return out