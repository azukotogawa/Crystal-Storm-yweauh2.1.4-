class_name RouteDressing
extends RefCounted

const _Pois = preload("res://world/poi_scatter.gd")
const _Border = preload("res://helpers/world_border.gd")
const _Default = preload("res://config/default_route_variety.tres")
const _Types = preload("res://helpers/voxel_types.gd")

static var _lock: Mutex = Mutex.new()
static var _cache_seed: int = -2147483648
static var _segments: Array = []
static var _bounds_ready: bool = false
static var _min_x: float = 0.0
static var _max_x: float = 0.0
static var _min_z: float = 0.0
static var _max_z: float = 0.0
static var _override = null


static func set_config(cfg) -> void:
	_override = cfg
	_cache_seed = -2147483648


static func config():
	if _override != null:
		return _override
	return _Default


static func relief_world(seed_value: int, wx: float, wz: float, layer: float) -> float:
	var cfg = config()
	if not cfg.enabled or layer <= 0.001:
		return 0.0
	_ensure(seed_value)
	if _segments.is_empty():
		return 0.0
	if _bounds_ready and (wx < _min_x or wx > _max_x or wz < _min_z or wz > _max_z):
		return 0.0
	var dist := _nearest(wx, wz)
	if dist >= cfg.band_radius:
		return 0.0
	return _hill(seed_value, wx, wz, cfg) * _fade(dist, cfg) * _spawn_gate(seed_value, wx, wz, cfg) * cfg.hill_layers * layer


## True when every point of the square [min_x, min_x + size] x [min_z, min_z + size]
## is farther from all route segments than relief and path tiles reach, so
## relief_world returns 0.0 and tile_for returns natural there.
static func box_clear(seed_value: int, min_x: float, min_z: float, size: float) -> bool:
	var cfg = config()
	if not cfg.enabled:
		return true
	_ensure(seed_value)
	if _segments.is_empty():
		return true
	var half := size * 0.5
	var reach: float = maxf(float(cfg.band_radius), maxf(float(cfg.path_radius), float(cfg.shoulder_radius)))
	var d := _nearest(min_x + half, min_z + half)
	return d - half * 1.4142136 - 0.5 > reach


static func tile_for(seed_value: int, wx: float, wz: float, natural: int) -> int:
	var cfg = config()
	if not cfg.enabled:
		return natural
	if _wet(natural):
		return natural
	_ensure(seed_value)
	if _segments.is_empty():
		return natural
	var x := floorf(wx)
	var z := floorf(wz)
	if _bounds_ready and (x < _min_x or x > _max_x or z < _min_z or z > _max_z):
		return natural
	if _inside_spawn(seed_value, x + 0.5, z + 0.5, cfg):
		return natural
	var dist := _nearest(x + 0.5, z + 0.5)
	if dist <= cfg.path_radius:
		return cfg.path_tile
	if dist <= cfg.shoulder_radius and cfg.shoulder_tiles.size() > 0:
		var pick: int = _mix(seed_value, int(x), int(z), 19) % int(cfg.shoulder_tiles.size())
		return int(cfg.shoulder_tiles[pick])
	return natural


static func props_for_chunk(seed_value: int, cx: int, cz: int) -> Array[Dictionary]:
	var cfg = config()
	var out: Array[Dictionary] = []
	if not cfg.enabled or cfg.props_per_chunk <= 0:
		return out
	_ensure(seed_value)
	if _segments.is_empty():
		return out
	var origin := Vector2(float(cx * 16), float(cz * 16))
	var reach: float = float(cfg.prop_far) + 1.0
	var box_min := origin - Vector2(reach, reach)
	var box_max := origin + Vector2(16.0 + reach, 16.0 + reach)
	var corner := Vector2(_Border.origin_corner_for_seed(seed_value))
	for index in _segments.size():
		if out.size() >= cfg.props_per_chunk:
			break
		var seg: Dictionary = _segments[index]
		var a: Vector2 = seg["a"]
		var b: Vector2 = seg["b"]
		if _box_misses(a, b, box_min, box_max):
			continue
		var span := a.distance_to(b)
		if span < 1.0:
			continue
		var steps := int(floor(span / maxf(cfg.prop_spacing, 1.0)))
		for step in steps:
			if out.size() >= cfg.props_per_chunk:
				break
			var roll := _mix(seed_value, index, step, 23)
			if roll % 3 != 0:
				continue
			var t: float = (float(step) + 0.5) * float(cfg.prop_spacing) / span
			if t <= 0.02 or t >= 0.98:
				continue
			var along := a.lerp(b, t)
			var dir := (b - a) / span
			var side := Vector2(-dir.y, dir.x)
			var sign := -1.0 if roll % 2 == 0 else 1.0
			var offset: float = lerpf(float(cfg.prop_near), float(cfg.prop_far), float(roll % 97) / 96.0)
			var at := along + side * sign * offset
			if at.distance_to(corner) < cfg.spawn_clear:
				continue
			if at.x < origin.x or at.y < origin.y or at.x >= origin.x + 16.0 or at.y >= origin.y + 16.0:
				continue
			var cell := Vector2i(int(floor(at.x)), int(floor(at.y)))
			var kind := "rock"
			if cfg.prop_kinds.size() > 0:
				kind = str(cfg.prop_kinds[roll % cfg.prop_kinds.size()])
			var yaw := 0
			if kind == "log":
				yaw = 90 if roll % 2 == 0 else 0
			out.append({"cell": cell, "kind": kind, "yaw": yaw})
	return out


