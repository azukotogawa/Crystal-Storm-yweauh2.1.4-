class_name VoxelTypes
extends RefCounted

const AIR := 255
const OCEAN := 0
const OCEAN2 := 1
const OCEAN3 := 2
const BEACH := 3
const BEACH2 := 4
const BEACH3 := 5
const GRASSLAND := 6
const GRASSLAND2 := 7
const GRASSLAND3 := 8
const GRASSLAND4 := 9
const GRASSLAND5 := 10
const HILLS  := 11
const HILLS2 := 12
const HILLS3 := 13
const HILLS4 := 14
const MOUNTAIN := 15
const MOUNTAIN2 := 16
const MOUNTAIN3 := 17
const MOUNTAIN4 := 18
const MOUNTAIN5 := 19
const MOUNTAIN6 := 20
const MOUNTAIN7 := 21
const SNOW := 22
const SNOW2 := 23
const SNOW3 := 24
const VALLEY := 25
const VALLEY2 := 26
const VALLEY3 := 27
const DESERT := 28
const DESERT2 := 29
const DESERT3 := 30
const TUNDRA := 31
const TUNDRA2 := 32
const TUNDRA3 := 33
const BASIN := 34
const BASIN2 := 35
const BASIN3 := 36
const RIVER := 37
const WATER := 38
const STONE := 39
const STONE2 := 40
const DIRT := 41
const DIRT2 := 42
const CAVE_STONE := 43
const CRYSTAL := 44
const CRYSTAL_VEIN := 50
const CRYSTAL_SHARD_GROUND := 51
const CRYSTAL_SCAR := 52
const GRASS_TUFT := 45
const BUSH := 46
const TREE_TRUNK := 47
const FARMLAND := 48
const TOWN_PATH := 49


static func is_plant_decoration_tile(tile_type: int) -> bool:
	return tile_type == GRASS_TUFT \
		or tile_type == BUSH \
		or tile_type == TREE_TRUNK \
		or tile_type == GRASSLAND2 \
		or tile_type == GRASSLAND3 \
		or tile_type == HILLS2

## new_tile_set.tres / voxelsnew.png use a different 64 px strip layout — do not bind to ChunkView.
const ATLAS_TEXTURE_PATH := "res://assets/tiles/Cube.png"
const ATLAS_GRID_COLUMNS := 7
const ATLAS_GRID_ROWS := 10
const ATLAS_TILE_PIXELS := 32
const SOIL_BOTTOM := Vector2i(6, 7)
const ROCK_BOTTOM := Vector2i(5, 7)
const SAND_BOTTOM := Vector2i(4, 7)
const CRYSTAL_BOTTOM := Vector2i(3, 8)
const CRYSTAL_SIDE := Vector2i(4, 9)


static func get_atlas_coord(tile_type: int) -> Vector2i:
	return ATLAS_COORDS.get(tile_type, Vector2i(6, 0))


## Minecraft-style face picking: grass tops on FACE_TOP, dirt/earth on vertical sides, a darker underside.
static func get_atlas_coord_for_face(tile_type: int, face_code: int) -> Vector2i:
	if face_code <= 0 or face_code >= 7:
		return get_atlas_coord(tile_type)
	if face_code == 2:
		return _bottom_for(tile_type)
	if _is_grass_surface(tile_type):
		return get_atlas_coord(DIRT) if face_code >= 3 else get_atlas_coord(tile_type)
	if _is_forest_surface(tile_type):
		return get_atlas_coord(TREE_TRUNK) if face_code >= 3 else get_atlas_coord(tile_type)
	if _is_snow_surface(tile_type):
		return get_atlas_coord(STONE2) if face_code >= 3 else get_atlas_coord(tile_type)
	if tile_type == DIRT or tile_type == DIRT2:
		return Vector2i(5, 6) if face_code >= 3 else get_atlas_coord(tile_type)
	if tile_type == CRYSTAL_VEIN:
		return Vector2i(4, 5) if face_code >= 3 else get_atlas_coord(tile_type)
	if tile_type == CRYSTAL or tile_type == CRYSTAL_SHARD_GROUND or tile_type == CRYSTAL_SCAR:
		return CRYSTAL_SIDE if face_code >= 3 else get_atlas_coord(tile_type)
	if _column_rock(tile_type):
		if face_code >= 3:
			var rock_top := get_atlas_coord(tile_type)
			return Vector2i(0, 4) if rock_top == Vector2i(2, 4) else Vector2i(2, 4)
		return get_atlas_coord(tile_type)
	if _is_desert_surface(tile_type):
		if face_code >= 3:
			var sand_top := get_atlas_coord(tile_type)
			return Vector2i(0, 7) if sand_top == Vector2i(2, 7) else Vector2i(2, 7)
		return get_atlas_coord(tile_type)
	if _is_stone_surface(tile_type):
		return get_atlas_coord(tile_type)
	return get_atlas_coord(tile_type)


