class_name CrystalTypes
extends RefCounted

enum SpawnKind { ORIGIN, RUIN, ARTIFACT }

enum AbsorbCategory { WATER, PLANT, ANIMAL, STONE, DIRT, DEFAULT }

const WATER_TILES := [
	VoxelTypes.RIVER,
	VoxelTypes.WATER,
	VoxelTypes.OCEAN,
	VoxelTypes.OCEAN2,
	VoxelTypes.OCEAN3,
]

const PLANT_TILES := [
	VoxelTypes.GRASSLAND, VoxelTypes.GRASSLAND2, VoxelTypes.GRASSLAND3,
	VoxelTypes.GRASSLAND4, VoxelTypes.GRASSLAND5,
	VoxelTypes.HILLS, VoxelTypes.HILLS2, VoxelTypes.HILLS3, VoxelTypes.HILLS4,
	VoxelTypes.BEACH, VoxelTypes.BEACH2, VoxelTypes.BEACH3,
	VoxelTypes.TUNDRA, VoxelTypes.TUNDRA2, VoxelTypes.TUNDRA3,
]

const STONE_TILES := [
	VoxelTypes.STONE, VoxelTypes.STONE2, VoxelTypes.CAVE_STONE,
	VoxelTypes.MOUNTAIN, VoxelTypes.MOUNTAIN2, VoxelTypes.MOUNTAIN3,
	VoxelTypes.MOUNTAIN4, VoxelTypes.MOUNTAIN5, VoxelTypes.MOUNTAIN6, VoxelTypes.MOUNTAIN7,
	VoxelTypes.SNOW, VoxelTypes.SNOW2, VoxelTypes.SNOW3,
]

const ABSORB_SECONDS := {
	AbsorbCategory.WATER: 0.35,
	AbsorbCategory.PLANT: 2.4,
	AbsorbCategory.ANIMAL: 1.2,
	AbsorbCategory.STONE: 3.2,
	AbsorbCategory.DIRT: 1.0,
	AbsorbCategory.DEFAULT: 1.5,
}

const POWER_GAIN := {
	AbsorbCategory.WATER: 0.0,
	AbsorbCategory.PLANT: 1.5,
	AbsorbCategory.ANIMAL: 3.0,
	AbsorbCategory.STONE: 0.4,
	AbsorbCategory.DIRT: 0.6,
	AbsorbCategory.DEFAULT: 0.8,
}

const STRENGTH_TIER_THRESHOLDS := [0.0, 12.0, 36.0, 80.0, 160.0, 320.0]

const NEIGHBOR_DIRS := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]


static func get_absorb_category(tile_id: int) -> AbsorbCategory:
	if tile_id in WATER_TILES:
		return AbsorbCategory.WATER
	if tile_id in PLANT_TILES:
		return AbsorbCategory.PLANT
	if tile_id in STONE_TILES:
		return AbsorbCategory.STONE
	if tile_id == VoxelTypes.DIRT or tile_id == VoxelTypes.DIRT2:
		return AbsorbCategory.DIRT
	return AbsorbCategory.DEFAULT


static func is_water_tile(tile_id: int) -> bool:
	return tile_id in WATER_TILES


static func can_absorb(tile_id: int) -> bool:
	return not is_water_tile(tile_id)


static func tier_from_power(power: float) -> int:
	var tier := 0
	for threshold in STRENGTH_TIER_THRESHOLDS:
		if power >= threshold:
			tier += 1
	return maxi(tier - 1, 0)