static func props_along(seed_value: int, origin: Vector2, dir: Vector2, along_n: int, across_n: int) -> Array[Dictionary]:
	var cfg = config()
	var out: Array[Dictionary] = []
	if not cfg.enabled:
		return out
	_ensure(seed_value)
	var side := Vector2(-dir.y, dir.x)
	var wanted := {}
	var chunks := {}
	for along in along_n:
		for across in across_n:
			var at: Vector2 = origin + dir * float(along) + side * float(across - across_n / 2)
			var cell := Vector2i(int(round(at.x)), int(round(at.y)))
			wanted[cell] = true
			var chunk := Vector2i(int(floor(float(cell.x) / 16.0)), int(floor(float(cell.y) / 16.0)))
			chunks[chunk] = true
	for chunk_v in chunks.keys():
		var chunk: Vector2i = chunk_v
		for spot_v in props_for_chunk(seed_value, chunk.x, chunk.y):
			var spot: Dictionary = spot_v
			var prop_cell: Vector2i = spot.get("cell", Vector2i.ZERO)
			if not wanted.has(prop_cell):
				continue
			wanted.erase(prop_cell)
			out.append(spot)
	return out


static func long_walk(seed_value: int) -> Dictionary:
	_ensure(seed_value)
	if _segments.is_empty():
		return {}
	return _segments[0]


static func segment_count(seed_value: int) -> int:
	_ensure(seed_value)
	return _segments.size()


static func _ensure(seed_value: int) -> void:
	if _cache_seed == seed_value:
		return
	_lock.lock()
	if _cache_seed != seed_value:
		_rebuild(seed_value)
		_cache_seed = seed_value
	_lock.unlock()


static func _rebuild(seed_value: int) -> void:
	_segments = []
	_bounds_ready = false
	var cfg = config()
	if not cfg.enabled:
		return
	var centers: Array[Vector2] = []
	for spot_v in _Pois.scatter(seed_value):
		var spot: Dictionary = spot_v
		var center: Vector2i = spot.get("center", Vector2i.ZERO)
		centers.append(Vector2(center))
	if centers.is_empty():
		return
	var corner := Vector2(_Border.origin_corner_for_seed(seed_value))
	var goal := centers[0]
	var best_d := INF
	for center in centers:
		var dist := corner.distance_to(center)
		if dist < best_d and dist <= cfg.long_walk_cap and dist > 8.0:
			best_d = dist
			goal = center
	if best_d < INF:
		_segments.append({"a": corner, "b": goal})
	var pending: Array = []
	var seen := {}
	for i in centers.size():
		var nearest := -1
		var nearest_d := INF
		for j in centers.size():
			if i == j:
				continue
			var dist := centers[i].distance_to(centers[j])
			if dist < nearest_d:
				nearest_d = dist
				nearest = j
		if nearest < 0 or nearest_d > cfg.link_columns:
			continue
		var lo := mini(i, nearest)
		var hi := maxi(i, nearest)
		var key := "%d:%d" % [lo, hi]
		if seen.has(key):
			continue
		seen[key] = true
		pending.append({"d": nearest_d, "a": centers[lo], "b": centers[hi]})
	pending.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return float(left["d"]) < float(right["d"])
	)
	var kept := 0
	for row_v in pending:
		if kept >= cfg.max_links:
			break
		var row: Dictionary = row_v
		_segments.append({"a": row["a"], "b": row["b"]})
		kept += 1
	_fit_bounds(cfg.band_radius)