const GRASS_TOP_VARIANTS: Array[Vector2i] = [
	Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2),
]
const DIRT_VARIANTS: Array[Vector2i] = [
	Vector2i(3, 2), Vector2i(0, 6), Vector2i(5, 6),
]
const STONE_VARIANTS: Array[Vector2i] = [
	Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 4),
]
const ORE_VARIANTS: Array[Vector2i] = [
	Vector2i(6, 1), Vector2i(4, 5), Vector2i(5, 5),
]
const CAVE_ROCK_VARIANTS: Array[Vector2i] = [
	Vector2i(3, 6), Vector2i(4, 6), Vector2i(6, 6),
]
const SAND_VARIANTS: Array[Vector2i] = [
	Vector2i(0, 7), Vector2i(1, 7), Vector2i(2, 7),
]
const BEACH_VARIANTS: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
]
const LEAF_VARIANTS: Array[Vector2i] = [
	Vector2i(0, 3), Vector2i(2, 3), Vector2i(4, 3),
]
const WOOD_VARIANTS: Array[Vector2i] = [
	Vector2i(1, 3), Vector2i(3, 3), Vector2i(5, 3),
]
const SNOW_VARIANTS: Array[Vector2i] = [
	Vector2i(0, 5), Vector2i(1, 5), Vector2i(2, 5),
]
const TUNDRA_VARIANTS: Array[Vector2i] = [
	Vector2i(0, 8), Vector2i(1, 8), Vector2i(2, 8),
]
const BASIN_VARIANTS: Array[Vector2i] = [
	Vector2i(0, 9), Vector2i(1, 9), Vector2i(2, 9),
]
const VALLEY_VARIANTS: Array[Vector2i] = [
	Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 9),
]
const DRY_GRASS_VARIANTS: Array[Vector2i] = [
	Vector2i(3, 1), Vector2i(4, 2), Vector2i(5, 2),
]
const FARMLAND_VARIANTS: Array[Vector2i] = [
	Vector2i(4, 1), Vector2i(4, 8), Vector2i(5, 8),
]
const PATH_VARIANTS: Array[Vector2i] = [
	Vector2i(5, 1), Vector2i(6, 8), Vector2i(6, 9),
]
const OCEAN_VARIANTS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(2, 0), Vector2i(4, 0),
]
const RIVER_VARIANTS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(3, 0), Vector2i(5, 0),
]


static func _green_grass_top(tile_type: int) -> bool:
	return tile_type == GRASSLAND or tile_type == GRASSLAND2 or tile_type == GRASSLAND3


static func _column_pick(cells: Array[Vector2i], world_x: int, world_z: int, salt: int) -> Vector2i:
	var n: int = world_x * 374761393 + world_z * 668265263 + salt * 1442695041
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	if n < 0:
		n = -n
	return cells[n % cells.size()]


## Ramps (face >= 7) use the landing top. Bottoms stay the underside cell.
static func _pick_other(cells: Array[Vector2i], world_x: int, world_z: int, salt: int, avoid: Vector2i) -> Vector2i:
	var picked := _column_pick(cells, world_x, world_z, salt)
	if picked != avoid:
		return picked
	var at := cells.find(picked)
	if at < 0:
		return picked
	return cells[(at + 1) % cells.size()]


static func _bottom_for(tile_type: int) -> Vector2i:
	if tile_type == CRYSTAL or tile_type == CRYSTAL_VEIN or tile_type == CRYSTAL_SHARD_GROUND or tile_type == CRYSTAL_SCAR:
		return CRYSTAL_BOTTOM
	if _is_snow_only(tile_type) or _column_rock(tile_type) or tile_type == CAVE_STONE or _is_stone_surface(tile_type):
		return ROCK_BOTTOM
	if _is_desert_surface(tile_type) or _is_beach(tile_type):
		return SAND_BOTTOM
	return SOIL_BOTTOM


