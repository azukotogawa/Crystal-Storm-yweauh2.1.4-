class_name ChunkData

const _WorldSettings = preload("res://config/world_settings.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")

var position: Vector2i
var world: InfiniteNoiseWorld = null

# 3D voxels/visibility removed for the one-voxel-thick heightfield path (was a major
# main-thread alloc/init cost on every ChunkData.new during streaming).
# get_voxel / is_visible / etc. now derive from the 2D maps (see overrides below).
# Legacy full-3D code paths (the old greedy) are bypassed anyway.

# Precomputed surface heights + tile IDs for this chunk's 16x16 columns.
# Computed in bg worker for perf. Used everywhere for meshing, collision, etc.
var surface_map: Array = []  # [x][z] -> float
var tile_map: Array = []       # [x][z] -> int  (precomputed on main thread for this chunk)
# Vector2i(local x,z) -> { "corner": bool, "dir": Vector2i, "dir2": Vector2i }
var ramp_map: Dictionary = {}
var river_ctx: RiverJobContext = null

# Snapshotted on main thread before worker generation (avoids TerrainEdits/FeatureRegistry races).
var _worker_height_delta: Array = []
var _worker_build_tile: Array = []
var _worker_feature_tile: Array = []
var _has_worker_snapshot: bool = false
## 1-cell halo for greedy meshing at chunk borders (worker-safe).
var _halo_surface: Array = []
var _has_halo_surface: bool = false

const SIZE := 16
const HALO := 1
## Legacy bound — prefer WorldSettings.get_active().chunk_height_bound() for checks.
const HEIGHT := 48
# Note: Worldgen is now fully volumetric (get_voxel). HEIGHT is still used as a safety bound.

func _init(coord: Vector2i, world_ref: InfiniteNoiseWorld = null):
	position = coord
	world = world_ref
	
	# For one-voxel-thick heightfield terrain we only need the 2D surface maps.
	# Removed the full 3D voxels/visibility arrays and their heavy nested alloc+init
	# (was ~40k entries per chunk, ran on main thread in every ChunkData.new).
	# This is a major win for chunk streaming FPS and memory.
	# get_voxel / is_visible now synthesize from the maps for surface y only.
	# Legacy 3D paths (if any) will see AIR / false.

	# Note: surface_map / tile_map are *not* auto-computed here anymore.
	# They are computed in the bg worker (_generate_chunk) via _compute_column_maps(true)
	# so that noise for new chunks doesn't block the main thread on request.

## Call on main thread immediately before dispatching chunk gen to WorkerThreadPool.
func capture_worker_snapshot() -> void:
	_worker_height_delta.resize(SIZE)
	_worker_build_tile.resize(SIZE)
	_worker_feature_tile.resize(SIZE)
	for x in SIZE:
		_worker_height_delta[x] = []
		_worker_build_tile[x] = []
		_worker_feature_tile[x] = []
		_worker_height_delta[x].resize(SIZE)
		_worker_build_tile[x].resize(SIZE)
		_worker_feature_tile[x].resize(SIZE)
		for z in SIZE:
			var wx := position.x * SIZE + x
			var wz := position.y * SIZE + z
			_worker_height_delta[x][z] = _TerrainEdits.get_height_delta(wx, wz)
			_worker_build_tile[x][z] = _TerrainEdits.get_build_tile(wx, wz)
			_worker_feature_tile[x][z] = _FeatureRegistry.get_tile_override(wx, wz)
	_has_worker_snapshot = true
	_capture_halo_surface()


func _capture_halo_surface() -> void:
	if world == null:
		return
	var dim := SIZE + HALO * 2
	_halo_surface.resize(dim)
	for ix in dim:
		_halo_surface[ix] = []
		_halo_surface[ix].resize(dim)
		for iz in dim:
			var lx := ix - HALO
			var lz := iz - HALO
			if lx >= 0 and lx < SIZE and lz >= 0 and lz < SIZE:
				_halo_surface[ix][iz] = -9999.0
				continue
			var wx := position.x * SIZE + lx
			var wz := position.y * SIZE + lz
			var hdelta: float = _TerrainEdits.get_height_delta(wx, wz)
			_halo_surface[ix][iz] = world.get_surface_height_worker(float(wx), float(wz), hdelta)
	_has_halo_surface = true


func _refresh_halo_interior_from_maps() -> void:
	if not _has_halo_surface:
		return
	for x in SIZE:
		for z in SIZE:
			_halo_surface[x + HALO][z + HALO] = float(surface_map[x][z])


func get_halo_surface_y(lx: int, lz: int) -> float:
	if not _has_halo_surface:
		return -9999.0
	var ix := lx + HALO
	var iz := lz + HALO
	if ix < 0 or iz < 0 or ix >= _halo_surface.size() or iz >= _halo_surface[ix].size():
		return -9999.0
	return float(_halo_surface[ix][iz])


func _compute_column_maps(use_uncached: bool = true):
	if not world:
		return

	surface_map.resize(SIZE)
	tile_map.resize(SIZE)
	for x in SIZE:
		surface_map[x] = []
		tile_map[x] = []
		surface_map[x].resize(SIZE)
		tile_map[x].resize(SIZE)
		for z in SIZE:
			var wx := float(position.x * SIZE + x)
			var wz := float(position.y * SIZE + z)

			if use_uncached and _has_worker_snapshot:
				surface_map[x][z] = world.get_surface_height_worker(
					wx, wz, float(_worker_height_delta[x][z])
				)
				tile_map[x][z] = world.get_tile_type_worker(
					wx, wz,
					int(_worker_build_tile[x][z]),
					int(_worker_feature_tile[x][z])
				)
			elif use_uncached:
				surface_map[x][z] = world.get_surface_height_uncached(wx, wz)
				tile_map[x][z] = world.get_tile_type_uncached(wx, wz)
			else:
				surface_map[x][z] = world.get_surface_height(wx, wz)
				tile_map[x][z] = world.get_tile_type(wx, wz)
	if _has_halo_surface:
		_refresh_halo_interior_from_maps()

func set_voxel(x: int, y: int, z: int, value: int):
	# For heightfield, we only "set" at surface y via the maps (done in bg compute).
	# This is a no-op for the removed 3D storage. Keep signature for compatibility.
	pass

func get_voxel(x: int, y: int, z: int) -> int:
	# Synthesize from heightfield maps: only the surface y has the tile, everything else is AIR.
	if x >= 0 and x < SIZE and z >= 0 and z < SIZE and surface_map:
		var sy: float = float(surface_map[x][z])
		if absf(float(y) - sy) < _surface_match_epsilon():
			return get_tile_type(x, z)
	return VoxelTypes.AIR

func get_visibility(x: int, y: int, z: int) -> bool:
	if x >= 0 and x < SIZE and z >= 0 and z < SIZE and surface_map:
		var sy: float = float(surface_map[x][z])
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
	ramp_map[Vector2i(x, z)] = {"corner": false, "side": false, "dir": dir, "dir2": Vector2i.ZERO}


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


func get_surface_y(x: int, z: int) -> float:
	if x >= 0 and x < SIZE and z >= 0 and z < SIZE and surface_map:
		return float(surface_map[x][z])
	if not world:
		return 0.0
	var wx = position.x * SIZE + x
	var wz = position.y * SIZE + z
	return world.get_surface_height_uncached(float(wx), float(wz))

func get_tile_type(x: int, z: int) -> int:
	if x >= 0 and x < SIZE and z >= 0 and z < SIZE and tile_map and tile_map[x] and tile_map[x][z] != null:
		return tile_map[x][z]
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
