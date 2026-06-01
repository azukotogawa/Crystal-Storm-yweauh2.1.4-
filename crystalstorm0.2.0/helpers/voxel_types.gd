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
const HILLS := 11
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

const biome_to_voxel_id = {
	"deep ocean": VoxelTypes.OCEAN,
	"ocean": VoxelTypes.OCEAN,
	"shallow sea": VoxelTypes.OCEAN,

	"beach": VoxelTypes.BEACH,
	"sandy beach": VoxelTypes.BEACH2,
	"coral reef": VoxelTypes.BEACH3,

	"grass": VoxelTypes.GRASSLAND,
	"meadow": VoxelTypes.GRASSLAND2,
	"plains": VoxelTypes.GRASSLAND3,
	"steppe": VoxelTypes.GRASSLAND4,
	"savanna": VoxelTypes.GRASSLAND5,

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

	"river": VoxelTypes.RIVER
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
	VoxelTypes.GRASSLAND4: Vector2i(3,2),
	VoxelTypes.GRASSLAND5: Vector2i(4,2),

	VoxelTypes.HILLS: Vector2i(0,3),
	VoxelTypes.HILLS2: Vector2i(1,3),
	VoxelTypes.HILLS3: Vector2i(2,3),
	VoxelTypes.HILLS4: Vector2i(3,3),

	VoxelTypes.MOUNTAIN: Vector2i(0,4),
	VoxelTypes.MOUNTAIN2: Vector2i(1,4),
	VoxelTypes.MOUNTAIN3: Vector2i(2,4),
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
	VoxelTypes.DESERT3: Vector2i(1,7),

	VoxelTypes.TUNDRA: Vector2i(0,8),
	VoxelTypes.TUNDRA2: Vector2i(1,8),
	VoxelTypes.TUNDRA3: Vector2i(2,8),

	VoxelTypes.BASIN: Vector2i(0,9),
	VoxelTypes.BASIN2: Vector2i(1,9),
	VoxelTypes.BASIN3: Vector2i(2,9),

	VoxelTypes.RIVER: Vector2i(1,0)
} 
