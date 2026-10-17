extends SceneTree

const _Dress = preload("res://world/route_dressing.gd")
const _Cfg = preload("res://config/route_variety_config.gd")
const _World = preload("res://world/InfiniteNoiseWorld.gd")
const _Types = preload("res://helpers/voxel_types.gd")
const _Border = preload("res://helpers/world_border.gd")
const _Settings = preload("res://config/world_settings.gd")

const _SEED := 12349
const _OTHER := 88021

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)
	print("FAIL " + msg)


func _run() -> void:
	_Dress.set_config(null)
	var cfg = _Dress.config()
	if cfg == null or not cfg.enabled:
		_fail("route variety config missing or disabled")
	else:
		_check_walk(cfg)
		_check_other_seed()
		_check_props(cfg)
		_check_wet()
		_check_samples(cfg)
	_Dress.set_config(null)
	if _failed == 0:
		print("All route variety tests OK")
		quit(0)
	else:
		push_error("verify_route_variety: %d failure(s)" % _failed)
		quit(1)


func _check_walk(cfg) -> void:
	var count := _Dress.segment_count(_SEED)
	var walk: Dictionary = _Dress.long_walk(_SEED)
	if count < 2 or walk.is_empty():
		_fail("seed %d segments=%d walk empty=%s" % [_SEED, count, walk.is_empty()])
		return
	if count > int(cfg.max_links) + 1:
		_fail("segment count %d over cap" % count)
		return
	var again: Dictionary = _Dress.long_walk(_SEED)
	if again.get("a") != walk.get("a") or again.get("b") != walk.get("b"):
		_fail("long walk is not stable")
		return
	var a: Vector2 = walk["a"]
	var b: Vector2 = walk["b"]
	if a.distance_to(b) < 8.0 or a.distance_to(b) > float(cfg.long_walk_cap) + 0.1:
		_fail("long walk length %.1f" % a.distance_to(b))
		return
	print("OK route segments=%d length=%.1f" % [count, a.distance_to(b)])


func _check_other_seed() -> void:
	var left: Dictionary = _Dress.long_walk(_SEED)
	var right: Dictionary = _Dress.long_walk(_OTHER)
	if right.is_empty():
		_fail("other seed has no walk")
		return
	if left.get("b") == right.get("b") and left.get("a") == right.get("a"):
		_fail("two seeds built the same walk")
		return
	print("OK route seeds differ")


func _check_props(cfg) -> void:
	var walk: Dictionary = _Dress.long_walk(_SEED)
	var a: Vector2 = walk["a"]
	var b: Vector2 = walk["b"]
	var kinds := {}
	var total := 0
	var chunks_with := 0
	for step in range(8, 80):
		var at := a.lerp(b, float(step) / 80.0)
		var cx := int(floor(at.x / 16.0))
		var cz := int(floor(at.y / 16.0))
		var first: Array[Dictionary] = _Dress.props_for_chunk(_SEED, cx, cz)
		var again: Array[Dictionary] = _Dress.props_for_chunk(_SEED, cx, cz)
		if first.size() > int(cfg.props_per_chunk):
			_fail("route props exceeded chunk cap")
			return
		if _signature(first) != _signature(again):
			_fail("route props are not deterministic")
			return
		if first.is_empty():
			continue
		chunks_with += 1
		for spot_v in first:
			var spot: Dictionary = spot_v
			var kind := str(spot.get("kind", ""))
			if kind not in cfg.prop_kinds:
				_fail("prop kind %s is not in the config" % kind)
				return
			kinds[kind] = true
			var cell: Vector2i = spot.get("cell", Vector2i.ZERO)
			if cell.x < cx * 16 or cell.y < cz * 16 or cell.x >= cx * 16 + 16 or cell.y >= cz * 16 + 16:
				_fail("prop %s left its chunk" % cell)
				return
			total += 1
	if total < 4 or kinds.size() < 2 or chunks_with < 2:
		_fail("route props total=%d kinds=%d chunks=%d" % [total, kinds.size(), chunks_with])
		return
	print("OK route props total=%d kinds=%d chunks=%d" % [total, kinds.size(), chunks_with])


func _check_wet() -> void:
	var walk: Dictionary = _Dress.long_walk(_SEED)
	var a: Vector2 = walk["a"]
	var b: Vector2 = walk["b"]
	var mid := a.lerp(b, 0.5)
	var kept := _Dress.tile_for(_SEED, mid.x, mid.y, _Types.RIVER)
	if kept != _Types.RIVER:
		_fail("river tile became %d on the route" % kept)
		return
	print("OK route keeps river tiles")


