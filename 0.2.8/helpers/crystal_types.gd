class_name CrystalTypes
extends RefCounted

enum SpawnKind { ORIGIN, RUIN, ARTIFACT }

const WATER_TILES := [
	VoxelTypes.RIVER,
	VoxelTypes.WATER,
	VoxelTypes.OCEAN,
	VoxelTypes.OCEAN2,
	VoxelTypes.OCEAN3,
]

const NEIGHBOR_DIRS := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

# Creeper World-style fluid tunables
const MIN_DEPTH := 0.04
const MAX_DEPTH := 12.0
const MIN_FLOW_DIFF := 0.08
const FLOW_RATE := 3.5
const MAX_FLOW_PER_CELL := 2.0
const EMIT_RATE := {
	SpawnKind.ORIGIN: 3.2,
	SpawnKind.RUIN: 1.1,
	SpawnKind.ARTIFACT: 0.7,
}
const INITIAL_SPAWN_DEPTH := 2.5
const STRENGTH_TIER_THRESHOLDS := [0.0, 20.0, 60.0, 140.0, 300.0, 600.0]
const CLIFF_HEIGHT := 1.05


static func is_water_tile(tile_id: int) -> bool:
	return tile_id in WATER_TILES


static func emit_rate_for(kind: SpawnKind) -> float:
	return EMIT_RATE.get(kind, 1.0)


static func tier_from_power(power: float) -> int:
	var tier := 0
	for threshold in STRENGTH_TIER_THRESHOLDS:
		if power >= threshold:
			tier += 1
	return maxi(tier - 1, 0)
