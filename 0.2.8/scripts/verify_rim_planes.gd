extends SceneTree

const _B = preload("res://helpers/world_border.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _WorldSettings = preload("res://config/world_settings.gd")


func _init() -> void:
	call_deferred("_run")


var _cd: ChunkData = null


func _micro(world: InfiniteNoiseWorld, x: int, z: int, mx: int, mz: int) -> int:
	var layer: float = _WorldSettings.get_active().layer_height()
	var n := TerrainLook.STEPS_PER_BLOCK
	var h: float = world.get_surface_height(float(x), float(z))
	var s := int(round(h * float(n) / layer))
	if _cd.has_method("rim_plane_steps"):
		s += int(_cd.rim_plane_steps(x, z, mx, mz, h))
	return s


func _region(world: InfiniteNoiseWorld, label: String, x0: int, x1: int, z0: int, z1: int) -> int:
	var n := TerrainLook.STEPS_PER_BLOCK
	var layer: float = _WorldSettings.get_active().layer_height()
	var w := (x1 - x0) * n
	var grid := {}
	var lo := 1 << 30
	for z in range(z0, z1):
		for x in range(x0, x1):
			if not TerrainLook.column_waves(world.get_tile_type(float(x), float(z))):
				continue
			for mz in n:
				for mx in n:
					var s := _micro(world, x, z, mx, mz)
					grid[Vector2i((x - x0) * n + mx, (z - z0) * n + mz)] = s
					lo = mini(lo, s)
	var hist := {}
	var bad := 0
	var cliffs := 0
	for k in grid:
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			var nk: Vector2i = k + d
			if not grid.has(nk):
				continue
			var diff: int = absi(int(grid[k]) - int(grid[nk]))
			hist[diff] = int(hist.get(diff, 0)) + 1
			if diff > 1:
				var kk: Vector2i = k
				var ax: int = x0 + kk.x / n
				var az: int = z0 + kk.y / n
				var bx: int = x0 + nk.x / n
				var bz: int = z0 + nk.y / n
				if absf(world.surface_height_raw(float(ax), float(az)) - world.surface_height_raw(float(bx), float(bz))) > layer:
					cliffs += 1
				else:
					bad += 1
	var planes := 0
	var seen := {}
	for k in grid:
		if seen.has(k):
			continue
		planes += 1
		var stack: Array = [k]
		seen[k] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nk: Vector2i = c + d
				if grid.has(nk) and not seen.has(nk) and int(grid[nk]) == int(grid[c]):
					seen[nk] = true
					stack.append(nk)
	print("REGION ", label, " micro=", grid.size(), " planes=", planes, " bad=", bad, " cliff_pairs=", cliffs, " diffhist=", hist)
	for zz in range(0, (z1 - z0) * n, n * 4):
		var row := ""
		for xx in range(0, w, n / 2):
			var k := Vector2i(xx, zz)
			row += ("%3d" % (int(grid[k]) - lo)) if grid.has(k) else "  ."
		print("ROW z=", z0 + zz / n, " ", row)
	return bad


func _run() -> void:
	_TerrainEdits.reset()
	var world := InfiniteNoiseWorld.new()
	world.world_seed = 12349
	_cd = ChunkData.new(Vector2i.ZERO, world)
	var bad := 0
	bad += _region(world, "+x", 992, 1024, -974, -950)
	bad += _region(world, "-z", 950, 974, -1024, -992)
	print("RIM PLANES ", "OK" if bad == 0 else "FAIL", " bad=", bad)
	if world is Node:
		world.free()
	quit(0 if bad == 0 else 1)
