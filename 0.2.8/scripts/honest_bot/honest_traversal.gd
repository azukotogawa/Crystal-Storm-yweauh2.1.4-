extends RefCounted

const CAP_COLUMNS := 48.0
const TREASURE_RADIUS := 10.0
const LANDMARK_STAND := 12.0
# Near density ring is about 1100 columns from the crystal corner. 1500 still skips the far side.
const LEG_CAP := 1500.0
const LEG_PACE := 8.0
const CHAIN_KEEP := 8

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


static func glow_choice(from_xz: Vector2, cells: Dictionary) -> Dictionary:
	var best := Vector2.ZERO
	var best_d := INF
	var found := false
	for key in cells.keys():
		var feat: Variant = cells[key]
		if typeof(feat) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = feat
		if str(row.get("poi_kind", "")) != "crystal_glow":
			continue
		var center := _center(row, key)
		var dist := from_xz.distance_to(center)
		if dist < best_d:
			best_d = dist
			best = center
			found = true
	if not found or best_d > LEG_CAP:
		return {
			"status": "too-far",
			"distance": best_d if found else -1.0,
			"xz": best,
			"poi_kind": "crystal_glow",
		}
	return {
		"status": "walk",
		"distance": best_d,
		"xz": best,
		"poi_kind": "crystal_glow",
	}


static func treasure_sites(cells: Dictionary) -> Array:
	return _buckets(cells)["treasure"]


static func exploration_chain(from_xz: Vector2, cells: Dictionary) -> Array:
	var buckets := _buckets(cells)
	var poi_list := _candidates(from_xz, buckets["poi"], "poi")
	var treasure_list := _candidates(from_xz, buckets["treasure"], "treasure")
	var landmark_list := _candidates(from_xz, buckets["landmark"], "landmark")
	var best_walks := -1
	var best_length := INF
	var best: Array = []
	for poi_v in poi_list:
		for treasure_v in treasure_list:
			for landmark_v in landmark_list:
				var scored := _score_chain(from_xz, [poi_v, treasure_v, landmark_v])
				var walks := int(scored.get("walks", 0))
				var length := float(scored.get("length", INF))
				if walks > best_walks or (walks == best_walks and length < best_length):
					best_walks = walks
					best_length = length
					best = scored.get("legs", [])
	return best


static func leg_limit(distance: float) -> float:
	return clampf(distance / LEG_PACE + 12.0, 20.0, 180.0)


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


static func _candidates(from_xz: Vector2, spots: Array, tag: String) -> Array:
	if spots.is_empty():
		return [_missing(tag)]
	var ranked: Array = spots.duplicate()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left: Vector2 = a.get("xz", Vector2.ZERO)
		var right: Vector2 = b.get("xz", Vector2.ZERO)
		return from_xz.distance_squared_to(left) < from_xz.distance_squared_to(right)
	)
	if ranked.size() > CHAIN_KEEP:
		ranked = ranked.slice(0, CHAIN_KEEP)
	return ranked


static func _score_chain(from_xz: Vector2, picks: Array) -> Dictionary:
	var cursor := from_xz
	var length := 0.0
	var walks := 0
	var legs: Array = []
	for pick_v in picks:
		var pick: Dictionary = pick_v
		var tag := str(pick.get("tag", ""))
		var kind := str(pick.get("poi_kind", ""))
		if bool(pick.get("missing", false)):
			legs.append(_far(tag, -1.0, Vector2.ZERO, kind))
			continue
		var center: Vector2 = pick.get("xz", Vector2.ZERO)
		var dist := cursor.distance_to(center)
		if dist > LEG_CAP:
			legs.append(_far(tag, dist, center, kind))
			continue
		legs.append({
			"status": "walk",
			"distance": dist,
			"xz": center,
			"poi_kind": kind,
			"tag": tag,
		})
		length += dist
		walks += 1
		cursor = center
	return {"walks": walks, "length": length, "legs": legs}


static func _buckets(cells: Dictionary) -> Dictionary:
	var out := {"poi": [], "treasure": [], "landmark": []}
	var seen := {}
	for key in cells.keys():
		var feat: Variant = cells[key]
		if typeof(feat) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = feat
		var tag := _tag(row)
		if tag == "":
			continue
		var center := _center(row, key)
		var stamp := "%s:%d:%d" % [tag, int(round(center.x)), int(round(center.y))]
		if seen.has(stamp):
			continue
		seen[stamp] = true
		var list: Array = out[tag]
		list.append({
			"tag": tag,
			"xz": center,
			"poi_kind": str(row.get("poi_kind", "")),
			"missing": false,
		})
		out[tag] = list
	return out


static func _missing(tag: String) -> Dictionary:
	return {"tag": tag, "xz": Vector2.ZERO, "poi_kind": "", "missing": true}


static func _far(tag: String, distance: float, center: Vector2, kind: String) -> Dictionary:
	return {
		"status": "too-far",
		"distance": distance,
		"xz": center,
		"poi_kind": kind,
		"tag": tag,
	}


static func _as_xz(value: Variant) -> Vector2:
	if value is Vector2i:
		return Vector2(value)
	if value is Vector2:
		return value
	if value is Vector3:
		return Vector2(value.x, value.z)
	return Vector2.ZERO
