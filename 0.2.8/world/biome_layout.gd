class_name BiomeLayout
extends RefCounted


const INTERIOR_BIOMES: Array[String] = [
	"plains", "steppe", "forest", "marsh", "highland",
]

static var regions: Array = []
static var _ready: bool = false


static func reset() -> void:
	regions.clear()
	_ready = false


static func ensure_generated(seed: int, half_extent: float, warp_strength: float = 0.22) -> void:
	if _ready:
		return
	_generate(seed, half_extent, warp_strength)
	_ready = true


static func _generate(seed: int, half_extent: float, warp_strength: float) -> void:
	regions.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 31007

	var names: Array[String] = []
	for b in INTERIOR_BIOMES:
		names.append(b)
	_shuffle_names(names, rng)

	var extent := half_extent * 0.82
	var min_sep := extent * 0.38
	var centers: Array[Vector2] = []

	for _attempt in 200:
		if centers.size() >= 5:
			break
		var c := Vector2(
			rng.randf_range(-extent, extent),
			rng.randf_range(-extent, extent)
		)
		var ok := true
		for existing in centers:
			if c.distance_to(existing) < min_sep:
				ok = false
				break
		if ok:
			centers.append(c)

	while centers.size() < 5:
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(extent * 0.25, extent * 0.7)
		centers.append(Vector2(cos(angle) * dist, sin(angle) * dist))

	for i in 5:
		regions.append({
			"center": centers[i],
			"biome": names[i],
			"radius_hint": extent * rng.randf_range(0.32, 0.48),
			"warp": warp_strength * rng.randf_range(0.85, 1.15),
		})


static func biome_name_at(wx: float, wz: float, seed: int, warp_strength: float, half_extent: float) -> String:
	ensure_generated(seed, half_extent, warp_strength)
	if regions.is_empty():
		return "plains"

	var wobble_x := _domain_warp(wx, wz, seed, 0.031) * warp_strength * half_extent * 0.08
	var wobble_z := _domain_warp(wz, wx, seed, 0.037) * warp_strength * half_extent * 0.08
	var p := Vector2(wx + wobble_x, wz + wobble_z)

	var best_idx := 0
	var best_dist := INF
	for i in regions.size():
		var center: Vector2 = regions[i].center
		var d := p.distance_squared_to(center)
		if d < best_dist:
			best_dist = d
			best_idx = i
	return str(regions[best_idx].biome)


## Biome name when every column in [min_x, max_x] x [min_z, max_z] maps to the
## same region for any wobble, else "". Same answer biome_name_at would give.
static func box_name(min_x: float, min_z: float, max_x: float, max_z: float, seed: int, warp_strength: float, half_extent: float) -> String:
	ensure_generated(seed, half_extent, warp_strength)
	if regions.is_empty():
		return "plains"
	var wob := absf(warp_strength * half_extent * 0.08) + 0.01
	var lo_x := min_x - wob
	var hi_x := max_x + wob
	var lo_z := min_z - wob
	var hi_z := max_z + wob
	var best := -1
	var best_far := INF
	var dmins: Array[float] = []
	for i in regions.size():
		var c: Vector2 = regions[i].center
		var nx := maxf(maxf(lo_x - c.x, 0.0), c.x - hi_x)
		var nz := maxf(maxf(lo_z - c.y, 0.0), c.y - hi_z)
		dmins.append(nx * nx + nz * nz)
		var fx := maxf(absf(c.x - lo_x), absf(c.x - hi_x))
		var fz := maxf(absf(c.y - lo_z), absf(c.y - hi_z))
		var far := fx * fx + fz * fz
		if far < best_far:
			best_far = far
			best = i
	for j in regions.size():
		if j == best:
			continue
		if dmins[j] <= best_far * 1.0001 + 1.0:
			return ""
	return str(regions[best].biome)


static func get_region_summary() -> Array:
	var out: Array = []
	for r in regions:
		out.append({
			"biome": r.biome,
			"center": [r.center.x, r.center.y],
		})
	return out


static func _domain_warp(x: float, z: float, seed: int, freq: float) -> float:
	return sin((x + float(seed) * 0.13) * freq) * cos((z - float(seed) * 0.09) * freq)


static func _shuffle_names(names: Array[String], rng: RandomNumberGenerator) -> void:
	for i in range(names.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := names[i]
		names[i] = names[j]
		names[j] = tmp