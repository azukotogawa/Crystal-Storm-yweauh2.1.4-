class_name ChunkData

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
var ramp_map: Dictionary = {}  # Vector2i(local x,z) -> Vector2i (direction toward higher neighbor)
var river_ctx: RiverJobContext = null

const SIZE := 16
const HEIGHT := 160
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
			
			# Force fresh computation for rivers
			if use_uncached:
				surface_map[x][z] = world.get_surface_height_uncached(wx, wz)
				tile_map[x][z] = world.get_tile_type_uncached(wx, wz)
			else:
				surface_map[x][z] = world.get_surface_height(wx, wz)
				tile_map[x][z] = world.get_tile_type(wx, wz)

func set_voxel(x: int, y: int, z: int, value: int):
	# For heightfield, we only "set" at surface y via the maps (done in bg compute).
	# This is a no-op for the removed 3D storage. Keep signature for compatibility.
	pass

func get_voxel(x: int, y: int, z: int) -> int:
	# Synthesize from heightfield maps: only the surface y has the tile, everything else is AIR.
	if x >= 0 and x < SIZE and z >= 0 and z < SIZE and surface_map:
		var sy: float = float(surface_map[x][z])
		if absf(float(y) - sy) < 0.6:
			return get_tile_type(x, z)
	return VoxelTypes.AIR

func get_visibility(x: int, y: int, z: int) -> bool:
	if x >= 0 and x < SIZE and z >= 0 and z < SIZE and surface_map:
		var sy: float = float(surface_map[x][z])
		if absf(float(y) - sy) < 0.6:
			return get_tile_type(x, z) != VoxelTypes.AIR
	return false

func set_visibility(x: int, y: int, z: int, value: bool):
	pass  # no-op, derived from maps

# Aliases for the "one voxel tall" + reveal work from the session
func is_visible(x: int, y: int, z: int) -> bool:
	return get_visibility(x, y, z)

func set_visible(x: int, y: int, z: int, visible: bool):
	set_visibility(x, y, z, visible)

func set_ramp(x: int, z: int, dir: Vector2i) -> void:
	ramp_map[Vector2i(x, z)] = dir


func has_ramp(x: int, z: int) -> bool:
	return ramp_map.has(Vector2i(x, z))


func get_ramp_dir(x: int, z: int) -> Vector2i:
	return ramp_map.get(Vector2i(x, z), Vector2i.ZERO)


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
	if abs(float(wy) - surface_y) < 0.6:
		return world.get_tile_type_uncached(float(wx), float(wz))
	var biome = world.get_biome(float(wx), float(wy), float(wz))
	return VoxelTypes.biome_to_voxel_id.get(biome.get("name", "air"), VoxelTypes.AIR)
