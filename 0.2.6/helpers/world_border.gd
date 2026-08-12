class_name WorldBorder
extends RefCounted

# Rectangular playable map centered on origin.
# -X / +X edges = ocean borders
# -Z / +Z edges = mountain borders
# Corners blend both (diagonal transition)
#
# Production world size: PLAYABLE_HALF 1024 cells → 128×128 chunks at CELLS=16
# (see WorldBakeService.full_world_chunk_bounds / production_chunk_side).

const PLAYABLE_HALF_X := 1024
const PLAYABLE_HALF_Z := 1024
const TRANSITION_WIDTH := 240.0
const DEEP_BORDER := 384.0

const SEA_LEVEL := 38.0
const OCEAN_FLOOR := 22.0
const MOUNTAIN_FLOOR := 88.0
const MOUNTAIN_PEAK := 138.0

## Player is stopped once past these transition fractions into the border band.
const PLAYER_OCEAN_TRANSITION_BLOCK := 0.12
const PLAYER_MOUNTAIN_TRANSITION_BLOCK := 0.08
const PLAYER_CORNER_TRANSITION_BLOCK := 0.14

const DIAG_DIRS := [
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

const _VoxelTypes = preload("res://helpers/voxel_types.gd")


static func zone_info(wx: float, wz: float) -> Dictionary:
	var ox: float = maxf(absf(wx) - float(PLAYABLE_HALF_X), 0.0)
	var oz: float = maxf(absf(wz) - float(PLAYABLE_HALF_Z), 0.0)
	var in_playable: bool = ox <= 0.001 and oz <= 0.001

	if in_playable:
		return {
			"zone": "playable",
			"side": "none",
			"ox": 0.0,
			"oz": 0.0,
			"dist": 0.0,
			"transition": 0.0,
			"deep": 0.0,
			"ocean_weight": 0.0,
			"mountain_weight": 0.0,
		}

	var corner: bool = ox > 0.001 and oz > 0.001
	var side: String = "corner" if corner else ("ocean" if ox >= oz else "mountain")
	var dist: float = sqrt(ox * ox + oz * oz) if corner else maxf(ox, oz)
	var transition: float = clampf(dist / TRANSITION_WIDTH, 0.0, 1.0)
	var deep: float = clampf((dist - TRANSITION_WIDTH) / maxf(DEEP_BORDER - TRANSITION_WIDTH, 1.0), 0.0, 1.0)

	return {
		"zone": "border",
		"side": side,
		"ox": ox,
		"oz": oz,
		"dist": dist,
		"transition": transition,
		"deep": deep,
		"ocean_weight": clampf(ox / maxf(ox + oz, 1.0), 0.0, 1.0) if corner else (1.0 if side == "ocean" else 0.0),
		"mountain_weight": clampf(oz / maxf(ox + oz, 1.0), 0.0, 1.0) if corner else (1.0 if side == "mountain" else 0.0),
	}


static func is_playable(wx: float, wz: float) -> bool:
	return zone_info(wx, wz).zone == "playable"


## Crystal fluid / spawn / absorption stay inside the playable rectangle.
static func allows_crystal(wx: float, wz: float) -> bool:
	return is_playable(wx, wz)


## Deep / mid border bands are impassable (ocean sink / unclimbable mountain wall).
static func blocks_player_movement(wx: float, wz: float) -> bool:
	var info: Dictionary = zone_info(wx, wz)
	if info.zone == "playable":
		return false
	var t: float = float(info.get("transition", 0.0))
	var deep: float = float(info.get("deep", 0.0))
	var side: String = str(info.get("side", ""))
	match side:
		"ocean":
			return t >= PLAYER_OCEAN_TRANSITION_BLOCK or deep > 0.05
		"mountain":
			return t >= PLAYER_MOUNTAIN_TRANSITION_BLOCK or deep > 0.02
		"corner":
			return t >= PLAYER_CORNER_TRANSITION_BLOCK or deep > 0.08
		_:
			return t >= 0.2 or deep > 0.1


## Ocean tiles (border seas) always stop the player — no swimming off the map.
static func is_ocean_tile(tile_id: int) -> bool:
	return tile_id in [_VoxelTypes.OCEAN, _VoxelTypes.OCEAN2, _VoxelTypes.OCEAN3]


## Border mountain / ice walls that should block traversal.
static func is_border_mountain_tile(tile_id: int) -> bool:
	return tile_id in [
		_VoxelTypes.MOUNTAIN, _VoxelTypes.MOUNTAIN2, _VoxelTypes.MOUNTAIN3,
		_VoxelTypes.MOUNTAIN4, _VoxelTypes.MOUNTAIN5, _VoxelTypes.MOUNTAIN6, _VoxelTypes.MOUNTAIN7,
		_VoxelTypes.SNOW, _VoxelTypes.SNOW2, _VoxelTypes.SNOW3,
	]


## Combined movement gate used by VoxelFloorProbe (tile + zone).
static func blocks_player_at(wx: float, wz: float, tile_id: int = -1) -> bool:
	if blocks_player_movement(wx, wz):
		return true
	if tile_id < 0:
		return false
	if is_ocean_tile(tile_id):
		return true
	# Mountain walls only force-block in the border band (interior highland stays walkable).
	if is_border_mountain_tile(tile_id) and is_border_tile_zone(wx, wz):
		return true
	return false


static func edge_interior_coords(wx: float, wz: float) -> Vector2:
	var cx: float = clampf(wx, -float(PLAYABLE_HALF_X), float(PLAYABLE_HALF_X))
	var cz: float = clampf(wz, -float(PLAYABLE_HALF_Z), float(PLAYABLE_HALF_Z))
	return Vector2(cx, cz)


static func apply_border_height(wx: float, wz: float, interior_h: float, info: Dictionary) -> float:
	if info.zone == "playable":
		return interior_h

	var edge: Vector2 = edge_interior_coords(wx, wz)
	var edge_h: float = interior_h
	var t: float = float(info.transition)
	var deep: float = float(info.deep)
	var ow: float = float(info.ocean_weight)
	var mw: float = float(info.mountain_weight)

	# Steeper intentional drop into deep ocean / rise into mountain wall.
	var ocean_target: float = lerpf(SEA_LEVEL - 6.0, OCEAN_FLOOR - deep * 18.0, maxf(t, deep * 0.55))
	var mountain_target: float = lerpf(
		SEA_LEVEL + 22.0,
		lerpf(MOUNTAIN_FLOOR, MOUNTAIN_PEAK, deep),
		smoothstep(0.0, 1.0, t)
	)

	var target: float = edge_h
	if info.side == "ocean":
		target = ocean_target
	elif info.side == "mountain":
		target = mountain_target
	elif info.side == "corner":
		var blend: float = smoothstep(0.0, 1.0, clampf(float(info.dist) / TRANSITION_WIDTH, 0.0, 1.0))
		target = lerpf(ocean_target, mountain_target, mw)
		target = lerpf(edge_h, target, blend)

	return lerpf(edge_h, target, smoothstep(0.0, 1.0, t))


static func interior_ridge_scale(wx: float, wz: float) -> float:
	var info: Dictionary = zone_info(wx, wz)
	if info.zone == "playable":
		return 0.0
	if info.side == "mountain":
		return lerpf(0.45, 1.0, float(info.transition))
	if info.side == "corner":
		return lerpf(0.0, 0.9, float(info.mountain_weight) * float(info.transition))
	return 0.0


static func is_border_tile_zone(wx: float, wz: float) -> bool:
	return zone_info(wx, wz).zone == "border"


static func border_biome_name(wx: float, wz: float) -> String:
	var info: Dictionary = zone_info(wx, wz)
	if info.zone == "playable":
		return ""
	if info.side == "ocean":
		return "ocean"
	if info.side == "mountain":
		return "border_mountain"
	if float(info.ocean_weight) >= float(info.mountain_weight):
		return "ocean"
	return "border_mountain"


static func is_near_playable_edge(wx: float, wz: float, margin: float = 6.0) -> bool:
	var ax: float = absf(wx)
	var az: float = absf(wz)
	var dx: float = float(PLAYABLE_HALF_X) - ax
	var dz: float = float(PLAYABLE_HALF_Z) - az
	# Inside, near edge
	if dx >= 0.0 and dz >= 0.0:
		return minf(dx, dz) <= margin
	# Outside, still near rim
	var ox: float = maxf(ax - float(PLAYABLE_HALF_X), 0.0)
	var oz: float = maxf(az - float(PLAYABLE_HALF_Z), 0.0)
	return minf(
		ox if ox > 0.001 else INF,
		oz if oz > 0.001 else INF
	) <= margin or (ox > 0.001 and oz > 0.001 and float(sqrt(ox * ox + oz * oz)) <= margin + 4.0)


## Distance past playable half (0 inside). Useful for map rim styling.
static func outside_distance(wx: float, wz: float) -> float:
	var ox: float = maxf(absf(wx) - float(PLAYABLE_HALF_X), 0.0)
	var oz: float = maxf(absf(wz) - float(PLAYABLE_HALF_Z), 0.0)
	if ox <= 0.001 and oz <= 0.001:
		return 0.0
	if ox > 0.001 and oz > 0.001:
		return sqrt(ox * ox + oz * oz)
	return maxf(ox, oz)


## 0..1 how strongly a map pixel should read as "edge rim" (inside near edge or outside).
static func map_edge_rim_strength(wx: float, wz: float, rim_cells: float = 10.0) -> float:
	var ax: float = absf(wx)
	var az: float = absf(wz)
	var dx: float = float(PLAYABLE_HALF_X) - ax
	var dz: float = float(PLAYABLE_HALF_Z) - az
	if dx < 0.0 or dz < 0.0:
		# Outside: full rim + deepens with distance
		var out_d: float = outside_distance(wx, wz)
		return clampf(0.55 + out_d / maxf(TRANSITION_WIDTH, 1.0), 0.55, 1.0)
	var near: float = minf(dx, dz)
	if near > rim_cells:
		return 0.0
	return 1.0 - clampf(near / maxf(rim_cells, 1.0), 0.0, 1.0)


static func should_force_ramp(world_x: int, world_z: int) -> bool:
	if not is_near_playable_edge(float(world_x), float(world_z), 8.0):
		return false
	return is_border_tile_zone(float(world_x), float(world_z)) or is_playable(float(world_x), float(world_z))


static func prefer_diagonal_ramp(wx: float, wz: float) -> bool:
	var info: Dictionary = zone_info(wx, wz)
	return info.side == "corner" and float(info.transition) < 0.85
