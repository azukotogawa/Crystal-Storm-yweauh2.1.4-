extends SceneTree

const _Scatter = preload("res://world/prop_scatter.gd")
const _World = preload("res://world/InfiniteNoiseWorld.gd")
const _Props = preload("res://helpers/voxel_prop_builder.gd")

const R := 12
const BUDGET := 12


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var tag := OS.get_environment("P7_TAG")
	var out_dir := OS.get_environment("P7_OUT")
	var world = _World.new(12349)
	var all: Array = []
	var per_kind := {}
	var per_chunk_max := {}
	var t0 := Time.get_ticks_usec()
	var biome_kinds := {}
	for cz in range(-R, R):
		for cx in range(-R, R):
			var spots: Array[Dictionary] = _Scatter.for_chunk(12349, cx, cz, BUDGET, world)
			var local := {}
			for s in spots:
				var k := str(s.kind)
				all.append(s)
				per_kind[k] = int(per_kind.get(k, 0)) + 1
				local[k] = int(local.get(k, 0)) + 1
				var b := str(world.get_biome(float(s.cell.x), 0.0, float(s.cell.y)).get("name", "?"))
				if not biome_kinds.has(b):
					biome_kinds[b] = {}
				biome_kinds[b][k] = int(biome_kinds[b].get(k, 0)) + 1
			for k in local.keys():
				per_chunk_max[k] = maxi(int(per_chunk_max.get(k, 0)), local[k])
	var us := Time.get_ticks_usec() - t0
	var chunks := float((2 * R) * (2 * R))
	var line := ""
	var ks := per_kind.keys()
	ks.sort()
	for k in ks:
		line += " %s=%d(%.2f/chunk,max%d)" % [k, per_kind[k], float(per_kind[k]) / chunks, per_chunk_max[k]]
	print("P7_PROPCOUNT tag=%s total=%d per_chunk=%.2f chunks=%d gen_us_per_chunk=%.0f kinds=%d%s" % [tag, all.size(), float(all.size()) / chunks, int(chunks), float(us) / chunks, ks.size(), line])
	var bl := ""
	var bn := biome_kinds.keys()
	bn.sort()
	for b in bn:
		bl += " %s:%d" % [b, biome_kinds[b].size()]
	print("P7_PROPBIOME tag=%s kinds_per_biome%s" % [tag, bl])
	_stats(tag, "bush", all.filter(func(s): return str(s.kind) == "bush"), out_dir)
	_stats(tag, "all", all, out_dir)
	var dark := 0
	var blocking := 0
	var darkest := 9.0
	var darkk := ""
	for k in _Scatter.KINDS:
		var node := _Props.build_scatter_prop(k)
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			var mat = (mi as MeshInstance3D).material_override
			if mat == null and (mi as MeshInstance3D).mesh != null and (mi as MeshInstance3D).mesh.get_surface_count() > 0:
				mat = (mi as MeshInstance3D).mesh.surface_get_material(0)
			if mat is StandardMaterial3D:
				var c: Color = (mat as StandardMaterial3D).albedo_color
				var lum := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
				if lum < darkest:
					darkest = lum
					darkk = k
				if lum < 0.08:
					dark += 1
		blocking += node.find_children("*", "CollisionObject3D", true, false).size()
		node.free()
	print("P7_PROPMAT tag=%s near_black_parts=%d darkest=%.3f(%s) collision_nodes=%d" % [tag, dark, darkest, darkk, blocking])
	var a: Array[Dictionary] = _Scatter.for_chunk(12349, 3, -2, BUDGET, world)
	var b2: Array[Dictionary] = _Scatter.for_chunk(12349, 3, -2, BUDGET, world)
	print("P7_PROPDET tag=%s deterministic=%s" % [tag, str(a) == str(b2)])
	quit(0)


