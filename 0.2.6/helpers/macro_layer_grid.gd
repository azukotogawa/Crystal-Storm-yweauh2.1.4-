class_name MacroLayerGrid
extends RefCounted
## Dense per-column macro terrain storage (v2 authority). Micro refinement is a sparse overlay.


const _WorldSettings = preload("res://config/world_settings.gd")

const SIZE := 16
const SCHEMA_VERSION := 1

const FLAG_NONE := 0
const FLAG_HAS_BUILD := 1
const FLAG_RAMP := 2
const FLAG_MICRO_PRESENT := 4


var schema_version: int = SCHEMA_VERSION

var _surface_y: Array = []
var _surface_tile: Array = []
var _stratum_layers: Array = []
var _surface_ly: Array = []
var _flags: Array = []
var _ready: bool = false
var _bound_surface: bool = false

static var _pool: Array = []
static var _enabled_env_raw: String = ""
static var _enabled_cached: bool = true


static func enabled() -> bool:
	var raw := OS.get_environment("CRYSTALSTORM_MACRO_TERRAIN").strip_edges().to_lower()
	if raw != _enabled_env_raw:
		_enabled_env_raw = raw
		_enabled_cached = not (raw == "0" or raw == "false" or raw == "off")
	return _enabled_cached


static func acquire() -> MacroLayerGrid:
	if _pool.is_empty():
		return MacroLayerGrid.new()
	return _pool.pop_back()


static func release(grid: MacroLayerGrid) -> void:
	if grid == null:
		return
	grid.prepare_for_reuse()
	if _pool.size() < 32:
		_pool.append(grid)


func clear() -> void:
	if not _bound_surface:
		_surface_y.clear()
		_surface_tile.clear()
	_stratum_layers.clear()
	_surface_ly.clear()
	_flags.clear()
	_bound_surface = false
	_ready = false


func bind_surface_arrays(surface_map: Array, tile_map: Array) -> void:
	if _bound_surface and _surface_y == surface_map and _surface_tile == tile_map:
		return
	_surface_y = surface_map
	_surface_tile = tile_map
	_bound_surface = true


func prepare_for_reuse() -> void:
	clear()


func clear_extended_metadata() -> void:
	_stratum_layers.clear()
	_surface_ly.clear()
	_flags.clear()


func is_ready() -> bool:
	return _ready


func is_surface_bound_to(surface_map: Array, tile_map: Array) -> bool:
	return _bound_surface and _surface_y == surface_map and _surface_tile == tile_map


func mark_ready() -> void:
	_ready = true


func _ensure_surface_rows() -> void:
	if _surface_y.size() != SIZE:
		_surface_y.resize(SIZE)
	if _surface_tile.size() != SIZE:
		_surface_tile.resize(SIZE)
	for x in SIZE:
		if _surface_y[x] == null or not (_surface_y[x] is Array):
			_surface_y[x] = []
		if _surface_tile[x] == null or not (_surface_tile[x] is Array):
			_surface_tile[x] = []
		if _surface_y[x].size() < SIZE:
			_surface_y[x].resize(SIZE)
		if _surface_tile[x].size() < SIZE:
			_surface_tile[x].resize(SIZE)


func ensure_surface_storage() -> void:
	if _bound_surface:
		_ensure_surface_rows()
		return
	if _surface_y.size() == SIZE:
		return
	_surface_y.resize(SIZE)
	_surface_tile.resize(SIZE)
	for x in SIZE:
		_surface_y[x] = []
		_surface_tile[x] = []
		_surface_y[x].resize(SIZE)
		_surface_tile[x].resize(SIZE)


func ensure_extended_storage() -> void:
	ensure_surface_storage()
	if _stratum_layers.size() == SIZE:
		return
	_stratum_layers.resize(SIZE)
	_surface_ly.resize(SIZE)
	_flags.resize(SIZE)
	for x in SIZE:
		_stratum_layers[x] = []
		_surface_ly[x] = []
		_flags[x] = []
		_stratum_layers[x].resize(SIZE)
		_surface_ly[x].resize(SIZE)
		_flags[x].resize(SIZE)
		for z in SIZE:
			_stratum_layers[x][z] = 0
			_surface_ly[x][z] = 0
			_flags[x][z] = FLAG_NONE


