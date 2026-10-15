class_name ChunkData

var position: Vector2i
var world: InfiniteNoiseWorld = null


var surface_map: Array = []
var tile_map: Array = []
var river_ctx: RiverJobContext = null

const SIZE := 16
const HEIGHT := 160

func _init(coord: Vector2i, world_ref: InfiniteNoiseWorld = null):
	position = coord
	world = world_ref
	
	# Legacy 3D paths (if any) will see AIR / false.


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
			
			if use_uncached:
				surface_map[x][z] = int(world.get_surface_height_uncached(wx, wz))
				tile_map[x][z] = world.get_tile_type_uncached(wx, wz)
			else:
				surface_map[x][z] = int(world.get_surface_height(wx, wz))
				tile_map[x][z] = world.get_tile_type(wx, wz)

func set_voxel(x: int, y: int, z: int, value: int):
	pass

func get_voxel(x: int, y: int, z: int) -> int:
	if x >= 0 and x < SIZE and z >= 0 and z < SIZE and surface_map:
		var sy = surface_map[x][z]
		if y == sy:
			return get_tile_type(x, z)
	return VoxelTypes.AIR

func get_visibility(x: int, y: int, z: int) -> bool:
	if x >= 0 and x < SIZE and z >= 0 and z < SIZE and surface_map:
		var sy = surface_map[x][z]
		if y == sy:
			return get_tile_type(x, z) != VoxelTypes.AIR
	return false

func set_visibility(x: int, y: int, z: int, value: bool):
	pass

func is_visible(x: int, y: int, z: int) -> bool:
	return get_visibility(x, y, z)

func set_visible(x: int, y: int, z: int, visible: bool):
	set_visibility(x, y, z, visible)

func get_surface_y(x: int, z: int) -> int:
	if x >= 0 and x < SIZE and z >= 0 and z < SIZE and surface_map:
		return surface_map[x][z]
	if not world:
		return 0
	var wx = position.x * SIZE + x
	var wz = position.y * SIZE + z
	return int(world.get_surface_height_uncached(float(wx), float(wz)))  # fallback; use uncached for thread safety (called from bg meshing)

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
	if abs(float(wy) - surface_y) < 0.6:
		return world.get_tile_type_uncached(float(wx), float(wz))
	var biome = world.get_biome(float(wx), float(wy), float(wz))
	return VoxelTypes.biome_to_voxel_id.get(biome.get("name", "air"), VoxelTypes.AIR)