func _stats(tag: String, label: String, spots: Array, out_dir: String) -> void:
	var set := {}
	for s in spots:
		set[s.cell] = true
	var n := set.size()
	var span := float(2 * R * ChunkData.SIZE)
	var dens := float(n) / (span * span)
	var nn: Array = []
	for c in set.keys():
		var best := 1e9
		for r in range(1, 16):
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dz)) != r:
						continue
					if set.has(c + Vector2i(dx, dz)):
						best = minf(best, Vector2(dx, dz).length())
			if best < 1e8 and float(r) > best:
				break
		if best < 1e8:
			nn.append(best)
	var mean := 0.0
	for d in nn:
		mean += d
	mean /= maxf(float(nn.size()), 1.0)
	var v := 0.0
	for d in nn:
		v += (d - mean) * (d - mean)
	var cv := sqrt(v / maxf(float(nn.size()), 1.0)) / maxf(mean, 0.0001)
	var ac_max := 0.0
	var ac_off := Vector2i.ZERO
	for dz in range(-20, 21):
		for dx in range(-20, 21):
			if maxi(absi(dx), absi(dz)) < 3:
				continue
			var c := 0
			for k in set.keys():
				if set.has(k + Vector2i(dx, dz)):
					c += 1
			var ratio := float(c) / maxf(float(n) * dens, 0.0001)
			if ratio > ac_max:
				ac_max = ratio
				ac_off = Vector2i(dx, dz)
	var align := 0.0
	var align_dir := ""
	for dir in ["x", "z", "x+z", "x-z"]:
		for mod in [2, 3, 4, 5, 6, 7, 8, 16]:
			var counts := {}
			for k in set.keys():
				var key: int = k.x if dir == "x" else (k.y if dir == "z" else (k.x + k.y if dir == "x+z" else k.x - k.y))
				var r := posmod(key, mod)
				counts[r] = int(counts.get(r, 0)) + 1
			var top := 0
			for r in counts.keys():
				top = maxi(top, counts[r])
			var score := float(top) / maxf(float(n) / float(mod), 1.0)
			if score > align:
				align = score
				align_dir = "%s mod %d" % [dir, mod]
	var occ := 0
	var grid := {}
	for k in set.keys():
		var g := Vector2i(floori(float(k.x) / 8.0), floori(float(k.y) / 8.0))
		grid[g] = int(grid.get(g, 0)) + 1
	var cells := float((2 * R * ChunkData.SIZE / 8) * (2 * R * ChunkData.SIZE / 8))
	var gm := float(n) / cells
	var gv := 0.0
	var empty := 0
	for gz in range(-R * ChunkData.SIZE / 8, R * ChunkData.SIZE / 8):
		for gx in range(-R * ChunkData.SIZE / 8, R * ChunkData.SIZE / 8):
			var c := float(grid.get(Vector2i(gx, gz), 0))
			gv += (c - gm) * (c - gm)
			if c == 0.0:
				empty += 1
	var vmr := (gv / cells) / maxf(gm, 0.0001)
	print("P7_PROPSTAT tag=%s set=%s n=%d density=%.4f nn_mean=%.2f nn_cv=%.3f(poisson~0.52,lattice~0) autocorr_max=%.2f@%s(random~1) align=%.2f(%s,random~1) clump_vmr=%.2f(random~1,clustered>1) empty_8x8=%.2f" % [tag, label, n, dens, mean, cv, ac_max, ac_off, align, align_dir, vmr, float(empty) / cells])
	var size := int(span)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	img.fill(Color(0.05, 0.05, 0.05))
	for k in set.keys():
		img.set_pixel(k.x + R * ChunkData.SIZE, k.y + R * ChunkData.SIZE, Color(0.3, 1.0, 0.3))
	img.save_png(out_dir + "/props-%s-%s.png" % [label, tag])
	var dimg := Image.create(size / 8, size / 8, false, Image.FORMAT_RGB8)
	var peak := 1
	for g in grid.keys():
		peak = maxi(peak, grid[g])
	for g in grid.keys():
		var x: int = g.x + R * ChunkData.SIZE / 8
		var y: int = g.y + R * ChunkData.SIZE / 8
		var vv := float(grid[g]) / float(peak)
		dimg.set_pixel(x, y, Color(vv, vv, vv))
	dimg.save_png(out_dir + "/density-%s-%s.png" % [label, tag])