static func face_atlas(tile_type: int, face_code: int, world_x: int, world_z: int) -> Vector2i:
	var face := face_code
	if face >= 7:
		face = 0
	if face == 2:
		return _bottom_for(tile_type)
	if _green_grass_top(tile_type) and face == 0:
		return _column_pick(GRASS_TOP_VARIANTS, world_x, world_z, 11)
	if (tile_type == DIRT or tile_type == DIRT2) and face == 0:
		return _column_pick(DIRT_VARIANTS, world_x, world_z, 29)
	if (tile_type == DIRT or tile_type == DIRT2) and face >= 3:
		var dirt_top := _column_pick(DIRT_VARIANTS, world_x, world_z, 29)
		return _pick_other(DIRT_VARIANTS, world_x, world_z, 31, dirt_top)
	if (_is_grass_surface(tile_type)) and face >= 3:
		return _column_pick(DIRT_VARIANTS, world_x, world_z, 29)
	if tile_type == CAVE_STONE:
		var cave_top := _column_pick(CAVE_ROCK_VARIANTS, world_x, world_z, 83)
		if face >= 3:
			return _pick_other(CAVE_ROCK_VARIANTS, world_x, world_z, 89, cave_top)
		return cave_top
	if tile_type == CRYSTAL_VEIN:
		var vein_top := _column_pick(ORE_VARIANTS, world_x, world_z, 67)
		if face >= 3:
			return _pick_other(ORE_VARIANTS, world_x, world_z, 71, vein_top)
		return vein_top
	if tile_type == CRYSTAL or tile_type == CRYSTAL_SHARD_GROUND or tile_type == CRYSTAL_SCAR:
		if face >= 3:
			return CRYSTAL_SIDE
		return get_atlas_coord(tile_type)
	if _column_rock(tile_type):
		var rock_top := _column_pick(STONE_VARIANTS, world_x, world_z, 41)
		if face >= 3:
			return _pick_other(STONE_VARIANTS, world_x, world_z, 43, rock_top)
		return rock_top
	if _is_desert_surface(tile_type):
		var sand_top := _column_pick(SAND_VARIANTS, world_x, world_z, 101)
		if face >= 3:
			return _pick_other(SAND_VARIANTS, world_x, world_z, 103, sand_top)
		return sand_top
	if _is_beach(tile_type):
		return _column_pick(BEACH_VARIANTS, world_x, world_z, 103)
	if _is_forest_surface(tile_type) and face == 0:
		return _column_pick(LEAF_VARIANTS, world_x, world_z, 107)
	if _is_forest_surface(tile_type) and face >= 3:
		return _column_pick(WOOD_VARIANTS, world_x, world_z, 109)
	if tile_type == TREE_TRUNK:
		return _column_pick(WOOD_VARIANTS, world_x, world_z, 109)
	if tile_type == BUSH and face == 0:
		return _column_pick(LEAF_VARIANTS, world_x, world_z, 107)
	if _is_tundra(tile_type) and face == 0:
		return _column_pick(TUNDRA_VARIANTS, world_x, world_z, 113)
	if _is_tundra(tile_type) and face >= 3:
		return _column_pick(STONE_VARIANTS, world_x, world_z, 41)
	if _is_snow_only(tile_type) and face == 0:
		return _column_pick(SNOW_VARIANTS, world_x, world_z, 127)
	if _is_snow_only(tile_type) and face >= 3:
		return _column_pick(STONE_VARIANTS, world_x, world_z, 41)
	if _is_basin(tile_type):
		return _column_pick(BASIN_VARIANTS, world_x, world_z, 131)
	if _is_valley(tile_type):
		return _column_pick(VALLEY_VARIANTS, world_x, world_z, 137)
	if _is_dry_grass(tile_type) and face == 0:
		return _column_pick(DRY_GRASS_VARIANTS, world_x, world_z, 139)
	if tile_type == FARMLAND and face == 0:
		return _column_pick(FARMLAND_VARIANTS, world_x, world_z, 149)
	if tile_type == TOWN_PATH and face == 0:
		return _column_pick(PATH_VARIANTS, world_x, world_z, 151)
	if _is_ocean(tile_type):
		return _column_pick(OCEAN_VARIANTS, world_x, world_z, 157)
	if tile_type == RIVER or tile_type == WATER:
		return _column_pick(RIVER_VARIANTS, world_x, world_z, 163)
	return get_atlas_coord_for_face(tile_type, face_code)


static func _column_rock(tile_type: int) -> bool:
	return tile_type == STONE or tile_type == STONE2 \
		or tile_type == MOUNTAIN or tile_type == MOUNTAIN2 \
		or tile_type == MOUNTAIN3 or tile_type == MOUNTAIN4 or tile_type == MOUNTAIN5 \
		or tile_type == MOUNTAIN6 or tile_type == MOUNTAIN7