func ensure_storage() -> void:
	ensure_surface_storage()
	ensure_extended_storage()


func set_column(
	lx: int,
	lz: int,
	surface_y: float,
	surface_tile: int,
	stratum_layers: int,
	flags: int = FLAG_NONE
) -> void:
	ensure_storage()
	if lx < 0 or lx >= SIZE or lz < 0 or lz >= SIZE:
		return
	var layer_h: float = _WorldSettings.get_active().layer_height()
	_surface_y[lx][lz] = surface_y
	_surface_tile[lx][lz] = surface_tile
	_stratum_layers[lx][lz] = stratum_layers
	_surface_ly[lx][lz] = int(round(surface_y / maxf(layer_h, 0.001))) if layer_h > 0.001 else 0
	_flags[lx][lz] = flags
	_ready = true


func get_surface_y(lx: int, lz: int) -> float:
	if not _ready or lx < 0 or lx >= SIZE or lz < 0 or lz >= SIZE:
		return 0.0
	return float(_surface_y[lx][lz])


func get_surface_tile(lx: int, lz: int) -> int:
	if not _ready or lx < 0 or lx >= SIZE or lz < 0 or lz >= SIZE:
		return 0
	return int(_surface_tile[lx][lz])


func get_stratum_layers(lx: int, lz: int) -> int:
	if not _ready or lx < 0 or lx >= SIZE or lz < 0 or lz >= SIZE:
		return 0
	return int(_stratum_layers[lx][lz])


func get_surface_ly(lx: int, lz: int) -> int:
	if not _ready or lx < 0 or lx >= SIZE or lz < 0 or lz >= SIZE:
		return 0
	return int(_surface_ly[lx][lz])


func get_flags(lx: int, lz: int) -> int:
	if not _ready or lx < 0 or lx >= SIZE or lz < 0 or lz >= SIZE:
		return FLAG_NONE
	if _flags.size() != SIZE:
		return FLAG_NONE
	return int(_flags[lx][lz])


func set_ramp_flag(lx: int, lz: int, on: bool) -> void:
	ensure_extended_storage()
	if lx < 0 or lx >= SIZE or lz < 0 or lz >= SIZE:
		return
	var f: int = int(_flags[lx][lz])
	if on:
		_flags[lx][lz] = f | FLAG_RAMP
	else:
		_flags[lx][lz] = f & ~FLAG_RAMP


func set_micro_flag(lx: int, lz: int, on: bool) -> void:
	ensure_extended_storage()
	if lx < 0 or lx >= SIZE or lz < 0 or lz >= SIZE:
		return
	var f: int = int(_flags[lx][lz])
	if on:
		_flags[lx][lz] = f | FLAG_MICRO_PRESENT
	else:
		_flags[lx][lz] = f & ~FLAG_MICRO_PRESENT


func has_micro_flag(lx: int, lz: int) -> bool:
	if not _ready or _flags.size() != SIZE:
		return false
	if lx < 0 or lx >= SIZE or lz < 0 or lz >= SIZE:
		return false
	return (int(_flags[lx][lz]) & FLAG_MICRO_PRESENT) != 0


func clear_all_ramp_flags() -> void:
	if not _ready or _flags.size() != SIZE:
		return
	for x in SIZE:
		for z in SIZE:
			_flags[x][z] = int(_flags[x][z]) & ~FLAG_RAMP


func sync_ramp_flags_from(ramp_map: Dictionary) -> void:
	if not _ready:
		return
	if ramp_map.is_empty():
		clear_all_ramp_flags()
		return
	ensure_extended_storage()
	clear_all_ramp_flags()
	for key_variant in ramp_map.keys():
		var key: Vector2i = key_variant
		set_ramp_flag(key.x, key.y, true)


