extends RefCounted

const CAP_COLUMNS := 48.0
const TREASURE_RADIUS := 10.0
const LANDMARK_STAND := 12.0

const POI_KINDS: Array[String] = [
	"camp", "abandoned_dig", "crystal_grove", "shrine",
]
const LANDMARK_KINDS: Array[String] = [
	"rock_spire", "ruined_tower", "crystal_glow",
]


static func poi_choice(from_xz: Vector2, cells: Dictionary) -> Dictionary:
	return _choice(from_xz, cells, "poi")


static func treasure_choice(from_xz: Vector2, cells: Dictionary) -> Dictionary:
	return _choice(from_xz, cells, "treasure")


static func landmark_choice(from_xz: Vector2, cells: Dictionary) -> Dictionary:
	return _choice(from_xz, cells, "landmark")


static func stand_off(from_xz: Vector2, target: Vector2, gap: float) -> Vector2:
	var offset := from_xz - target
	var dist := offset.length()
	if dist <= gap:
		return from_xz
	if dist < 0.001:
		return target + Vector2(gap, 0.0)
	return target + offset / dist * gap


static func approach(from_xz: Vector2, target: Vector2, gap: float) -> Dictionary:
	if gap > 0.0 and from_xz.distance_to(target) <= gap:
		return {"walk": false, "goal": from_xz}
	if gap <= 0.0:
		return {"walk": true, "goal": target}
	return {"walk": true, "goal": stand_off(from_xz, target, gap)}


static func _choice(from_xz: Vector2, cells: Dictionary, kind: String) -> Dictionary:
	var best := Vector2.ZERO
	var best_kind := ""
	var best_d := INF
	var found := false
	for key in cells.keys():
		var feat: Variant = cells[key]
		if typeof(feat) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = feat
		var tag := _tag(row)
		if tag != kind:
			continue
		var center := _center(row, key)
		var dist := from_xz.distance_to(center)
		if dist < best_d:
			best_d = dist
			best = center
			best_kind = str(row.get("poi_kind", ""))
			found = true
	if not found or best_d > CAP_COLUMNS:
		return {
			"status": "too-far",
			"distance": best_d if found else -1.0,
			"xz": best,
			"poi_kind": best_kind,
		}
	return {
		"status": "walk",
		"distance": best_d,
		"xz": best,
		"poi_kind": best_kind,
	}


static func _tag(row: Dictionary) -> String:
	var poi_kind := str(row.get("poi_kind", ""))
	if bool(row.get("landmark", false)) and poi_kind in LANDMARK_KINDS:
		return "landmark"
	if bool(row.get("treasure_site", false)):
		return "treasure"
	if poi_kind in POI_KINDS:
		return "poi"
	return ""


static func _center(row: Dictionary, key: Variant) -> Vector2:
	return _as_xz(row.get("center", key))


static func _as_xz(value: Variant) -> Vector2:
	if value is Vector2i:
		return Vector2(value)
	if value is Vector2:
		return value
	if value is Vector3:
		return Vector2(value.x, value.z)
	return Vector2.ZERO
