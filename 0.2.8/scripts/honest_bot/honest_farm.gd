extends RefCounted

const XP_READY := 191
const DEMO_LEVEL := 6
const HEART_GAP := 3.6
const CHIP_DEPTH_MIN := 0.05
const CHIP_DEPTH_MAX := 2.3
const SITE_CAP := 4
const SITE_REACH := 1500.0
const FARM_SITE_REACH := 96.0
const SEEK_COLUMNS := 220.0
const HOME_COLUMNS := 36.0
const FARM_LIMIT := 900.0
const CHIP_LIMIT := 480.0
const WILD: PackedStringArray = ["rabbit", "deer", "boar", "bird"]


static func earned(level: int, remainder: int) -> int:
	var total := maxi(remainder, 0)
	var lv := 1
	var prog = load("res://systems/progression_service.gd")
	while lv < maxi(level, 1):
		total += int(prog.xp_to_advance(lv))
		lv += 1
	return total


static func ready(level: int, remainder: int) -> bool:
	return level >= 3 and earned(level, remainder) >= XP_READY


static func demo_ready(level: int) -> bool:
	return level >= DEMO_LEVEL


static func farm_clock_open(level: int, dist: float) -> bool:
	return not demo_ready(level) and dist <= HOME_COLUMNS


static func chip_cell_ok(cell: Vector2, origin: Vector2, depth: float) -> bool:
	if cell.distance_to(origin) < HEART_GAP:
		return false
	return depth >= CHIP_DEPTH_MIN and depth <= CHIP_DEPTH_MAX


static func site_key(at: Vector2) -> String:
	return "%d:%d" % [int(round(at.x)), int(round(at.y))]


static func next_site(from_xz: Vector2, sites: Array, done: Dictionary, visits: int, reach: float = SITE_REACH) -> Dictionary:
	if visits >= SITE_CAP:
		return {}
	var cap := reach if reach > 0.0 else SITE_REACH
	var best: Dictionary = {}
	var best_d := INF
	for row in sites:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var at: Vector2 = row.get("xz", Vector2.ZERO)
		var key := site_key(at)
		if done.has(key):
			continue
		var dist := from_xz.distance_to(at)
		if dist > cap or dist >= best_d:
			continue
		best_d = dist
		best = {"key": key, "xz": at, "distance": dist}
	return best


static func prefer_kind(kind: String, killed: Dictionary) -> int:
	if kind == "" or kind == "origin_warden" or kind == "spawn_elite" or kind == "town_militia" or kind == "town_villager":
		return -1
	if kind == "crystal_mite":
		return 1 if not killed.has(kind) else 0
	if kind in WILD:
		return 2 if not killed.has(kind) else 0
	if not killed.has(kind):
		return 3
	return 0


static func pick_seek(rows: Array, from_xz: Vector2, killed: Dictionary, radius: float, skipped: Dictionary, fresh_crystal: bool) -> Dictionary:
	var best: Dictionary = {}
	var best_rank := -1
	var best_d := INF
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var kind := str(row.get("kind", ""))
		var rank := prefer_kind(kind, killed)
		if rank < 0:
			continue
		if fresh_crystal and (kind in WILD or rank < 3):
			continue
		var iid := str(row.get("id", ""))
		if skipped.has(iid):
			continue
		var at: Vector2 = row.get("xz", from_xz)
		var dist := from_xz.distance_to(at)
		if dist > radius:
			continue
		if rank > best_rank or (rank == best_rank and dist < best_d):
			best_rank = rank
			best_d = dist
			best = row
	return best