func _ensure_legacy_row(surface_map: Array, tile_map: Array, x: int) -> void:
	if surface_map.size() <= x:
		surface_map.resize(SIZE)
	if tile_map.size() <= x:
		tile_map.resize(SIZE)
	if surface_map[x] == null or not (surface_map[x] is Array):
		surface_map[x] = []
	if tile_map[x] == null or not (tile_map[x] is Array):
		tile_map[x] = []
	if surface_map[x].size() < SIZE:
		surface_map[x].resize(SIZE)
	if tile_map[x].size() < SIZE:
		tile_map[x].resize(SIZE)


func sync_to_legacy_maps(surface_map: Array, tile_map: Array) -> void:
	ensure_storage()
	surface_map.resize(SIZE)
	tile_map.resize(SIZE)
	for x in SIZE:
		_ensure_legacy_row(surface_map, tile_map, x)
		for z in SIZE:
			surface_map[x][z] = float(_surface_y[x][z])
			tile_map[x][z] = int(_surface_tile[x][z])


func sync_cells_to_legacy_maps(surface_map: Array, tile_map: Array, local_cells: Array) -> void:
	if not _ready:
		return
	for cell_variant in local_cells:
		var cell: Vector2i = cell_variant
		var x: int = cell.x
		var z: int = cell.y
		if x < 0 or x >= SIZE or z < 0 or z >= SIZE:
			continue
		_ensure_legacy_row(surface_map, tile_map, x)
		surface_map[x][z] = float(_surface_y[x][z])
		tile_map[x][z] = int(_surface_tile[x][z])


func _write_surface_column(x: int, z: int, surface_y: float, surface_tile: int) -> void:
	_surface_y[x][z] = surface_y
	_surface_tile[x][z] = surface_tile


func populate_from_chunk_data(data, use_uncached: bool = true) -> void:
	if data == null or data.world == null:
		return
	ensure_surface_storage()
	_ready = true
	for x in SIZE:
		for z in SIZE:
			var wx := float(data.position.x * SIZE + x)
			var wz := float(data.position.y * SIZE + z)
			var surface_y := 0.0
			var surface_tile := 0
			if use_uncached and data._has_worker_snapshot:
				var hdelta: float = float(data._worker_height_delta[x][z])
				surface_y = data.world.get_surface_height_worker(wx, wz, hdelta)
				surface_tile = data.world.get_tile_type_worker(
					wx, wz,
					int(data._worker_build_tile[x][z]),
					int(data._worker_feature_tile[x][z])
				)
			elif use_uncached:
				surface_y = data.world.get_surface_height_uncached(wx, wz)
				surface_tile = data.world.get_tile_type_uncached(wx, wz)
			else:
				surface_y = data.world.get_surface_height(wx, wz)
				surface_tile = data.world.get_tile_type(wx, wz)
			_write_surface_column(x, z, surface_y, surface_tile)


func update_cells_from_chunk_data(data, local_cells: Array) -> int:
	if data == null or data.world == null:
		return 0
	ensure_surface_storage()
	_ready = true
	var examined := 0
	var seen: Dictionary = {}
	for cell_variant in local_cells:
		var cell: Vector2i = cell_variant
		if seen.has(cell):
			continue
		seen[cell] = true
		var x: int = cell.x
		var z: int = cell.y
		if x < 0 or x >= SIZE or z < 0 or z >= SIZE:
			continue
		examined += 1
		var wx := float(data.position.x * SIZE + x)
		var wz := float(data.position.y * SIZE + z)
		var surface_y := 0.0
		var surface_tile := 0
		if data._has_worker_snapshot:
			var hdelta: float = float(data._worker_height_delta[x][z])
			surface_y = data.world.get_surface_height_worker(wx, wz, hdelta)
			surface_tile = data.world.get_tile_type_worker(
				wx, wz,
				int(data._worker_build_tile[x][z]),
				int(data._worker_feature_tile[x][z])
			)
		else:
			surface_y = data.world.get_surface_height_uncached(wx, wz)
			surface_tile = data.world.get_tile_type_uncached(wx, wz)
		_write_surface_column(x, z, surface_y, surface_tile)
	return examined