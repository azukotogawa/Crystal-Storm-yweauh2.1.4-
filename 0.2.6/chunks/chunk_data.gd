class_name ChunkData

const _WorldSettings = preload("res://config/world_settings.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldState = preload("res://world/world_state.gd")
const _MacroLayerGrid = preload("res://helpers/macro_layer_grid.gd")
const _MicroLayerGrid = preload("res://helpers/micro_layer_grid.gd")
const _WorldBakeService = preload("res://world/world_bake_service.gd")

var position: Vector2i
var world: InfiniteNoiseWorld = null

# 3D voxels/visibility removed for the one-voxel-thick heightfield path (was a major
# main-thread alloc/init cost on every ChunkData.new during streaming).
# get_voxel / is_visible / etc. now derive from the 2D maps (see overrides below).
# Legacy full-3D code paths (the old greedy) are bypassed anyway.

## Macro terrain authority (v2). Legacy maps are synced views for mesh/verify scripts.
var macro_grid = null
## Sparse localized micro refinement overlay (optional per column).
var micro_grid = null
var last_micro_examined: int = 0

# Compatibility façade — lazy-synced from macro_grid when legacy readers need it.
var surface_map: Array = []  # [x][z] -> float
var tile_map: Array = []       # [x][z] -> int
var _legacy_maps_dirty: bool = false
var _macro_enabled: bool = true
var _macro_surface_bound: bool = false
var _macro_ramp_flags_dirty: bool = false
var _maps_resident: bool = false
static var s_macro_enabled_from_env: bool = true
static var s_micro_enabled_from_env: bool = true
# Vector2i(local x,z) -> { "corner": bool, "dir": Vector2i, "dir2": Vector2i }
var ramp_map: Dictionary = {}

# Snapshotted on main thread before worker generation (avoids live WorldState races).
var _worker_height_delta: Array = []
var _worker_build_tile: Array = []
var _worker_feature_tile: Array = []
## True when feature tile comes from baked static vegetation (still pristine for mesh plans).
var _worker_feature_baked: Array = []
## Halo-region height deltas (world units), same dim as _halo_surface — worker-safe.
var _worker_halo_height_delta: Array = []
var _has_worker_snapshot: bool = false
## Mesh-input revision stamp captured with the frozen overlay arrays.
var overlay_mesh_stamp: Dictionary = {}
## Job-local micro skip set for one mesh stage (owned by the single in-flight worker for this data).
## Never shared across ChunkManager concurrent jobs — each job uses its own ChunkData.
var _mesh_job_micro_skip: Dictionary = {}
## 1-cell halo for greedy meshing at chunk borders (worker-safe).
var _halo_surface: Array = []
## Natural (pre-overlay) halo heights — baked base when available; used to recompose on dirty.
var _halo_base_surface: Array = []
var _has_halo_surface: bool = false
## Immutable baked base columns (pre-WorldState). Set by WorldBakeService apply.
var _baked_base_surface: Array = []
var _baked_base_tile: Array = []
var _has_baked_base: bool = false

const SIZE := 16
const HALO := 1
## Legacy bound — prefer WorldSettings.get_active().chunk_height_bound() for checks.
const HEIGHT := 48
# Note: Worldgen is now fully volumetric (get_voxel). HEIGHT is still used as a safety bound.

func _init(coord: Vector2i, world_ref: InfiniteNoiseWorld = null):
	position = coord
	world = world_ref
	_macro_enabled = s_macro_enabled_from_env
	_macro_ramp_flags_dirty = false

	# For one-voxel-thick heightfield terrain we only need the 2D surface maps.
	# Removed the full 3D voxels/visibility arrays and their heavy nested alloc+init
	# (was ~40k entries per chunk, ran on main thread in every ChunkData.new).
	# This is a major win for chunk streaming FPS and memory.
	# get_voxel / is_visible now synthesize from the maps for surface y only.
	# Legacy 3D paths (if any) will see AIR / false.

	# Note: surface_map / tile_map are *not* auto-computed here anymore.
	# They are computed in the bg worker (_generate_chunk) via _compute_column_maps(true)
	# so that noise for new chunks doesn't block the main thread on request.


## Reset a pooled ChunkData shell for a new stream load (main thread only).
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

## Rebind zero-copy surface view after snapshot restore (outside timers).
func touch_macro_view_pointers() -> void:
	if macro_grid == null:
		return
	_ensure_surface_map_storage()
	macro_grid.bind_surface_arrays(surface_map, tile_map)


## Pre-allocate macro surface bind outside timed hot paths (extended metadata stays lazy).
func prewarm_macro_storage() -> void:
	if not _macro_enabled:
		return
	touch_macro_view_pointers()
	_bind_macro_surface_if_needed()

## Call on main thread immediately before dispatching chunk gen to WorkerThreadPool.
## Copies mesh-input overlays from WorldState into frozen per-chunk arrays.
func capture_worker_snapshot() -> void:
	var ws = _WorldState.get_active()
	overlay_mesh_stamp = ws.capture_mesh_overlay_stamp()
	var layer_h: float = maxf(_WorldSettings.get_active().layer_height(), 0.001)
	_ensure_worker_overlay_storage()
	# Fast path: no overlay maps → zero-fill without Dictionary lookups (common on pristine bake walk).
	var overlays_empty: bool = (
		ws.height_delta.is_empty()
		and ws.build_tile.is_empty()
		and ws.tile_overrides.is_empty()
		and ws.feature_cells.is_empty()
		and (not ("seeded_tile_keys" in ws) or ws.seeded_tile_keys.is_empty())
	)
	if overlays_empty:
		for x in SIZE:
			for z in SIZE:
				_worker_height_delta[x][z] = 0.0
				_worker_build_tile[x][z] = -1
				_worker_feature_tile[x][z] = -1
				_worker_feature_baked[x][z] = false
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
				# Baked vegetation + world-seeded stamps (towns/roads) are pristine for mesh plans.
				var feat_entry: Dictionary = ws.feature_cells.get(key, {})
				var seeded: bool = bool(ws.seeded_tile_keys.get(key, false)) \
					if "seeded_tile_keys" in ws else false
				_worker_feature_baked[x][z] = bool(feat_entry.get("_baked_static", false)) or seeded
	_has_worker_snapshot = true
	_capture_halo_surface()


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
	_halo_surface.resize(dim)
	_halo_base_surface.resize(dim)
	_worker_halo_height_delta.resize(dim)
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
			# Main-thread capture only: freeze height delta for later worker refresh.
			var hdelta: float = float(int(ws.height_delta.get(key, 0))) * layer_h
			_worker_halo_height_delta[ix][iz] = hdelta
			var resolved: Dictionary = _resolve_halo_natural_height(wx, wz, bake)
			if bool(resolved.get("deferred", false)):
				_halo_base_surface[ix][iz] = -9999.0
				_halo_surface[ix][iz] = -9999.0
				continue
			var base_h: float = float(resolved.get("base", 0.0))
			_halo_base_surface[ix][iz] = base_h
			_halo_surface[ix][iz] = _WorldBakeService.compose_surface_height(base_h, hdelta)
	_has_halo_surface = true


## Main-thread: natural (pre-overlay) height for a halo world cell.
## Covered bake cells use package data only; missing packages defer (no noise).
func _resolve_halo_natural_height(wx: int, wz: int, bake) -> Dictionary:
	if bake != null and bake.valid and bake.has_method("covers_world_cell") \
			and bool(bake.covers_world_cell(wx, wz)):
		var sample: Dictionary = bake.sample_world_base(wx, wz)
		if sample.is_empty():
			if bake.has_method("note_halo_deferred"):
				bake.note_halo_deferred()
			return {"deferred": true}
		if bake.has_method("note_halo_bake_hit"):
			bake.note_halo_bake_hit()
		return {"base": float(sample.get("surface", 0.0)), "deferred": false}
	# Outside package bounds, or no valid bake: legacy noise (allowed for out-of-bounds).
	var h: float = world.get_surface_height_worker(float(wx), float(wz), 0.0)
	return {"base": h, "deferred": false}


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
	# Package layout matches WorldBakeService: index = lz * CELLS + lx
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


## Natural (pre-overlay) height for dig/build strata mesh.
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
	return _MicroLayerGrid.enabled()


static func configure_macro_terrain_from_env() -> void:
	s_macro_enabled_from_env = _MacroLayerGrid.enabled()


static func configure_micro_terrain_from_env() -> void:
	s_micro_enabled_from_env = _MicroLayerGrid.enabled()


## Benchmark-only: flip macro mode without OS env churn between paired samples.
static func set_macro_enabled_for_benchmark(on: bool) -> void:
	s_macro_enabled_from_env = on


static func set_micro_enabled_for_benchmark(on: bool) -> void:
	s_micro_enabled_from_env = on


func is_macro_terrain_enabled() -> bool:
	return _macro_enabled


func is_micro_terrain_enabled() -> bool:
	return s_micro_enabled_from_env


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


## Benchmark layout: resident macro_grid stays bound; only _macro_enabled toggles between paired runs.
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


## Batch macro metadata after column populate or mesh emit. ramp_map is source of truth.
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
		# Refresh frozen halo height-delta ring for dirty edge columns (main thread).
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
		feat_t = int(_worker_feature_tile[x][z])
	if _has_baked_base:
		surface_map[x][z] = _WorldBakeService.compose_surface_height(
			get_baked_base_height(x, z), hdelta
		)
		if build_t >= 0:
			tile_map[x][z] = build_t
		elif feat_t >= 0:
			tile_map[x][z] = feat_t
		else:
			tile_map[x][z] = get_baked_base_tile(x, z)
		if bake != null and bake.has_method("note_dirty_bake_hit"):
			bake.note_dirty_bake_hit()
		return
	# No stored base: try live bake sample only if this column is covered (worker-safe if resident).
	var wx_i: int = position.x * SIZE + x
	var wz_i: int = position.y * SIZE + z
	if bake != null and bake.valid and bake.has_method("covers_world_cell") \
			and bool(bake.covers_world_cell(wx_i, wz_i)):
		var sample: Dictionary = {}
		if bake.has_method("sample_base"):
			sample = bake.sample_base(position, x, z)
		if not sample.is_empty():
			if not _has_baked_base and bake.has_method("sample_base"):
				# Soft-fill single cell natural height for dig strata; keep maps consistent.
				pass
			surface_map[x][z] = _WorldBakeService.compose_surface_height(
				float(sample.get("surface", 0.0)), hdelta
			)
			if build_t >= 0:
				tile_map[x][z] = build_t
			elif feat_t >= 0:
				tile_map[x][z] = feat_t
			else:
				tile_map[x][z] = int(sample.get("tile", VoxelTypes.AIR))
			if bake.has_method("note_dirty_bake_hit"):
				bake.note_dirty_bake_hit()
			return
		# Covered but package unavailable: never re-noise static terrain.
		return
	# Outside package / no bake: legacy procedural column.
	var wx := float(wx_i)
	var wz := float(wz_i)
	if _has_worker_snapshot:
		surface_map[x][z] = world.get_surface_height_worker(wx, wz, hdelta)
		tile_map[x][z] = world.get_tile_type_worker(wx, wz, build_t, feat_t)
	else:
		surface_map[x][z] = world.get_surface_height_uncached(wx, wz)
		tile_map[x][z] = world.get_tile_type_uncached(wx, wz)


func _refresh_halo_for_local_cell(x: int, z: int) -> void:
	if not _has_halo_surface or world == null:
		return
	if _maps_resident:
		_halo_surface[x + HALO][z + HALO] = surface_map[x][z]
	_refresh_halo_border_for_local_cell(x, z)


## Main-thread only: refresh frozen halo height-delta cells around a local column.
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
				# Main-thread pre-snapshot path only.
				var wx: int = position.x * SIZE + lx
				var wz: int = position.y * SIZE + lz
				var key := Vector2i(wx, wz)
				var layer_h: float = maxf(_WorldSettings.get_active().layer_height(), 0.001)
				hdelta = float(int(_WorldState.get_active().height_delta.get(key, 0))) * layer_h
			# Recompose from frozen natural base — never re-noise covered bake cells.
			if ix < _halo_base_surface.size() and iz < _halo_base_surface[ix].size():
				var base_h: float = float(_halo_base_surface[ix][iz])
				if base_h <= -9000.0:
					_halo_surface[ix][iz] = -9999.0
				else:
					_halo_surface[ix][iz] = _WorldBakeService.compose_surface_height(base_h, hdelta)
			else:
				_halo_surface[ix][iz] = -9999.0


func _compute_column_maps(use_uncached: bool = true):
	# Local capture avoids mid-loop use of a field cleared by another thread/path.
	var w = world
	if w == null:
		return

	_ensure_surface_map_storage()
	# Prefer immutable baked base when present (should already be applied via pipeline).
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
					int(_worker_feature_tile[x][z])
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
	# For heightfield, we only "set" at surface y via the maps (done in bg compute).
	# This is a no-op for the removed 3D storage. Keep signature for compatibility.
	pass

func get_voxel(x: int, y: int, z: int) -> int:
	# Synthesize from heightfield maps: only the surface y has the tile, everything else is AIR.
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
	pass  # no-op, derived from maps

# Aliases for the "one voxel tall" + reveal work from the session
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


func set_ramp_side(x: int, z: int, face_dir: Vector2i, climb_dir: Vector2i) -> void:
	ramp_map[Vector2i(x, z)] = {"side": true, "corner": false, "dir": face_dir, "dir2": climb_dir}


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


func get_ramp_entry(x: int, z: int) -> Dictionary:
	return ramp_map.get(Vector2i(x, z), {})


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


func get_worker_feature_tile(lx: int, lz: int) -> int:
	if not _has_worker_snapshot:
		return -1
	if lx < 0 or lx >= SIZE or lz < 0 or lz >= SIZE:
		return -1
	if lx >= _worker_feature_tile.size() or lz >= _worker_feature_tile[lx].size():
		return -1
	return int(_worker_feature_tile[lx][lz])


## True when feature tile is baked static vegetation (not a runtime edit).
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


## Materialize legacy façade arrays from macro authority (verify/save readers only).
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


## Test/verify helper: patch one column on macro authority and legacy façade together.
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

# Seamless borders
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
	# Prefer the new full volumetric get_voxel when available (best natural rivers + true 3D caves + layers).
	# Falls back gracefully if the method is missing on older world instances.
	if world.has_method("get_voxel"):
		return world.get_voxel(float(wx), float(wy), float(wz))
	# Legacy heightfield path (kept for compatibility)
	var surface_y = world.get_surface_height_uncached(float(wx), float(wz))
	if float(wy) > surface_y + 0.5:
		return VoxelTypes.AIR
	if abs(float(wy) - surface_y) < _surface_match_epsilon():
		return world.get_tile_type_uncached(float(wx), float(wz))
	var biome = world.get_biome(float(wx), float(wy), float(wz))
	return VoxelTypes.biome_to_voxel_id.get(biome.get("name", "air"), VoxelTypes.AIR)
