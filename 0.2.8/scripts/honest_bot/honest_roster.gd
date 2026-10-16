extends RefCounted

const SCAN_COLUMNS := 32.0
const POOL_STAND := 6.0
const ENGAGE_COLUMNS := 2.35
const KITE_COLUMNS := 1.2
const LEVEL_GOAL := 3
const HUNT_LIMIT := 165.0
const QUIET_LIMIT := 42.0
const APPROACH_LIMIT := 40.0

const ORDER: PackedStringArray = [
	"crystal_mite",
	"farm_bomber",
	"crystal_stag",
	"thornling",
	"corrupted_beast",
	"crystal_wisp",
	"shard_guard",
	"spawn_elite",
]


static func pick(rows: Array, from_xz: Vector2, radius: float, killed: Dictionary, grind_mite: bool) -> Dictionary:
	var fresh: Dictionary = {}
	var fresh_d := INF
	var mite: Dictionary = {}
	var mite_d := INF
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var kind := str(row.get("kind", ""))
		if kind == "" or kind == "origin_warden":
			continue
		var xz: Vector2 = row.get("xz", Vector2.ZERO)
		var dist := from_xz.distance_to(xz)
		if dist > radius:
			continue
		if kind == "crystal_mite" and not killed.has(kind) and dist < mite_d:
			mite = row
			mite_d = dist
		elif not killed.has(kind):
			if dist < fresh_d:
				fresh = row
				fresh_d = dist
		elif grind_mite and kind == "crystal_mite" and dist < mite_d:
			mite = row
			mite_d = dist
	if not killed.has("crystal_mite") and not mite.is_empty():
		return mite
	if not fresh.is_empty():
		return fresh
	return mite


static func kind_status(kind: String, killed: Dictionary, seen: Dictionary) -> String:
	if int(killed.get(kind, 0)) > 0:
		return "pass"
	if kind == "crystal_mite" and bool(seen.get(kind, false)):
		return "fail"
	return "absent"


static func keep_hunting(level: int, goal: int, quiet: float, quiet_limit: float, age: float, age_limit: float, pending_new: bool, endangered: bool) -> bool:
	if age >= age_limit:
		return false
	if endangered and not pending_new:
		return false
	if pending_new:
		return true
	if level >= goal:
		return false
	if quiet >= quiet_limit and level >= 2:
		return false
	return true


static func pool_goal(from_xz: Vector2, origin: Vector2, stand: float) -> Vector2:
	var delta := from_xz - origin
	if delta.length() <= stand:
		return from_xz
	return origin + delta.normalized() * stand
