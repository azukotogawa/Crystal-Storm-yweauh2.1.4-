extends SceneTree


const _Border = preload("res://helpers/world_border.gd")
const _Edits = preload("res://world/terrain_edits.gd")
const _Pois = preload("res://world/poi_scatter.gd")

const SEEDS: Array[int] = [1, 7, 42, 12349, 9001]


var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	_Edits.reset()
	var hashes: Dictionary = {}
	for seed_value in SEEDS:
		var digest := _check_seed(seed_value)
		if digest == "":
			continue
		hashes[seed_value] = digest
		var again := _edge_hash(_make_world(seed_value))
		if again != digest:
			_fail("seed %d border hash changed on replay %s vs %s" % [seed_value, digest, again])
		else:
			print("OK seed %d border hash %s" % [seed_value, digest])
	if hashes.size() >= 2:
		var distinct: Dictionary = {}
		for seed_value in hashes:
			distinct[hashes[seed_value]] = true
		if distinct.size() < 2:
			_fail("different seeds produced the same border hash")
		else:
			print("OK border hash changes with seed (%d distinct)" % distinct.size())
	if _failed == 0:
		print("WORLD EDGE BORDERS OK")
		quit(0)
	else:
		push_error("verify_world_edge_borders: %d failure(s)" % _failed)
		quit(1)


func _make_world(seed_value: int) -> InfiniteNoiseWorld:
	var world := InfiniteNoiseWorld.new()
	world.apply_seed(seed_value)
	return world


func _check_seed(seed_value: int) -> String:
	var world := _make_world(seed_value)
	var half := int(_Border.PLAYABLE_HALF_X)
	var ocean_n := 0
	var mountain_n := 0
	var ocean_hi := -999.0
	var mountain_lo := 999.0
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for z in range(-half, half + 1):
		if not _take_edge(world, ctx, half, z, "ocean"):
			world.free()
			return ""
		if not _take_edge(world, ctx, -half, z, "ocean"):
			world.free()
			return ""
		ocean_n += 2
		if posmod(z, 64) == 0:
			ocean_hi = maxf(ocean_hi, world.get_surface_height_uncached(float(half), float(z)))
			ocean_hi = maxf(ocean_hi, world.get_surface_height_uncached(float(-half), float(z)))
	for x in range(-half + 1, half):
		if not _take_edge(world, ctx, x, half, "mountain"):
			world.free()
			return ""
		if not _take_edge(world, ctx, x, -half, "mountain"):
			world.free()
			return ""
		mountain_n += 2
		if posmod(x, 64) == 0:
			mountain_lo = minf(mountain_lo, world.get_surface_height_uncached(float(x), float(half)))
			mountain_lo = minf(mountain_lo, world.get_surface_height_uncached(float(x), float(-half)))
		if posmod(x, 16) == 0:
			if not _cliff(world, float(x), float(half), Vector2(0, -1)):
				world.free()
				return ""
			if not _cliff(world, float(x), float(-half), Vector2(0, 1)):
				world.free()
				return ""
	if not _reach(world, seed_value):
		world.free()
		return ""
	var digest := ctx.finish().hex_encode()
	print(
		"EDGE seed=%d ocean_cells=%d mountain_cells=%d ocean_max_h=%.1f mountain_min_h=%.1f hash=%s"
		% [seed_value, ocean_n, mountain_n, ocean_hi, mountain_lo, digest.substr(0, 16)]
	)
	world.free()
	return digest


func _take_edge(world: InfiniteNoiseWorld, ctx: HashingContext, x: int, z: int, kind: String) -> bool:
	var h := world.get_surface_height_uncached(float(x), float(z))
	var tile := world.get_tile_type_uncached(float(x), float(z))
	ctx.update(PackedByteArray([x & 255, (x >> 8) & 255, z & 255, (z >> 8) & 255, tile & 255]))
	ctx.update(PackedFloat32Array([h]).to_byte_array())
	if kind == "ocean":
		if not _Border.is_ocean_tile(tile) or h > _Border.OCEAN_EDGE_MAX:
			_fail("ocean edge %d,%d tile=%d h=%.2f" % [x, z, tile, h])
			return false
		if not _Border.blocks_player_at(float(x), float(z), tile):
			_fail("ocean edge %d,%d does not stop the player" % [x, z])
			return false
	else:
		if not _Border.is_border_mountain_tile(tile) or h < _Border.MOUNTAIN_EDGE_MIN:
			_fail("mountain edge %d,%d tile=%d h=%.2f" % [x, z, tile, h])
			return false
	return true