static func _is_grass_surface(tile_type: int) -> bool:
	return tile_type in [
		GRASSLAND, GRASSLAND2, GRASSLAND3, GRASSLAND4, GRASSLAND5,
		GRASS_TUFT, FARMLAND, TOWN_PATH,
	]


static func _is_forest_surface(tile_type: int) -> bool:
	return tile_type in [HILLS, HILLS2, HILLS3, HILLS4]


static func _is_snow_surface(tile_type: int) -> bool:
	return _is_snow_only(tile_type) or _is_tundra(tile_type)


static func _is_snow_only(tile_type: int) -> bool:
	return tile_type == SNOW or tile_type == SNOW2 or tile_type == SNOW3


static func _is_tundra(tile_type: int) -> bool:
	return tile_type == TUNDRA or tile_type == TUNDRA2 or tile_type == TUNDRA3


static func _is_beach(tile_type: int) -> bool:
	return tile_type == BEACH or tile_type == BEACH2 or tile_type == BEACH3


static func _is_basin(tile_type: int) -> bool:
	return tile_type == BASIN or tile_type == BASIN2 or tile_type == BASIN3


static func _is_valley(tile_type: int) -> bool:
	return tile_type == VALLEY or tile_type == VALLEY2 or tile_type == VALLEY3


static func _is_dry_grass(tile_type: int) -> bool:
	return tile_type == GRASSLAND4 or tile_type == GRASSLAND5 or tile_type == GRASS_TUFT


static func _is_ocean(tile_type: int) -> bool:
	return tile_type == OCEAN or tile_type == OCEAN2 or tile_type == OCEAN3


static func _is_stone_surface(tile_type: int) -> bool:
	return tile_type in [
		MOUNTAIN, MOUNTAIN2, MOUNTAIN3, MOUNTAIN4, MOUNTAIN5, MOUNTAIN6, MOUNTAIN7,
		STONE, STONE2, CAVE_STONE, VALLEY, VALLEY2, VALLEY3, BASIN, BASIN2, BASIN3,
	]


static func _is_desert_surface(tile_type: int) -> bool:
	return tile_type in [DESERT, DESERT2, DESERT3]


static func atlas_grid_vec2() -> Vector2:
	return Vector2(float(ATLAS_GRID_COLUMNS), float(ATLAS_GRID_ROWS))


const biome_to_voxel_id = {
	"deep ocean": VoxelTypes.OCEAN,
	"ocean": VoxelTypes.OCEAN2,
	"shallow sea": VoxelTypes.OCEAN3,

	"beach": VoxelTypes.BEACH,
	"sandy beach": VoxelTypes.BEACH2,
	"coral reef": VoxelTypes.BEACH3,

	"grass": VoxelTypes.GRASSLAND,
	"meadow": VoxelTypes.GRASSLAND2,
	"plains": VoxelTypes.GRASSLAND3,
	"steppe": VoxelTypes.GRASSLAND4,
	"savanna": VoxelTypes.GRASSLAND5,
	"marsh": VoxelTypes.GRASSLAND,

	"forest": VoxelTypes.HILLS,
	"dense forest": VoxelTypes.HILLS2,
	"pine forest": VoxelTypes.HILLS3,
	"jungle": VoxelTypes.HILLS4,

	"mountain": VoxelTypes.MOUNTAIN,
	"ridge": VoxelTypes.MOUNTAIN2,
	"peak": VoxelTypes.MOUNTAIN3,
	"volcano": VoxelTypes.MOUNTAIN4,
	"precipice": VoxelTypes.MOUNTAIN5,
	"zenith": VoxelTypes.MOUNTAIN6,
	"plateau": VoxelTypes.MOUNTAIN7,

	"snow": VoxelTypes.SNOW,
	"ice field": VoxelTypes.SNOW2,
	"glacier": VoxelTypes.SNOW3,

	"ravine": VoxelTypes.VALLEY,
	"canyon": VoxelTypes.VALLEY2,
	"valley": VoxelTypes.VALLEY3,

	"desert": VoxelTypes.DESERT,
	"dunes": VoxelTypes.DESERT2,
	"badlands": VoxelTypes.DESERT3,

	"tundra": VoxelTypes.TUNDRA,
	"frozen plains": VoxelTypes.TUNDRA2,
	"permafrost": VoxelTypes.TUNDRA3,

	"dry lake": VoxelTypes.BASIN,
	"salt flat": VoxelTypes.BASIN2,
	"basin": VoxelTypes.BASIN3,

	"river": VoxelTypes.RIVER,
	"water": VoxelTypes.WATER,
	"stone": VoxelTypes.STONE,
	"rock": VoxelTypes.STONE2,
	"dirt": VoxelTypes.DIRT,
	"subsoil": VoxelTypes.DIRT2,
	"cave": VoxelTypes.CAVE_STONE,
	"cave stone": VoxelTypes.CAVE_STONE,

	"grass tuft": VoxelTypes.GRASS_TUFT,
	"bush": VoxelTypes.BUSH,
	"tree": VoxelTypes.TREE_TRUNK,
	"farmland": VoxelTypes.FARMLAND,
	"town path": VoxelTypes.TOWN_PATH,
}