static func _fit_bounds(pad: float) -> void:
	if _segments.is_empty():
		return
	var first: Dictionary = _segments[0]
	var a0: Vector2 = first["a"]
	_min_x = a0.x
	_max_x = a0.x
	_min_z = a0.y
	_max_z = a0.y
	for seg_v in _segments:
		var seg: Dictionary = seg_v
		var a: Vector2 = seg["a"]
		var b: Vector2 = seg["b"]
		_min_x = minf(_min_x, minf(a.x, b.x))
		_max_x = maxf(_max_x, maxf(a.x, b.x))
		_min_z = minf(_min_z, minf(a.y, b.y))
		_max_z = maxf(_max_z, maxf(a.y, b.y))
	_min_x -= pad
	_max_x += pad
	_min_z -= pad
	_max_z += pad
	_bounds_ready = true


static func _nearest(wx: float, wz: float) -> float:
	var best := INF
	var p := Vector2(wx, wz)
	for seg_v in _segments:
		var seg: Dictionary = seg_v
		var a: Vector2 = seg["a"]
		var b: Vector2 = seg["b"]
		var ab := b - a
		var len2 := ab.length_squared()
		var t := 0.0
		if len2 > 0.01:
			t = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
		var dist := p.distance_to(a + ab * t)
		if dist < best:
			best = dist
	return best


static func _hill(seed_value: int, wx: float, wz: float, cfg) -> float:
	var wave: float = maxf(float(cfg.hill_wavelength), 4.0)
	var gx := wx / wave
	var gz := wz / wave
	var x0 := int(floor(gx))
	var z0 := int(floor(gz))
	var tx := gx - float(x0)
	var tz := gz - float(z0)
	tx = tx * tx * (3.0 - 2.0 * tx)
	tz = tz * tz * (3.0 - 2.0 * tz)
	var h00 := _unit(seed_value, x0, z0)
	var h10 := _unit(seed_value, x0 + 1, z0)
	var h01 := _unit(seed_value, x0, z0 + 1)
	var h11 := _unit(seed_value, x0 + 1, z0 + 1)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tz), tz)


static func _inside_spawn(seed_value: int, wx: float, wz: float, cfg) -> bool:
	if float(cfg.spawn_clear) <= 0.0:
		return false
	var corner := Vector2(_Border.origin_corner_for_seed(seed_value))
	return corner.distance_to(Vector2(wx, wz)) < float(cfg.spawn_clear)


static func _spawn_gate(seed_value: int, wx: float, wz: float, cfg) -> float:
	var clear := float(cfg.spawn_clear)
	if clear <= 0.0:
		return 1.0
	var corner := Vector2(_Border.origin_corner_for_seed(seed_value))
	var dist := corner.distance_to(Vector2(wx, wz))
	if dist <= clear:
		return 0.0
	var span := maxf(float(cfg.fade_columns), 0.001)
	if dist >= clear + span:
		return 1.0
	var u := (dist - clear) / span
	var s := u * u * (3.0 - 2.0 * u)
	return s


static func _box_misses(a: Vector2, b: Vector2, box_min: Vector2, box_max: Vector2) -> bool:
	if maxf(a.x, b.x) < box_min.x or minf(a.x, b.x) > box_max.x:
		return true
	if maxf(a.y, b.y) < box_min.y or minf(a.y, b.y) > box_max.y:
		return true
	return false


static func _fade(dist: float, cfg) -> float:
	var inner: float = maxf(float(cfg.band_radius) - float(cfg.fade_columns), 0.0)
	if dist <= inner:
		return 1.0
	var span: float = maxf(float(cfg.band_radius) - inner, 0.001)
	var u := clampf((dist - inner) / span, 0.0, 1.0)
	var s := u * u * (3.0 - 2.0 * u)
	return 1.0 - s


static func _unit(seed_value: int, ix: int, iz: int) -> float:
	return float(_mix(seed_value, ix, iz, 41) % 10001) / 10000.0 * 2.0 - 1.0


static func _wet(tile: int) -> bool:
	return tile == _Types.OCEAN or tile == _Types.OCEAN2 or tile == _Types.OCEAN3 \
		or tile == _Types.RIVER or tile == _Types.WATER \
		or tile == _Types.CRYSTAL or tile == _Types.CRYSTAL_VEIN \
		or tile == _Types.CRYSTAL_SHARD_GROUND or tile == _Types.CRYSTAL_SCAR


static func _mix(seed_value: int, a: int, b: int, salt: int) -> int:
	var n := int(seed_value) * 2246822519 + int(a) * 3266489917 + int(b) * 668265263 + int(salt) * 374761393
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	if n < 0:
		n = -n
	if n < 0:
		n = 0
	return n
