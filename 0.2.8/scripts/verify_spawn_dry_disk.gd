extends SceneTree


const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _SpawnPointDef = preload("res://config/spawn_point_def.gd")

const _SEEDS: Array[int] = [0, 1, 2, 3, 5, 7, 8, 13, 42, 55, 77, 99, 100, 12349]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var world := InfiniteNoiseWorld.new()
	var crystal := CrystalManager.new()
	crystal.world = world
	var player := Player.new()
	player.world = world
	player.crystal_manager = crystal
	var clearance := InfiniteNoiseWorld.SPAWN_RIVER_CLEARANCE
	for seed_value in _SEEDS:
		world.apply_seed(seed_value)
		crystal._spawn_points.clear()
		var land: Vector2i = crystal._resolve_origin_spawn_position()
		var released := CrystalSpawnPoint.from_def(0, land, _SpawnPointDef.make_released())
		crystal._spawn_points.append(released)
		if released.is_boss or crystal.get_active_spawns().size() != 1:
			push_error("seed %d expected one released crystal, boss=%s count=%d" % [
				seed_value, released.is_boss, crystal.get_active_spawns().size(),
			])
			failed = true
		var col: Vector2i = player._resolve_spawn_column()
		var center: Vector2 = world.spawn_river_center()
		var dx := float(col.x) - center.x
		var dz := float(col.y) - center.y
		var dist := sqrt(dx * dx + dz * dz)
		var tile := int(world.get_tile_type(float(col.x), float(col.y)))
		var wet := _CrystalTypes.is_water_tile(tile)
		if wet or dist >= clearance:
			push_error("seed %d spawn %s dist %.1f tile %d land %s heart %s" % [
				seed_value, col, dist, tile, land, center,
			])
			failed = true
		else:
			print("OK seed %d spawn %s dist %.1f tile %d" % [seed_value, col, dist, tile])
	player.free()
	crystal.free()
	world.free()
	if failed:
		push_error("verify_spawn_dry_disk failed")
		quit(1)
		return
	print("All spawn dry disk tests OK")
	quit(0)
