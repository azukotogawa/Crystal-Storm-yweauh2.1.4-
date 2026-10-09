extends SceneTree
## Origin river clearance: unshifted mask outside the disk, no river inside it.


const _VoxelTypes = preload("res://helpers/voxel_types.gd")

const _SEEDS: Array[int] = [1, 7, 42, 99, 12349]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var world := InfiniteNoiseWorld.new()
	for seed_value in _SEEDS:
		if _scan_seed(world, seed_value):
			failed = true
	world.free()
	if failed:
		push_error("verify_river_mask failed")
		quit(1)
		return
	print("All river mask tests OK")
	quit(0)


func _scan_seed(world: InfiniteNoiseWorld, seed_value: int) -> bool:
	world.apply_seed(seed_value)
	var clearance := InfiniteNoiseWorld.SPAWN_RIVER_CLEARANCE
	var radius := int(clearance)
	var failed := false
	var active_inside := 0
	var river_tiles := 0
	var tile_samples := 0

	for z in range(-radius + 1, radius):
		for x in range(-radius + 1, radius):
			var d2 := float(x) * float(x) + float(z) * float(z)
			if d2 >= clearance * clearance:
				continue
			var mask: Dictionary = world.get_river_mask(float(x), float(z))
			if bool(mask.get("active", false)):
				active_inside += 1
				if active_inside == 1:
					push_error("seed %d river mask active inside clearance at (%d,%d)" % [seed_value, x, z])
			var in_core := absi(x) <= 16 and absi(z) <= 16
			var on_stride := (x & 3) == 0 and (z & 3) == 0
			if in_core or on_stride:
				tile_samples += 1
				if world.get_tile_type(float(x), float(z)) == _VoxelTypes.RIVER:
					river_tiles += 1
					if river_tiles == 1:
						push_error("seed %d RIVER tile inside clearance at (%d,%d)" % [seed_value, x, z])

	if active_inside > 0 or river_tiles > 0:
		failed = true

	var origin: Dictionary = world.get_river_mask(0.0, 0.0)
	if bool(origin.get("active", false)) or float(origin.get("strength", 1.0)) > 0.0001:
		push_error("seed %d origin mask should be inactive with zero strength, got %s" % [seed_value, str(origin)])
		failed = true
	if world.get_tile_type(0.0, 0.0) == _VoxelTypes.RIVER:
		push_error("seed %d origin tile is RIVER" % seed_value)
		failed = true

	# Interior falloff: active forced off, strength scaled by smoothstep.
	var sample := Vector2(24.0, -18.0)
	var raw: Dictionary = world.river_mask_formula(sample.x, sample.y)
	var faded: Dictionary = world.get_river_mask(sample.x, sample.y)
	var t := sample.length() / clearance
	var fade := t * t * (3.0 - 2.0 * t)
	var expect_strength := float(raw.get("strength", 0.0)) * fade
	if bool(faded.get("active", false)):
		push_error("seed %d interior mask stayed active" % seed_value)
		failed = true
	elif not is_equal_approx(float(faded.get("strength", -1.0)), expect_strength):
		push_error("seed %d interior strength %.4f want %.4f" % [seed_value, float(faded.get("strength", 0.0)), expect_strength])
		failed = true
	elif not is_equal_approx(float(faded.get("dist", -1.0)), float(raw.get("dist", -2.0))):
		push_error("seed %d interior dist changed" % seed_value)
		failed = true

	var rim := Vector2(clearance, 0.0)
	if not _masks_match(world.get_river_mask(rim.x, rim.y), world.river_mask_formula(rim.x, rim.y)):
		push_error("seed %d rim mask does not match the unshifted formula" % seed_value)
		failed = true

	var mismatch := 0
	var far := radius + 512
	# Coarse grid: every outside sample must match the unshifted formula exactly.
	for z in range(-far, far + 1, 16):
		var zz := float(z)
		for x in range(-far, far + 1, 16):
			var xx := float(x)
			if xx * xx + zz * zz < clearance * clearance:
				continue
			var mask: Dictionary = world.get_river_mask(xx, zz)
			var formula: Dictionary = world.river_mask_formula(xx, zz)
			if not _masks_match(mask, formula):
				mismatch += 1
				if mismatch == 1:
					push_error("seed %d mask != formula at (%.1f,%.1f) mask=%s formula=%s" % [seed_value, xx, zz, str(mask), str(formula)])
	if mismatch > 0:
		failed = true

	# Near-rim band, step 2 so a ribbon a few columns wide is not skipped.
	var nearest := -1.0
	var band_active := 0
	var band_total := 0
	var band_outer := clearance + 64.0
	for z in range(-radius - 64, radius + 65, 2):
		var zz := float(z)
		for x in range(-radius - 64, radius + 65, 2):
			var xx := float(x)
			var d2 := xx * xx + zz * zz
			if d2 < clearance * clearance or d2 > band_outer * band_outer:
				continue
			band_total += 1
			var mask: Dictionary = world.get_river_mask(xx, zz)
			if not _masks_match(mask, world.river_mask_formula(xx, zz)):
				mismatch += 1
				if mismatch == 1:
					push_error("seed %d band mask != formula at (%.1f,%.1f)" % [seed_value, xx, zz])
				failed = true
			if bool(mask.get("active", false)):
				band_active += 1
				var dist := sqrt(d2)
				if nearest < 0.0 or dist < nearest:
					nearest = dist
	var band_frac := float(band_active) / float(maxi(band_total, 1))
	if band_frac >= 0.85:
		push_error("seed %d near-rim band is a lake frac=%.3f nearest=%.1f" % [seed_value, band_frac, nearest])
		failed = true

	var ring_active := band_active
	var ring_total := band_total
	if ring_active == 0:
		var wider := _first_active_distance(world, clearance, clearance + 512.0)
		nearest = wider
		if wider < 0.0:
			push_error("seed %d found no river within 512 columns of the clearance" % seed_value)
			failed = true
		else:
			ring_active = 1
			print("seed %d nearest river is %.1f columns out (past the near rim)" % [seed_value, wider])

	if failed:
		push_error("seed %d river mask failed inside=%d tiles=%d/%d nearest=%.1f ring=%d/%d band=%.3f" % [
			seed_value, active_inside, river_tiles, tile_samples, nearest, ring_active, ring_total, band_frac,
		])
	else:
		print("OK seed %d river clearance inside_tiles=%d nearest=%.1f ring=%d/%d band=%.3f" % [
			seed_value, tile_samples, nearest, ring_active, ring_total, band_frac,
		])
	return failed


## Walk outward on 16 rays until a river cell appears, or the search radius ends.
func _first_active_distance(world: InfiniteNoiseWorld, inner: float, outer: float) -> float:
	var rays := 16
	for dist_i in range(int(ceil(inner)) + 1, int(outer) + 1, 2):
		var dist := float(dist_i)
		for ray in rays:
			var ang := float(ray) * TAU / float(rays)
			var xx := cos(ang) * dist
			var zz := sin(ang) * dist
			if bool(world.get_river_mask(xx, zz).get("active", false)):
				return dist
	return -1.0


func _masks_match(mask: Dictionary, formula: Dictionary) -> bool:
	if bool(mask.get("active", false)) != bool(formula.get("active", false)):
		return false
	if not is_equal_approx(float(mask.get("strength", 0.0)), float(formula.get("strength", 0.0))):
		return false
	if not is_equal_approx(float(mask.get("dist", 0.0)), float(formula.get("dist", 0.0))):
		return false
	return true
