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

const DIAG_DIRS := [
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]


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
		}

	var corner: bool = ox > 0.001 and oz > 0.001
	var side: String = "corner" if corner else ("ocean" if ox >= oz else "mountain")
	var dist: float = sqrt(ox * ox + oz * oz) if corner else maxf(ox, oz)
	var transition: float = clampf(dist / TRANSITION_WIDTH, 0.0, 1.0)
	var deep: float = clampf((dist - TRANSITION_WIDTH) / (DEEP_BORDER - TRANSITION_WIDTH), 0.0, 1.0)

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


## Deep border bands are impassable (ocean sink / unclimbable mountain wall).
static func blocks_player_movement(wx: float, wz: float) -> bool:
	var info: Dictionary = zone_info(wx, wz)
	if info.zone == "playable":
		return false
	var deep: float = float(info.get("deep", 0.0))
	var side: String = str(info.get("side", ""))
	match side:
		"ocean":
			return deep > 0.28
		"mountain":
			return deep > 0.18
		"corner":
			return deep > 0.32
		_:
			return deep > 0.45


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

	var ocean_target: float = lerpf(SEA_LEVEL - 4.0, OCEAN_FLOOR - deep * 14.0, maxf(t, deep * 0.5))
	var mountain_target: float = lerpf(
		SEA_LEVEL + 18.0,
		lerpf(MOUNTAIN_FLOOR, MOUNTAIN_PEAK, deep),
		t
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
		return lerpf(0.35, 1.0, float(info.transition))
	if info.side == "corner":
		return lerpf(0.0, 0.85, float(info.mountain_weight) * float(info.transition))
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
	# Diagonal corner — classify by dominant border
	if float(info.ocean_weight) >= float(info.mountain_weight):
		return "ocean"
	return "border_mountain"


static func is_near_playable_edge(wx: float, wz: float, margin: float = 6.0) -> bool:
	var ox: float = maxf(absf(wx) - float(PLAYABLE_HALF_X), 0.0)
	var oz: float = maxf(absf(wz) - float(PLAYABLE_HALF_Z), 0.0)
	if ox <= 0.001 and oz <= 0.001:
		return false
	return minf(
		ox if ox > 0.001 else INF,
		oz if oz > 0.001 else INF
	) <= margin or (ox > 0.001 and oz > 0.001 and float(sqrt(ox * ox + oz * oz)) <= margin + 4.0)


static func should_force_ramp(world_x: int, world_z: int) -> bool:
	if not is_near_playable_edge(float(world_x), float(world_z), 8.0):
		return false
	return is_border_tile_zone(float(world_x), float(world_z)) or is_playable(float(world_x), float(world_z))


static func prefer_diagonal_ramp(wx: float, wz: float) -> bool:
	var info: Dictionary = zone_info(wx, wz)
	return info.side == "corner" and float(info.transition) < 0.85