class_name ChunkData

const _WorldSettings = preload("res://config/world_settings.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldState = preload("res://world/world_state.gd")
const _MacroLayerGrid = preload("res://helpers/macro_layer_grid.gd")
const _MicroLayerGrid = preload("res://helpers/micro_layer_grid.gd")
const _WorldBakeService = preload("res://world/world_bake_service.gd")
static var USE_MICRO_BRICKS: bool = false

var position: Vector2i
var world: InfiniteNoiseWorld = null


## Macro terrain authority (v2). Legacy maps are synced views for mesh/verify scripts.
var macro_grid = null
var micro_grid = null
var last_micro_examined: int = 0

var surface_map: Array = []
var tile_map: Array = []
var _legacy_maps_dirty: bool = false
var _macro_enabled: bool = true
var _macro_surface_bound: bool = false
var _macro_ramp_flags_dirty: bool = false
var _maps_resident: bool = false
static var s_macro_enabled_from_env: bool = true
static var s_micro_enabled_from_env: bool = true
var ramp_map: Dictionary = {}
var _worker_force_ramp: Dictionary = {}
var _worker_water_lid: Dictionary = {}

# Snapshotted on main thread before worker generation (avoids live WorldState races).
var _worker_height_delta: Array = []
var _worker_build_tile: Array = []
var _worker_feature_tile: Array = []
var _worker_feature_baked: Array = []
## Halo-region height deltas (world units), same dim as _halo_surface — worker-safe.
var _worker_halo_height_delta: Array = []
var _has_worker_snapshot: bool = false
var overlay_mesh_stamp: Dictionary = {}
var _mesh_job_micro_skip: Dictionary = {}
var preserve_column_maps: bool = false
var skip_mesh_plan_cache: bool = false
var _preserve_surface_snapshot: Array = []
var _preserve_tile_snapshot: Array = []
var _preserve_surface_hold: Array = []
var _preserve_tile_hold: Array = []
var _has_preserve_map_snapshot: bool = false
var _halo_surface: Array = []
var _halo_base_surface: Array = []
var _has_halo_surface: bool = false
var _baked_base_surface: Array = []
var _baked_base_tile: Array = []
var _has_baked_base: bool = false

const SIZE := 16
const HALO := 1
## Legacy bound — prefer WorldSettings.get_active().chunk_height_bound() for checks.
const HEIGHT := 48

func _init(coord: Vector2i, world_ref: InfiniteNoiseWorld = null):
	position = coord
	world = world_ref
	_macro_enabled = s_macro_enabled_from_env
	_macro_ramp_flags_dirty = false

	# Legacy 3D paths (if any) will see AIR / false.



func prepare_for_reuse(coord: Vector2i, world_ref: InfiniteNoiseWorld) -> void:
	position = coord
	world = world_ref
	if macro_grid:
		macro_grid.prepare_for_reuse()
	if micro_grid:
		micro_grid.prepare_for_reuse()
	surface_map.clear()
	tile_map.clear()
	ramp_map.clear()
	_worker_height_delta.clear()
	_worker_build_tile.clear()
	_worker_feature_tile.clear()
	_worker_feature_baked.clear()
	_worker_force_ramp.clear()
	_worker_water_lid.clear()
	_worker_halo_height_delta.clear()
	_halo_surface.clear()
	_halo_base_surface.clear()
	_has_worker_snapshot = false
	overlay_mesh_stamp = {}
	_mesh_job_micro_skip.clear()
	_has_halo_surface = false
	_baked_base_surface.clear()
	_baked_base_tile.clear()
	_has_baked_base = false
	_legacy_maps_dirty = false
	_macro_enabled = s_macro_enabled_from_env
	_macro_surface_bound = false
	_macro_ramp_flags_dirty = false
	_maps_resident = false
	last_micro_examined = 0
	clear_preserve_map_snapshot()

func touch_macro_view_pointers() -> void:
	if macro_grid == null:
		return
	_ensure_surface_map_storage()
	macro_grid.bind_surface_arrays(surface_map, tile_map)


func prewarm_macro_storage() -> void:
	if not _macro_enabled:
		return
	touch_macro_view_pointers()
	_bind_macro_surface_if_needed()

static var _snap_measure: bool = false
static var _snap_phase: Dictionary = {}
static var _snap_worst: Dictionary = {}
static var _snap_n: int = 0
static var _snap_max_us: int = 0
static var _snap_last_halo: Dictionary = {}


static func set_snapshot_measure_enabled(enabled: bool) -> void:
	_snap_measure = enabled
	if enabled:
		_snap_phase.clear()
		_snap_worst.clear()
		_snap_n = 0
		_snap_max_us = 0


static func _snap_add(phase: String, us: int) -> void:
	if not _snap_measure or us < 0:
		return
	if not _snap_phase.has(phase):
		_snap_phase[phase] = {"n": 0, "total_us": 0, "max_us": 0}
	var row: Dictionary = _snap_phase[phase]
	row["n"] = int(row["n"]) + 1
	row["total_us"] = int(row["total_us"]) + us
	row["max_us"] = maxi(int(row["max_us"]), us)


static func get_snapshot_measure() -> Dictionary:
	var phases: Array = []
	for k in _snap_phase.keys():
		var row: Dictionary = _snap_phase[k]
		phases.append({
			"phase": k,
			"n": int(row.get("n", 0)),
			"total_us": int(row.get("total_us", 0)),
			"total_ms": float(row.get("total_us", 0)) / 1000.0,
			"max_us": int(row.get("max_us", 0)),
			"max_ms": float(row.get("max_us", 0)) / 1000.0,
			"avg_us": float(row.get("total_us", 0)) / float(maxi(int(row.get("n", 0)), 1)),
		})
	phases.sort_custom(func(a, b): return int(a.max_us) > int(b.max_us))
	return {
		"calls": _snap_n,
		"max_us": _snap_max_us,
		"max_ms": float(_snap_max_us) / 1000.0,
		"phases": phases,
		"worst": _snap_worst.duplicate(true),
	}


var _snapshot_base_only: bool = false


func capture_base_only_snapshot() -> void:
	_snapshot_base_only = true
	overlay_mesh_stamp = {}
	_ensure_worker_overlay_storage()
	for x in SIZE:
		for z in SIZE:
			_worker_height_delta[x][z] = 0.0
			_worker_build_tile[x][z] = -1
			_worker_feature_tile[x][z] = -1
			_worker_feature_baked[x][z] = false
	_has_worker_snapshot = true
	_capture_halo_surface()
	_snapshot_base_only = false


func set_worker_feature_tile(lx: int, lz: int, tile: int, baked: bool = true) -> void:
	if lx < 0 or lz < 0 or lx >= SIZE or lz >= SIZE:
		return
	_ensure_worker_overlay_storage()
	_worker_feature_tile[lx][lz] = tile
	_worker_feature_baked[lx][lz] = baked


func capture_worker_snapshot() -> void:
	if not _snap_measure and OS.get_environment("CRYSTALSTORM_DRAIN_STREAM_MEASURE").strip_edges().to_lower() in ["1", "true", "on"]:
		_snap_measure = true
	var t_all := Time.get_ticks_usec() if _snap_measure else 0
	var parts: Dictionary = {} if _snap_measure else {}
	var ws = _WorldState.get_active()
	var t0 := Time.get_ticks_usec() if _snap_measure else 0
	overlay_mesh_stamp = ws.capture_mesh_overlay_stamp()
	if _snap_measure:
		_snap_add("capture_mesh_overlay_stamp", Time.get_ticks_usec() - t0)
		parts["capture_mesh_overlay_stamp_us"] = Time.get_ticks_usec() - t0
	var layer_h: float = maxf(_WorldSettings.get_active().layer_height(), 0.001)
	t0 = Time.get_ticks_usec() if _snap_measure else 0
	_ensure_worker_overlay_storage()
	_worker_force_ramp.clear()
	_worker_water_lid.clear()
	if _snap_measure:
		_snap_add("ensure_worker_overlay_storage", Time.get_ticks_usec() - t0)
		parts["ensure_worker_overlay_storage_us"] = Time.get_ticks_usec() - t0
	var overlays_empty: bool = (
		ws.height_delta.is_empty()
		and ws.build_tile.is_empty()
		and ws.tile_overrides.is_empty()
		and ws.feature_cells.is_empty()
		and (not ("seeded_tile_keys" in ws) or ws.seeded_tile_keys.is_empty())
	)
	t0 = Time.get_ticks_usec() if _snap_measure else 0
	if overlays_empty:
		for x in SIZE:
			for z in SIZE:
				_worker_height_delta[x][z] = 0.0
				_worker_build_tile[x][z] = -1
				_worker_feature_tile[x][z] = -1
				_worker_feature_baked[x][z] = false
		if _snap_measure:
			_snap_add("overlay_copy_empty_fast", Time.get_ticks_usec() - t0)
			parts["overlay_path"] = "empty_fast"
			parts["overlay_copy_us"] = Time.get_ticks_usec() - t0
	else:
		for x in SIZE:
			for z in SIZE:
				var wx := position.x * SIZE + x
				var wz := position.y * SIZE + z
				var key := Vector2i(wx, wz)
				# Read authority storage once; convert height layers → world units for workers.
				_worker_height_delta[x][z] = float(int(ws.height_delta.get(key, 0))) * layer_h
				_worker_build_tile[x][z] = int(ws.build_tile.get(key, -1))
				_worker_feature_tile[x][z] = int(ws.tile_overrides.get(key, -1))
				var feat_entry: Dictionary = ws.feature_cells.get(key, {})
				var seeded: bool = bool(ws.seeded_tile_keys.get(key, false)) \
					if "seeded_tile_keys" in ws else false
				_worker_feature_baked[x][z] = bool(feat_entry.get("_baked_static", false)) or seeded
				var bid := str(feat_entry.get("build_id", ""))
				if bid == "cardinal_ramp" or bid == "corner_ramp":
					_worker_force_ramp[Vector2i(x, z)] = feat_entry.duplicate()
		if _snap_measure:
			_snap_add("overlay_copy_dict_walk", Time.get_ticks_usec() - t0)
			parts["overlay_path"] = "dict_walk"
			parts["overlay_copy_us"] = Time.get_ticks_usec() - t0
			parts["feature_cells_n"] = ws.feature_cells.size()
			parts["seeded_tile_keys_n"] = ws.seeded_tile_keys.size() if "seeded_tile_keys" in ws else 0
	_capture_water_lid_snapshot(ws)
	_has_worker_snapshot = true
	t0 = Time.get_ticks_usec() if _snap_measure else 0
	_capture_halo_surface()
	if _snap_measure:
		var halo_us := Time.get_ticks_usec() - t0
		_snap_add("capture_halo_surface", halo_us)
		parts["capture_halo_surface_us"] = halo_us
		for hk in _snap_last_halo.keys():
			parts[hk] = _snap_last_halo[hk]
		var tot := Time.get_ticks_usec() - t_all
		_snap_add("capture_worker_snapshot_total", tot)
		_snap_n += 1
		if tot >= _snap_max_us:
			_snap_max_us = tot
			parts["total_us"] = tot
			parts["total_ms"] = float(tot) / 1000.0
			parts["coord"] = [position.x, position.y]
			_snap_worst = parts.duplicate(true)


func _capture_water_lid_snapshot(ws) -> void:
	_worker_water_lid.clear()
	if ws == null:
		return
	for x in range(-1, SIZE + 1):
		for z in range(-1, SIZE + 1):
			_refresh_water_lid_cell(ws, x, z)


func _refresh_water_lid_cell(ws, x: int, z: int) -> void:
	var entry: Dictionary = ws.channels.get(Vector2i(position.x * SIZE + x, position.y * SIZE + z), {})
	if float(entry.get("water_level", 0.0)) < 0.05:
		_worker_water_lid.erase(Vector2i(x, z))
		return
	_worker_water_lid[Vector2i(x, z)] = float(entry.get("surface_y", 0.0))


func _ensure_worker_overlay_storage() -> void:
	var need_alloc := (
		_worker_height_delta.size() != SIZE
		or _worker_build_tile.size() != SIZE
		or _worker_feature_tile.size() != SIZE
		or _worker_feature_baked.size() != SIZE
	)
	if not need_alloc and _worker_height_delta[0] is Array and _worker_height_delta[0].size() == SIZE:
		return
	_worker_height_delta.resize(SIZE)
	_worker_build_tile.resize(SIZE)
	_worker_feature_tile.resize(SIZE)
	_worker_feature_baked.resize(SIZE)
	for x in SIZE:
		_worker_height_delta[x] = []
		_worker_build_tile[x] = []
		_worker_feature_tile[x] = []
		_worker_feature_baked[x] = []
		_worker_height_delta[x].resize(SIZE)
		_worker_build_tile[x].resize(SIZE)
		_worker_feature_tile[x].resize(SIZE)
		_worker_feature_baked[x].resize(SIZE)


func is_overlay_mesh_stamp_current() -> bool:
	return _WorldState.get_active().is_mesh_stamp_current(overlay_mesh_stamp)


func has_worker_overlay_snapshot() -> bool:
	return _has_worker_snapshot


func _capture_halo_surface() -> void:
	if world == null:
		return
	var dim := SIZE + HALO * 2
	var layer_h: float = maxf(_WorldSettings.get_active().layer_height(), 0.001)
	var ws = _WorldState.get_active()
	var bake = _WorldBakeService.get_active()
	var t_alloc := Time.get_ticks_usec() if _snap_measure else 0
	_halo_surface.resize(dim)
	_halo_base_surface.resize(dim)
	_worker_halo_height_delta.resize(dim)
	var resolve_bake_us := 0
	var resolve_noise_us := 0
	var resolve_n := 0
	var bake_hits := 0
	var noise_hits := 0
	var deferred_n := 0
	for ix in dim:
		_halo_surface[ix] = []
		_halo_surface[ix].resize(dim)
		_halo_base_surface[ix] = []
		_halo_base_surface[ix].resize(dim)
		_worker_halo_height_delta[ix] = []
		_worker_halo_height_delta[ix].resize(dim)
		for iz in dim:
			var lx := ix - HALO
			var lz := iz - HALO
			if lx >= 0 and lx < SIZE and lz >= 0 and lz < SIZE:
				_halo_surface[ix][iz] = -9999.0
				_halo_base_surface[ix][iz] = -9999.0
				_worker_halo_height_delta[ix][iz] = 0.0
				continue
			var wx := position.x * SIZE + lx
			var wz := position.y * SIZE + lz
			var key := Vector2i(wx, wz)
			var hdelta: float = 0.0
			if not _snapshot_base_only:
				hdelta = float(int(ws.height_delta.get(key, 0))) * layer_h
			_worker_halo_height_delta[ix][iz] = hdelta
			var t_r := Time.get_ticks_usec() if _snap_measure else 0
			var resolved: Dictionary = _resolve_halo_natural_height(wx, wz, bake)
			if _snap_measure:
				var rus := Time.get_ticks_usec() - t_r
				resolve_n += 1
				if bool(resolved.get("via_bake", false)):
					resolve_bake_us += rus
					bake_hits += 1
				elif bool(resolved.get("deferred", false)):
					resolve_bake_us += rus
					deferred_n += 1
				else:
					resolve_noise_us += rus
					noise_hits += 1
			if bool(resolved.get("deferred", false)):
				_halo_base_surface[ix][iz] = -9999.0
				_halo_surface[ix][iz] = -9999.0
				continue
			var base_h: float = float(resolved.get("base", 0.0))
			_halo_base_surface[ix][iz] = base_h
			_halo_surface[ix][iz] = _WorldBakeService.compose_surface_height(base_h, hdelta)
	_has_halo_surface = true
	if _snap_measure:
		_snap_add("halo_resolve_bake_sample", resolve_bake_us)
		_snap_add("halo_resolve_noise", resolve_noise_us)
		_snap_last_halo = {
			"halo_resolve_bake_us": resolve_bake_us,
			"halo_resolve_noise_us": resolve_noise_us,
			"halo_bake_hits": bake_hits,
			"halo_noise_hits": noise_hits,
			"halo_deferred_n": deferred_n,
			"halo_border_cells": resolve_n,
			"halo_loop_wall_us": Time.get_ticks_usec() - t_alloc,
		}


func _resolve_halo_natural_height(wx: int, wz: int, bake) -> Dictionary:
	if bake != null and bake.valid and bake.has_method("covers_world_cell") \
			and bool(bake.covers_world_cell(wx, wz)):
		var sample: Dictionary = bake.sample_world_base(wx, wz)
		if sample.is_empty():
			if bake.has_method("note_halo_deferred"):
				bake.note_halo_deferred()
			return {"deferred": true, "via_bake": true}
		if bake.has_method("note_halo_bake_hit"):
			bake.note_halo_bake_hit()
		return {"base": float(sample.get("surface", 0.0)), "deferred": false, "via_bake": true}
	# Outside package bounds, or no valid bake: legacy noise (allowed for out-of-bounds).
	var h: float = world.get_surface_height_worker(float(wx), float(wz), 0.0)
	return {"base": h, "deferred": false, "via_bake": false}


func store_baked_base(surface: PackedFloat32Array, tiles: PackedInt32Array) -> void:
	_baked_base_surface.clear()
	_baked_base_tile.clear()
	_baked_base_surface.resize(SIZE)
	_baked_base_tile.resize(SIZE)
	for lx in SIZE:
		_baked_base_surface[lx] = []
		_baked_base_surface[lx].resize(SIZE)
		_baked_base_tile[lx] = []
		_baked_base_tile[lx].resize(SIZE)
	var i := 0
	for lz in SIZE:
		for lx in SIZE:
			if i < surface.size():
				_baked_base_surface[lx][lz] = float(surface[i])
			if i < tiles.size():
				_baked_base_tile[lx][lz] = int(tiles[i])
			i += 1
	_has_baked_base = true


func has_baked_base() -> bool:
	return _has_baked_base


func get_baked_base_height(lx: int, lz: int) -> float:
	if not _has_baked_base:
		return 0.0
	if lx < 0 or lx >= SIZE or lz < 0 or lz >= SIZE:
		return 0.0
	if lx >= _baked_base_surface.size() or _baked_base_surface[lx] == null:
		return 0.0
	if lz >= _baked_base_surface[lx].size():
		return 0.0
	return float(_baked_base_surface[lx][lz])


func get_baked_base_tile(lx: int, lz: int) -> int:
	if not _has_baked_base:
		return VoxelTypes.AIR
	if lx < 0 or lx >= SIZE or lz < 0 or lz >= SIZE:
		return VoxelTypes.AIR
	if lx >= _baked_base_tile.size() or _baked_base_tile[lx] == null:
		return VoxelTypes.AIR
	if lz >= _baked_base_tile[lx].size():
		return VoxelTypes.AIR
	return int(_baked_base_tile[lx][lz])


func get_natural_surface_y(lx: int, lz: int) -> float:
	if _has_baked_base:
		return get_baked_base_height(lx, lz)
	if world == null:
		return 0.0
	var wx: int = position.x * SIZE + lx
	var wz: int = position.y * SIZE + lz
	return world.get_surface_height_worker(float(wx), float(wz), 0.0)


func _refresh_halo_interior_from_maps() -> void:
	if not _has_halo_surface:
		return
	if _maps_resident:
		for x in SIZE:
			for z in SIZE:
				_halo_surface[x + HALO][z + HALO] = surface_map[x][z]
		return
	for x in SIZE:
		for z in SIZE:
			_halo_surface[x + HALO][z + HALO] = get_surface_y(x, z)


func get_halo_surface_y(lx: int, lz: int) -> float:
	if not _has_halo_surface:
		return -9999.0
	var ix := lx + HALO
	var iz := lz + HALO
	if ix < 0 or iz < 0 or ix >= _halo_surface.size() or iz >= _halo_surface[ix].size():
		return -9999.0
	return float(_halo_surface[ix][iz])


func ensure_column_maps() -> void:
	if _maps_resident:
		return
	if surface_map.size() == SIZE and tile_map.size() == SIZE:
		_maps_resident = true
		return
	_compute_column_maps(true)


static func macro_terrain_enabled() -> bool:
	return _MacroLayerGrid.enabled()


static func micro_terrain_enabled() -> bool:
	return USE_MICRO_BRICKS and _MicroLayerGrid.enabled()


static func configure_macro_terrain_from_env() -> void:
	s_macro_enabled_from_env = _MacroLayerGrid.enabled()


static func configure_micro_terrain_from_env() -> void:
	s_micro_enabled_from_env = USE_MICRO_BRICKS and _MicroLayerGrid.enabled()


static func set_macro_enabled_for_benchmark(on: bool) -> void:
	s_macro_enabled_from_env = on


static func set_micro_enabled_for_benchmark(on: bool) -> void:
	s_micro_enabled_from_env = on


func is_macro_terrain_enabled() -> bool:
	return _macro_enabled


func is_micro_terrain_enabled() -> bool:
	return USE_MICRO_BRICKS and s_micro_enabled_from_env


func sync_macro_mode_from_env() -> void:
	_macro_enabled = s_macro_enabled_from_env


func _micro_grid():
	if micro_grid == null and is_micro_terrain_enabled():
		micro_grid = _MicroLayerGrid.acquire()
	return micro_grid


func _micro_active() -> bool:
	return is_micro_terrain_enabled() and micro_grid != null


func has_micro_brick(lx: int, lz: int) -> bool:
	return _micro_active() and micro_grid.has_brick(lx, lz)


func derive_micro_from_terrain_edits() -> void:
	if not is_micro_terrain_enabled():
		return
	var grid = _micro_grid()
	grid.derive_from_terrain_edits(self)


func sync_macro_benchmark_layout() -> void:
	sync_macro_mode_from_env()
	if not _macro_enabled:
		return
	if macro_grid == null:
		prewarm_macro_storage()
	elif not _macro_surface_bound:
		touch_macro_view_pointers()
		_bind_macro_surface_if_needed()


func _macro_grid() -> MacroLayerGrid:
	if macro_grid == null and _macro_enabled:
		macro_grid = _MacroLayerGrid.acquire()
	return macro_grid


func _macro_active() -> bool:
	return _macro_enabled and macro_grid != null


func mark_macro_ramp_flags_dirty() -> void:
	_macro_ramp_flags_dirty = true


func finalize_macro_metadata(sync_ramps: bool = false) -> void:
	if not _macro_enabled:
		return
	var grid := _macro_grid()
	grid.ensure_extended_storage()
	if sync_ramps:
		grid.sync_ramp_flags_from(ramp_map)
		_macro_ramp_flags_dirty = false


func ensure_macro_ramp_flags_synced() -> void:
	if not _macro_enabled:
		return
	finalize_macro_metadata(true)


func sync_macro_ramp_flags() -> void:
	mark_macro_ramp_flags_dirty()
	ensure_macro_ramp_flags_synced()


func refresh_worker_snapshot_for_cells(local_cells: Array) -> void:
	if world == null:
		return
	if not _has_worker_snapshot:
		capture_worker_snapshot()
		return
	var ws = _WorldState.get_active()
	overlay_mesh_stamp = ws.capture_mesh_overlay_stamp()
	var layer_h: float = maxf(_WorldSettings.get_active().layer_height(), 0.001)
	for cell_variant in local_cells:
		var cell: Vector2i = cell_variant
		var x: int = cell.x
		var z: int = cell.y
		if x < 0 or x >= SIZE or z < 0 or z >= SIZE:
			continue
		var wx := position.x * SIZE + x
		var wz := position.y * SIZE + z
		var key := Vector2i(wx, wz)
		_worker_height_delta[x][z] = float(int(ws.height_delta.get(key, 0))) * layer_h
		_worker_build_tile[x][z] = int(ws.build_tile.get(key, -1))
		_worker_feature_tile[x][z] = int(ws.tile_overrides.get(key, -1))
		if _worker_feature_baked.size() != SIZE:
			_worker_feature_baked.resize(SIZE)
		if _worker_feature_baked[x] == null or not (_worker_feature_baked[x] is Array) \
				or _worker_feature_baked[x].size() != SIZE:
			_worker_feature_baked[x] = []
			_worker_feature_baked[x].resize(SIZE)
		var feat_entry: Dictionary = ws.feature_cells.get(key, {})
		var seeded: bool = bool(ws.seeded_tile_keys.get(key, false)) \
			if "seeded_tile_keys" in ws else false
		_worker_feature_baked[x][z] = bool(feat_entry.get("_baked_static", false)) or seeded
		var bid := str(feat_entry.get("build_id", ""))
		if bid == "cardinal_ramp" or bid == "corner_ramp":
			_worker_force_ramp[Vector2i(x, z)] = feat_entry.duplicate()
		else:
			_worker_force_ramp.erase(Vector2i(x, z))
		_refresh_water_lid_cell(ws, x, z)
		_refresh_worker_halo_deltas_around(x, z, ws, layer_h)
		_refresh_halo_for_local_cell(x, z)


func update_dirty_column_maps(local_cells: Array) -> int:
	if not world:
		return 0
	ensure_column_maps()
	_ensure_surface_map_storage()
	var bake = _WorldBakeService.get_active()
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
		_rebuild_dirty_column(x, z, bake)
		if _has_halo_surface:
			_halo_surface[x + HALO][z + HALO] = surface_map[x][z]
	for cell_variant in local_cells:
		var cell: Vector2i = cell_variant
		var x: int = cell.x
		var z: int = cell.y
		if x == 0 or z == 0 or x == SIZE - 1 or z == SIZE - 1:
			_refresh_halo_border_for_local_cell(x, z)
	if is_micro_terrain_enabled():
		var micro = _micro_grid()
		last_micro_examined = micro.update_dirty_columns(self, local_cells, true)
	return examined


## Dirty column = baked base (or legacy noise outside package) + frozen WorldState overlays.
func _rebuild_dirty_column(x: int, z: int, bake) -> void:
	var hdelta: float = 0.0
	var build_t: int = -1
	var feat_t: int = -1
	if _has_worker_snapshot:
		hdelta = float(_worker_height_delta[x][z])
		build_t = int(_worker_build_tile[x][z])
		feat_t = mesh_feature_tile(x, z)
	if _has_baked_base:
		surface_map[x][z] = _WorldBakeService.compose_surface_height(
			get_baked_base_height(x, z), hdelta
		)
		# Authored WorldObjects mark build_tile without raising — do not retile
		# the floor under them. Feature tile overrides (water replace, paths,
		# farmland) apply even when height is unchanged.
		if build_t >= 0 and absf(hdelta) > 0.01:
			tile_map[x][z] = build_t
		elif feat_t >= 0:
			tile_map[x][z] = feat_t
		else:
			tile_map[x][z] = get_baked_base_tile(x, z)
		if bake != null and bake.has_method("note_dirty_bake_hit"):
			bake.note_dirty_bake_hit()
		return
	var wx_i: int = position.x * SIZE + x
	var wz_i: int = position.y * SIZE + z
	if bake != null and bake.valid and bake.has_method("covers_world_cell") \
			and bool(bake.covers_world_cell(wx_i, wz_i)):
		var sample: Dictionary = {}
		if bake.has_method("sample_base"):
			sample = bake.sample_base(position, x, z)
		if not sample.is_empty():
			if not _has_baked_base and bake.has_method("sample_base"):
				pass
			surface_map[x][z] = _WorldBakeService.compose_surface_height(
				float(sample.get("surface", 0.0)), hdelta
			)
			if build_t >= 0 and absf(hdelta) > 0.01:
				tile_map[x][z] = build_t
			elif feat_t >= 0:
				tile_map[x][z] = feat_t
			else:
				tile_map[x][z] = int(sample.get("tile", VoxelTypes.AIR))
			if bake.has_method("note_dirty_bake_hit"):
				bake.note_dirty_bake_hit()
			return
		return
	var wx := float(wx_i)
	var wz := float(wz_i)
	if _has_worker_snapshot:
		surface_map[x][z] = world.get_surface_height_worker(wx, wz, hdelta)
		var mesh_build: int = build_t if absf(hdelta) > 0.01 else -1
		var mesh_feat: int = mesh_feature_tile(x, z)
		tile_map[x][z] = world.get_tile_type_worker(wx, wz, mesh_build, mesh_feat)
	else:
		surface_map[x][z] = world.get_surface_height_uncached(wx, wz)
		tile_map[x][z] = world.get_tile_type_uncached(wx, wz)


func _refresh_halo_for_local_cell(x: int, z: int) -> void:
	if not _has_halo_surface or world == null:
		return
	if _maps_resident:
		_halo_surface[x + HALO][z + HALO] = surface_map[x][z]
	_refresh_halo_border_for_local_cell(x, z)


func _refresh_worker_halo_deltas_around(x: int, z: int, ws, layer_h: float) -> void:
	if not _has_halo_surface or _worker_halo_height_delta.is_empty():
		return
	for ox in [-1, 0, 1]:
		for oz in [-1, 0, 1]:
			var lx: int = x + ox
			var lz: int = z + oz
			if lx >= 0 and lx < SIZE and lz >= 0 and lz < SIZE:
				continue
			var ix: int = lx + HALO
			var iz: int = lz + HALO
			if ix < 0 or iz < 0 or ix >= _worker_halo_height_delta.size() \
					or iz >= _worker_halo_height_delta[ix].size():
				continue
			var wx: int = position.x * SIZE + lx
			var wz: int = position.y * SIZE + lz
			_worker_halo_height_delta[ix][iz] = float(int(ws.height_delta.get(Vector2i(wx, wz), 0))) * layer_h


func _refresh_halo_border_for_local_cell(x: int, z: int) -> void:
	if not _has_halo_surface or world == null:
		return
	for ox in [-1, 0, 1]:
		for oz in [-1, 0, 1]:
			if ox == 0 and oz == 0:
				continue
			var lx: int = x + ox
			var lz: int = z + oz
			if lx >= 0 and lx < SIZE and lz >= 0 and lz < SIZE:
				continue
			var ix: int = lx + HALO
			var iz: int = lz + HALO
			if ix < 0 or iz < 0 or ix >= _halo_surface.size() or iz >= _halo_surface[ix].size():
				continue
			var hdelta: float = 0.0
			if _has_worker_snapshot and ix < _worker_halo_height_delta.size() \
					and iz < _worker_halo_height_delta[ix].size():
				# Worker / post-capture path: never re-read live WorldState.
				hdelta = float(_worker_halo_height_delta[ix][iz])
			else:
				var wx: int = position.x * SIZE + lx
				var wz: int = position.y * SIZE + lz
				var key := Vector2i(wx, wz)
				var layer_h: float = maxf(_WorldSettings.get_active().layer_height(), 0.001)
				hdelta = float(int(_WorldState.get_active().height_delta.get(key, 0))) * layer_h
			if ix < _halo_base_surface.size() and iz < _halo_base_surface[ix].size():
				var base_h: float = float(_halo_base_surface[ix][iz])
				if base_h <= -9000.0:
					_halo_surface[ix][iz] = -9999.0
				else:
					_halo_surface[ix][iz] = _WorldBakeService.compose_surface_height(base_h, hdelta)
			else:
				_halo_surface[ix][iz] = -9999.0


func snapshot_resident_maps() -> void:
	if surface_map.is_empty() or tile_map.is_empty():
		return
	_preserve_surface_hold = _preserve_surface_snapshot
	_preserve_tile_hold = _preserve_tile_snapshot
	_preserve_surface_snapshot = surface_map.duplicate(true)
	_preserve_tile_snapshot = tile_map.duplicate(true)
	_has_preserve_map_snapshot = true


func has_preserve_map_snapshot() -> bool:
	return _has_preserve_map_snapshot


func clear_preserve_map_snapshot() -> void:
	_has_preserve_map_snapshot = false
	# Drop the reference. clear() in place races a worker that is indexing it.
	_preserve_surface_hold = _preserve_surface_snapshot
	_preserve_tile_hold = _preserve_tile_snapshot
	_preserve_surface_snapshot = []
	_preserve_tile_snapshot = []


func restore_resident_map_snapshot() -> void:
	if not _has_preserve_map_snapshot:
		return
	var snap_h: Array = _preserve_surface_snapshot
	var snap_t: Array = _preserve_tile_snapshot
	if snap_h.is_empty():
		return
	_ensure_surface_map_storage()
	var x_count: int = mini(SIZE, mini(snap_h.size(), surface_map.size()))
	for x in x_count:
		if x >= snap_h.size() or x >= surface_map.size():
			break
		var src_h = snap_h[x]
		var dst = surface_map[x]
		if src_h == null or dst == null or not (src_h is Array) or not (dst is Array):
			continue
		var row: Array = src_h
		var dst_row: Array = dst
		var src_t: Array = []
		if x < snap_t.size() and snap_t[x] is Array:
			src_t = snap_t[x]
		var dst_t: Array = []
		if x < tile_map.size() and tile_map[x] is Array:
			dst_t = tile_map[x]
		var n: int = mini(SIZE, mini(row.size(), dst_row.size()))
		for z in n:
			if z >= row.size() or z >= dst_row.size():
				break
			dst_row[z] = row[z]
			if z < src_t.size() and z < dst_t.size():
				dst_t[z] = src_t[z]
	_maps_resident = true


func _compute_column_maps(use_uncached: bool = true):
	var w = world
	if w == null:
		return
	# A yard stamp landed while this regen was already queued. Do not overwrite it.
	if preserve_column_maps or _has_preserve_map_snapshot:
		restore_resident_map_snapshot()
		preserve_column_maps = false
		if _has_halo_surface:
			_refresh_halo_interior_from_maps()
		return

	_ensure_surface_map_storage()
	if _has_baked_base and _has_worker_snapshot:
		var bake = _WorldBakeService.get_active()
		for x in SIZE:
			for z in SIZE:
				_rebuild_dirty_column(x, z, bake)
		if _has_halo_surface:
			_refresh_halo_interior_from_maps()
		return
	for x in SIZE:
		for z in SIZE:
			var wx := float(position.x * SIZE + x)
			var wz := float(position.y * SIZE + z)
			if use_uncached and _has_worker_snapshot:
				surface_map[x][z] = w.get_surface_height_worker(
					wx, wz, float(_worker_height_delta[x][z])
				)
				tile_map[x][z] = w.get_tile_type_worker(
					wx, wz,
					int(_worker_build_tile[x][z]),
					mesh_feature_tile(x, z)
				)
			elif use_uncached:
				surface_map[x][z] = w.get_surface_height_uncached(wx, wz)
				tile_map[x][z] = w.get_tile_type_uncached(wx, wz)
			else:
				surface_map[x][z] = w.get_surface_height(wx, wz)
				tile_map[x][z] = w.get_tile_type(wx, wz)
	if _has_halo_surface:
		_refresh_halo_interior_from_maps()

func set_voxel(x: int, y: int, z: int, value: int):
	pass

func get_voxel(x: int, y: int, z: int) -> int:
	if x >= 0 and x < SIZE and z >= 0 and z < SIZE and _has_resident_column_maps():
		var sy: float = get_surface_y(x, z)
		if absf(float(y) - sy) < _surface_match_epsilon():
			return get_tile_type(x, z)
	return VoxelTypes.AIR

func get_visibility(x: int, y: int, z: int) -> bool:
	if x >= 0 and x < SIZE and z >= 0 and z < SIZE and _has_resident_column_maps():
		var sy: float = get_surface_y(x, z)
		if absf(float(y) - sy) < _surface_match_epsilon():
			return get_tile_type(x, z) != VoxelTypes.AIR
	return false

func set_visibility(x: int, y: int, z: int, value: bool):
	pass

func is_visible(x: int, y: int, z: int) -> bool:
	return get_visibility(x, y, z)

func set_visible(x: int, y: int, z: int, visible: bool):
	set_visibility(x, y, z, visible)

func set_ramp_cardinal(x: int, z: int, dir: Vector2i) -> void:
	ramp_map[Vector2i(x, z)] = {"corner": false, "side": false, "approach": false, "dir": dir, "dir2": Vector2i.ZERO}


func set_ramp_approach(x: int, z: int, climb_dir: Vector2i) -> void:
	ramp_map[Vector2i(x, z)] = {"corner": false, "side": false, "approach": true, "dir": climb_dir, "dir2": Vector2i.ZERO}


func set_ramp_corner(x: int, z: int, dir_a: Vector2i, dir_b: Vector2i) -> void:
	ramp_map[Vector2i(x, z)] = {"corner": true, "side": false, "dir": dir_a, "dir2": dir_b}


func set_concave_prism(x: int, z: int, leg_x: int, leg_z: int, surface_h: float = 0.0) -> void:
	ramp_map[Vector2i(x, z)] = {
		"concave": true,
		"side": true,
		"corner": false,
		"dir": Vector2i(leg_x, 0),
		"dir2": Vector2i(0, leg_z),
		"surface_h": surface_h,
	}


func has_ramp(x: int, z: int) -> bool:
	return ramp_map.has(Vector2i(x, z))


static var _empty_ramp: Dictionary = {}


static func empty_ramp_entry() -> Dictionary:
	return _empty_ramp


func get_ramp_entry(x: int, z: int) -> Dictionary:
	var key := Vector2i(x, z)
	if not ramp_map.has(key):
		return _empty_ramp
	return ramp_map[key]


func is_ramp_corner(x: int, z: int) -> bool:
	var entry: Dictionary = get_ramp_entry(x, z)
	return entry.get("corner", false)


func get_ramp_dir(x: int, z: int) -> Vector2i:
	var entry: Dictionary = get_ramp_entry(x, z)
	return entry.get("dir", Vector2i.ZERO)


func get_ramp_dir2(x: int, z: int) -> Vector2i:
	var entry: Dictionary = get_ramp_entry(x, z)
	return entry.get("dir2", Vector2i.ZERO)


func get_worker_height_delta(lx: int, lz: int) -> float:
	if not _has_worker_snapshot:
		return 0.0
	if lx < 0 or lx >= SIZE or lz < 0 or lz >= SIZE:
		return 0.0
	return float(_worker_height_delta[lx][lz])


func get_worker_build_tile(lx: int, lz: int) -> int:
	if not _has_worker_snapshot:
		return -1
	if lx < 0 or lx >= SIZE or lz < 0 or lz >= SIZE:
		return -1
	return int(_worker_build_tile[lx][lz])


## Baked plant decorations are drawn by the vegetation layer and must not
## change the column the mesh plan was stored against.
func mesh_feature_tile(lx: int, lz: int) -> int:
	var ft: int = get_worker_feature_tile(lx, lz)
	if ft < 0:
		return -1
	if get_worker_feature_is_baked(lx, lz) and VoxelTypes.is_plant_decoration_tile(ft):
		return -1
	return ft


func get_worker_feature_tile(lx: int, lz: int) -> int:
	if not _has_worker_snapshot:
		return -1
	if lx < 0 or lx >= SIZE or lz < 0 or lz >= SIZE:
		return -1
	if lx >= _worker_feature_tile.size() or lz >= _worker_feature_tile[lx].size():
		return -1
	return int(_worker_feature_tile[lx][lz])


func get_worker_feature_is_baked(lx: int, lz: int) -> bool:
	if not _has_worker_snapshot:
		return false
	if lx < 0 or lx >= SIZE or lz < 0 or lz >= SIZE:
		return false
	if lx >= _worker_feature_baked.size() or _worker_feature_baked[lx] == null:
		return false
	if lz >= _worker_feature_baked[lx].size():
		return false
	return bool(_worker_feature_baked[lx][lz])


func _ensure_surface_map_storage() -> void:
	if surface_map.size() == SIZE and tile_map.size() == SIZE:
		var ready := true
		for x in SIZE:
			if surface_map[x] == null or surface_map[x].size() != SIZE \
					or tile_map[x] == null or tile_map[x].size() != SIZE:
				ready = false
				break
		if ready:
			_maps_resident = true
			return
	surface_map.resize(SIZE)
	tile_map.resize(SIZE)
	for x in SIZE:
		if surface_map[x] == null or not (surface_map[x] is Array):
			surface_map[x] = []
		if tile_map[x] == null or not (tile_map[x] is Array):
			tile_map[x] = []
		surface_map[x].resize(SIZE)
		tile_map[x].resize(SIZE)
	_maps_resident = true


func _bind_macro_surface_if_needed() -> void:
	if not _macro_enabled or _macro_surface_bound:
		return
	var grid: MacroLayerGrid = macro_grid if macro_grid != null else _macro_grid()
	if grid.is_surface_bound_to(surface_map, tile_map):
		grid.mark_ready()
		_macro_surface_bound = true
		return
	grid.bind_surface_arrays(surface_map, tile_map)
	grid.mark_ready()
	_macro_surface_bound = true


func maps_materialized() -> bool:
	return _maps_resident


func _has_resident_column_maps() -> bool:
	if _maps_resident:
		return true
	if surface_map.size() != SIZE or tile_map.size() != SIZE:
		return false
	for x in SIZE:
		if surface_map[x] == null or surface_map[x].size() != SIZE:
			return false
		if tile_map[x] == null or tile_map[x].size() != SIZE:
			return false
	_maps_resident = true
	return true


func ensure_legacy_maps_synced() -> void:
	if not _macro_enabled:
		return
	_bind_macro_surface_if_needed()
	if not macro_grid.is_ready():
		return
	ensure_macro_ramp_flags_synced()
	if not _legacy_maps_dirty:
		return
	macro_grid.sync_to_legacy_maps(surface_map, tile_map)
	_legacy_maps_dirty = false


func sync_legacy_cells(local_cells: Array) -> void:
	if not _macro_active() or not macro_grid.is_ready():
		return
	macro_grid.sync_cells_to_legacy_maps(surface_map, tile_map, local_cells)


func patch_local_column(lx: int, lz: int, surface_y: float, surface_tile: int) -> void:
	if lx < 0 or lx >= SIZE or lz < 0 or lz >= SIZE:
		return
	if _macro_active() and macro_grid.is_ready():
		_ensure_surface_map_storage()
		macro_grid.bind_surface_arrays(surface_map, tile_map)
		var stratum: int = macro_grid.get_stratum_layers(lx, lz)
		var flags: int = macro_grid.get_flags(lx, lz)
		macro_grid.set_column(lx, lz, surface_y, surface_tile, stratum, flags)
		_legacy_maps_dirty = false
		if _has_halo_surface:
			_halo_surface[lx + HALO][lz + HALO] = surface_y
		return
	if surface_map.size() != SIZE or tile_map.size() != SIZE:
		surface_map.resize(SIZE)
		tile_map.resize(SIZE)
		for x in SIZE:
			if surface_map[x] == null or not (surface_map[x] is Array):
				surface_map[x] = []
			if tile_map[x] == null or not (tile_map[x] is Array):
				tile_map[x] = []
			surface_map[x].resize(SIZE)
			tile_map[x].resize(SIZE)
	surface_map[lx][lz] = surface_y
	tile_map[lx][lz] = surface_tile
	if _has_halo_surface:
		_halo_surface[lx + HALO][lz + HALO] = surface_y


func get_surface_y(x: int, z: int) -> float:
	if x >= 0 and x < SIZE and z >= 0 and z < SIZE:
		if _micro_active() and micro_grid.has_brick(x, z):
			return micro_grid.get_surface_y(x, z)
		if _maps_resident:
			return float(surface_map[x][z])
		if _has_resident_column_maps():
			return float(surface_map[x][z])
	if x >= 0 and x < SIZE and z >= 0 and z < SIZE:
		if _macro_active() and macro_grid.is_ready():
			return macro_grid.get_surface_y(x, z)
	if not world:
		return 0.0
	var wx = position.x * SIZE + x
	var wz = position.y * SIZE + z
	return world.get_surface_height_uncached(float(wx), float(wz))

func get_tile_type(x: int, z: int) -> int:
	if x >= 0 and x < SIZE and z >= 0 and z < SIZE:
		if _micro_active() and micro_grid.has_brick(x, z):
			return micro_grid.get_surface_tile(x, z)
		if _maps_resident:
			return int(tile_map[x][z])
		if _has_resident_column_maps():
			return int(tile_map[x][z])
	if x >= 0 and x < SIZE and z >= 0 and z < SIZE:
		if _macro_active() and macro_grid.is_ready():
			return macro_grid.get_surface_tile(x, z)
	if not world:
		return VoxelTypes.AIR
	var wx = position.x * SIZE + x
	var wz = position.y * SIZE + z
	return world.get_tile_type_uncached(float(wx), float(wz))

static func _surface_match_epsilon() -> float:
	return _WorldSettings.get_active().layer_height() * 0.35


func is_in_bounds(x: int, y: int, z: int) -> bool:
	return x >= 0 and x < SIZE and y >= 0 and y < HEIGHT and z >= 0 and z < SIZE

func get_voxel_global(gx: int, gy: int, gz: int) -> int:
	if gy < 0 or gy >= HEIGHT:
		return VoxelTypes.AIR
	var local_x = gx % SIZE
	var local_z = gz % SIZE
	if local_x < 0: local_x += SIZE
	if local_z < 0: local_z += SIZE
	var chunk_x = floori(gx / float(SIZE))
	var chunk_z = floori(gz / float(SIZE))
	if chunk_x == position.x and chunk_z == position.y:
		return get_voxel(local_x, gy, local_z)
	return _compute_voxel_at_world(gx, gy, gz)

func _compute_voxel_at_world(wx: int, wy: int, wz: int) -> int:
	if not world:
		return VoxelTypes.AIR
	if world.has_method("get_voxel"):
		return world.get_voxel(float(wx), float(wy), float(wz))
	var surface_y = world.get_surface_height_uncached(float(wx), float(wz))
	if float(wy) > surface_y + 0.5:
		return VoxelTypes.AIR
	if abs(float(wy) - surface_y) < _surface_match_epsilon():
		return world.get_tile_type_uncached(float(wx), float(wz))
	var biome = world.get_biome(float(wx), float(wy), float(wz))
	return VoxelTypes.biome_to_voxel_id.get(biome.get("name", "air"), VoxelTypes.AIR)