func _check_samples(cfg) -> void:
	var world = _World.new()
	var cells := _sample_cells(cfg)
	if cells.is_empty():
		_fail("no sample cells on the long walk")
		return
	var bare := _Cfg.new()
	bare.enabled = false
	var flat: Array = _read(world, cells, bare)
	var shaped: Array = _read(world, cells, null)
	var layer := float(_Settings.get_active().layer_height())
	var corner := Vector2(_Border.origin_corner_for_seed(_SEED))
	var up := false
	var down := false
	var path_cells: Array[Vector2i] = []
	var shoulders := {}
	var prev := 0.0
	var prev_set := false
	for i in cells.size():
		var cell: Vector2i = cells[i]
		var delta := float(shaped[i]) - float(flat[i])
		if delta > layer * 0.5:
			up = true
		if delta < -layer * 0.5:
			down = true
		if prev_set and absf(delta - prev) > layer + 0.01:
			_fail("relief step %.2f at %s" % [delta - prev, cell])
			return
		prev = delta
		prev_set = true
		var center := Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5)
		if center.distance_to(corner) < float(cfg.spawn_clear):
			if absf(delta) > 0.01:
				_fail("spawn pad moved at %s" % cell)
				return
			continue
		var tile := int(world.get_tile_type(center.x, center.y))
		var dist := _line_dist(cell)
		if dist <= float(cfg.path_radius):
			if tile != int(cfg.path_tile):
				_fail("path cell %s tile %d dist %.3f" % [cell, tile, dist])
				return
			path_cells.append(cell)
		var shoulder_cell := _offset_cell(cell, 2.2)
		var shoulder_dist := _line_dist(shoulder_cell)
		if shoulder_dist > float(cfg.path_radius) and shoulder_dist <= float(cfg.shoulder_radius):
			var shoulder_tile := int(world.get_tile_type(float(shoulder_cell.x) + 0.5, float(shoulder_cell.y) + 0.5))
			shoulders[shoulder_tile] = true
	if not up or not down:
		_fail("relief up=%s down=%s" % [up, down])
		return
	if path_cells.size() < 8:
		_fail("path cells %d" % path_cells.size())
		return
	for i in range(1, path_cells.size()):
		var step: Vector2i = path_cells[i] - path_cells[i - 1]
		if maxi(absi(step.x), absi(step.y)) > 1:
			_fail("path gap %s to %s" % [path_cells[i - 1], path_cells[i]])
			return
	if shoulders.size() < 2:
		_fail("shoulder used %d tiles" % shoulders.size())
		return
	var pad_on: float = _height_at(world, null, corner)
	var pad_off: float = _height_at(world, bare, corner)
	if absf(pad_on - pad_off) > 0.01:
		_fail("origin height changed by %.2f" % (pad_on - pad_off))
		return
	var t0 := Time.get_ticks_usec()
	for n in 24:
		var at: Vector2 = corner + Vector2(float(n), float(-n))
		world.get_surface_height(at.x, at.y)
		world.get_tile_type(at.x, at.y)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	if ms > 800.0:
		_fail("route samples took %.1f ms" % ms)
		return
	print("OK route relief path=%d shoulders=%d sample_ms=%.1f" % [path_cells.size(), shoulders.size(), ms])


func _sample_cells(cfg) -> Array[Vector2i]:
	var walk: Dictionary = _Dress.long_walk(_SEED)
	var out: Array[Vector2i] = []
	if walk.is_empty():
		return out
	var a: Vector2 = walk["a"]
	var b: Vector2 = walk["b"]
	var span := a.distance_to(b)
	var steps := int(ceil(span))
	var corner := Vector2(_Border.origin_corner_for_seed(_SEED))
	var seen := {}
	for step in range(0, steps + 1):
		var at := a.lerp(b, float(step) / float(maxi(steps, 1)))
		if at.distance_to(corner) < float(cfg.spawn_clear) - 2.0:
			continue
		if at.distance_to(b) < 4.0:
			continue
		var cell := Vector2i(int(floor(at.x)), int(floor(at.y)))
		if seen.has(cell):
			continue
		seen[cell] = true
		out.append(cell)
		if out.size() >= 96:
			break
	return out


func _offset_cell(cell: Vector2i, columns: float) -> Vector2i:
	var walk: Dictionary = _Dress.long_walk(_SEED)
	var a: Vector2 = walk["a"]
	var b: Vector2 = walk["b"]
	var dir := (b - a).normalized()
	var side := Vector2(-dir.y, dir.x)
	var at := Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5) + side * columns
	return Vector2i(int(floor(at.x)), int(floor(at.y)))


func _line_dist(cell: Vector2i) -> float:
	var walk: Dictionary = _Dress.long_walk(_SEED)
	var a: Vector2 = walk["a"]
	var b: Vector2 = walk["b"]
	var p := Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5)
	var ab := b - a
	var len2 := ab.length_squared()
	var t := 0.0
	if len2 > 0.01:
		t = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _read(world, cells: Array[Vector2i], cfg) -> Array:
	_Dress.set_config(cfg)
	world.apply_seed(_SEED)
	var out: Array = []
	for cell in cells:
		out.append(world.get_surface_height(float(cell.x), float(cell.y)))
	return out


func _height_at(world, cfg, at: Vector2) -> float:
	_Dress.set_config(cfg)
	world.apply_seed(_SEED)
	return float(world.get_surface_height(at.x, at.y))


func _signature(spots: Array[Dictionary]) -> String:
	var parts: PackedStringArray = []
	for spot in spots:
		var cell: Vector2i = spot.get("cell", Vector2i.ZERO)
		parts.append("%s:%s:%s" % [cell, spot.get("kind", ""), spot.get("yaw", 0)])
	return "|".join(parts)