const ATLAS_COORDS = {
	VoxelTypes.AIR: Vector2i(6,0),
	
	VoxelTypes.OCEAN: Vector2i(0,0),
	VoxelTypes.OCEAN2: Vector2i(0,0),
	VoxelTypes.OCEAN3: Vector2i(0,0),

	VoxelTypes.BEACH: Vector2i(0,1),
	VoxelTypes.BEACH2: Vector2i(1,1),
	VoxelTypes.BEACH3: Vector2i(2,1),

	VoxelTypes.GRASSLAND: Vector2i(0,2),
	VoxelTypes.GRASSLAND2: Vector2i(1,2),
	VoxelTypes.GRASSLAND3: Vector2i(2,2),
	VoxelTypes.GRASSLAND4: Vector2i(3,1),
	VoxelTypes.GRASSLAND5: Vector2i(4,2),

	VoxelTypes.HILLS: Vector2i(0,3),
	VoxelTypes.HILLS2: Vector2i(1,3),
	VoxelTypes.HILLS3: Vector2i(1,3),
	VoxelTypes.HILLS4: Vector2i(4,3),

	VoxelTypes.MOUNTAIN: Vector2i(0,4),
	VoxelTypes.MOUNTAIN2: Vector2i(1,4),
	VoxelTypes.MOUNTAIN3: Vector2i(3,5),
	VoxelTypes.MOUNTAIN4: Vector2i(3,4),
	VoxelTypes.MOUNTAIN5: Vector2i(4,4),
	VoxelTypes.MOUNTAIN6: Vector2i(5,4),
	VoxelTypes.MOUNTAIN7: Vector2i(6,4),

	VoxelTypes.SNOW: Vector2i(0,5),
	VoxelTypes.SNOW2: Vector2i(1,5),
	VoxelTypes.SNOW3: Vector2i(2,5),

	VoxelTypes.VALLEY: Vector2i(0,6),
	VoxelTypes.VALLEY2: Vector2i(1,6),
	VoxelTypes.VALLEY3: Vector2i(2,6),

	VoxelTypes.DESERT: Vector2i(0,7),
	VoxelTypes.DESERT2: Vector2i(1,7),
	VoxelTypes.DESERT3: Vector2i(2,7),

	VoxelTypes.TUNDRA: Vector2i(0,8),
	VoxelTypes.TUNDRA2: Vector2i(1,8),
	VoxelTypes.TUNDRA3: Vector2i(2,8),

	VoxelTypes.BASIN: Vector2i(0,9),
	VoxelTypes.BASIN2: Vector2i(1,9),
	VoxelTypes.BASIN3: Vector2i(2,9),

	VoxelTypes.RIVER: Vector2i(1,0),
	VoxelTypes.WATER: Vector2i(1,0),
	VoxelTypes.STONE: Vector2i(0,4),
	VoxelTypes.STONE2: Vector2i(2,4),
	VoxelTypes.DIRT: Vector2i(3,2),
	VoxelTypes.DIRT2: Vector2i(0,6),
	VoxelTypes.CAVE_STONE: Vector2i(4,4),

	VoxelTypes.CRYSTAL: Vector2i(6,2),
	VoxelTypes.CRYSTAL_VEIN: Vector2i(6,1),
	VoxelTypes.CRYSTAL_SHARD_GROUND: Vector2i(6,3),
	VoxelTypes.CRYSTAL_SCAR: Vector2i(6,5),

	VoxelTypes.GRASS_TUFT: Vector2i(4,2),
	VoxelTypes.BUSH: Vector2i(4,3),
	VoxelTypes.TREE_TRUNK: Vector2i(1,3),
	VoxelTypes.FARMLAND: Vector2i(4,1),
	VoxelTypes.TOWN_PATH: Vector2i(5,1),
}
