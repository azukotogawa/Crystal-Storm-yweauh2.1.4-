class_name EmptyRoomPrefab
extends RefCounted

## One empty dungeon room prefab (Done slice for plan #9 option A).
## Footprint is a hollow stone-walled pit dug from the surface.

const ID := "empty_room"
const HALF_W := 3
const HALF_D := 3
const DIG_LAYERS := 3
const WALL_TILE := 40 ## VoxelTypes.STONE2
const FLOOR_TILE := 43 ## VoxelTypes.CAVE_STONE


static func size_cells() -> Vector2i:
	return Vector2i(HALF_W * 2 + 1, HALF_D * 2 + 1)


static func footprint_cells(center: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dz in range(-HALF_D, HALF_D + 1):
		for dx in range(-HALF_W, HALF_W + 1):
			out.append(center + Vector2i(dx, dz))
	return out


static func wall_cells(center: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dz in range(-HALF_D, HALF_D + 1):
		for dx in range(-HALF_W, HALF_W + 1):
			if absi(dx) == HALF_W or absi(dz) == HALF_D:
				out.append(center + Vector2i(dx, dz))
	return out


static func interior_cells(center: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dz in range(-(HALF_D - 1), HALF_D):
		for dx in range(-(HALF_W - 1), HALF_W):
			out.append(center + Vector2i(dx, dz))
	return out


static func describe() -> Dictionary:
	return {
		"id": ID,
		"half_w": HALF_W,
		"half_d": HALF_D,
		"dig_layers": DIG_LAYERS,
		"wall_tile": WALL_TILE,
		"floor_tile": FLOOR_TILE,
		"size": size_cells(),
	}