func _cliff(world: InfiniteNoiseWorld, x: float, z: float, inland: Vector2) -> bool:
	var edge_h := world.get_surface_height_uncached(x, z)
	var foot := Vector2(x, z) + inland * (_Border.CREST_COLS + 2.0)
	var foot_h := world.get_surface_height_uncached(foot.x, foot.y)
	if edge_h - foot_h < 12.0:
		_fail("headwall too low at %.0f,%.0f edge=%.1f foot=%.1f" % [x, z, edge_h, foot_h])
		return false
	return true


func _reach(world: InfiniteNoiseWorld, seed_value: int) -> bool:
	var spawn: Vector2i = _Border.origin_corner_for_seed(seed_value)
	if _Border.playable_inset(float(spawn.x), float(spawn.y)) <= _Border.RIM_BAND_MAX:
		_fail("spawn %s sits inside the rim" % spawn)
		return false
	if _Border.rim_surface_tile(seed_value, float(spawn.x), float(spawn.y)) >= 0:
		_fail("spawn %s is a rim tile" % spawn)
		return false
	var spawn_tile := world.get_tile_type_uncached(float(spawn.x), float(spawn.y))
	var spawn_h := world.get_surface_height_uncached(float(spawn.x), float(spawn.y))
	if _Border.is_ocean_tile(spawn_tile):
		_fail("spawn %s is ocean tile %d" % [spawn, spawn_tile])
		return false
	var step := Vector2(-signf(float(spawn.x)), -signf(float(spawn.y)))
	var cursor := Vector2(spawn)
	for _i in 16:
		cursor += step * 4.0
		if _Border.rim_surface_tile(seed_value, cursor.x, cursor.y) >= 0:
			_fail("corridor blocked at %s" % cursor)
			return false
		if _Border.is_ocean_tile(world.get_tile_type_uncached(cursor.x, cursor.y)):
			_fail("corridor ocean at %s" % cursor)
			return false
	var pois: Array = _Pois.proposals(seed_value)
	if pois.is_empty():
		_fail("seed %d generated no POIs" % seed_value)
		return false
	var blocked := 0
	for spot_v in pois:
		var center: Vector2i = spot_v.get("center", Vector2i.ZERO)
		if not _Border.is_playable(float(center.x), float(center.y)):
			blocked += 1
			continue
		if _Border.playable_inset(float(center.x), float(center.y)) <= _Border.RIM_BAND_MAX:
			blocked += 1
			continue
		if _Border.rim_surface_tile(seed_value, float(center.x), float(center.y)) >= 0:
			blocked += 1
	if blocked > 0:
		_fail("seed %d has %d POIs inside the rim" % [seed_value, blocked])
		return false
	print(
		"REACH seed=%d spawn=%s tile=%d h=%.1f pois=%d"
		% [seed_value, spawn, spawn_tile, spawn_h, pois.size()]
	)
	return true


func _edge_hash(world: InfiniteNoiseWorld) -> String:
	var half := int(_Border.PLAYABLE_HALF_X)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for z in range(-half, half + 1):
		_hash_cell(world, ctx, half, z)
		_hash_cell(world, ctx, -half, z)
	for x in range(-half + 1, half):
		_hash_cell(world, ctx, x, half)
		_hash_cell(world, ctx, x, -half)
	var digest := ctx.finish().hex_encode()
	world.free()
	return digest


func _hash_cell(world: InfiniteNoiseWorld, ctx: HashingContext, x: int, z: int) -> void:
	var h := world.get_surface_height_uncached(float(x), float(z))
	var tile := world.get_tile_type_uncached(float(x), float(z))
	ctx.update(PackedByteArray([x & 255, (x >> 8) & 255, z & 255, (z >> 8) & 255, tile & 255]))
	ctx.update(PackedFloat32Array([h]).to_byte_array())
