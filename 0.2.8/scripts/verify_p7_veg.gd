extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")
const _Veg = preload("res://world/vegetation_manager.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var p = await C.boot(self, 30)
	var world = get_first_node_in_group("world")
	var bake = load("res://world/world_bake_service.gd").get_active()
	var args: Array = bake._veg_scatter_args(world)
	var t0 := Time.get_ticks_msec()
	var m: Dictionary = _Veg.bake_scatter_map(world, args[0], args[1], args[2])
	var ms := Time.get_ticks_msec() - t0
	var tag := OS.get_environment("P7_TAG")
	var by_kind := {}
	var bushes: Array = []
	var minx := 1 << 30
	var maxx := -(1 << 30)
	var minz := 1 << 30
	var maxz := -(1 << 30)
	var chunk := {}
	for k in m.keys():
		var pid := str(m[k].get("plant_id", "?"))
		by_kind[pid] = int(by_kind.get(pid, 0)) + 1
		var ck := Vector2i(floori(k.x / 16.0), floori(k.y / 16.0))
		if not chunk.has(ck):
			chunk[ck] = {}
		chunk[ck][pid] = int(chunk[ck].get(pid, 0)) + 1
		if pid == "bush":
			bushes.append(k)
		minx = mini(minx, k.x)
		maxx = maxi(maxx, k.x)
		minz = mini(minz, k.y)
		maxz = maxi(maxz, k.y)
	var per_chunk := {}
	for ck in chunk.keys():
		for pid in chunk[ck].keys():
			if not per_chunk.has(pid):
				per_chunk[pid] = [0, 0]
			per_chunk[pid][0] += chunk[ck][pid]
			per_chunk[pid][1] = maxi(per_chunk[pid][1], chunk[ck][pid])
	var pc_line := ""
	var kinds := by_kind.keys()
	kinds.sort()
	for pid in kinds:
		var mean := float(per_chunk[pid][0]) / float(maxi(chunk.size(), 1))
		pc_line += " %s=%d(mean/chunk=%.2f,max=%d)" % [pid, by_kind[pid], mean, per_chunk[pid][1]]
	print("P7_VEGCOUNT tag=%s total=%d chunks=%d ms=%d%s" % [tag, m.size(), chunk.size(), ms, pc_line])
	var set := {}
	for b in bushes:
		set[b] = true
	var nn: Array = []
	for b in bushes:
		var best := 1e9
		for r in range(1, 13):
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dz)) != r:
						continue
					if set.has(b + Vector2i(dx, dz)):
						best = minf(best, Vector2(dx, dz).length())
			if best < 1e8 and float(r) > best:
				break
		if best < 1e8:
			nn.append(best)
	var mean := 0.0
	for d in nn:
		mean += d
	mean /= maxf(float(nn.size()), 1.0)
	var var_ := 0.0
	for d in nn:
		var_ += (d - mean) * (d - mean)
	var cv := sqrt(var_ / maxf(float(nn.size()), 1.0)) / maxf(mean, 0.0001)
	var area := float((maxx - minx + 1) * (maxz - minz + 1))
	var dens := float(bushes.size()) / maxf(area, 1.0)
	var ac_max := 0.0
	var ac_off := Vector2i.ZERO
	for dz in range(-8, 9):
		for dx in range(-8, 9):
			if dx == 0 and dz == 0:
				continue
			if absi(dx) + absi(dz) <= 1:
				continue
			var c := 0
			for b in bushes:
				if set.has(b + Vector2i(dx, dz)):
					c += 1
			var ratio := float(c) / maxf(float(bushes.size()) * dens, 0.0001)
			if ratio > ac_max:
				ac_max = ratio
				ac_off = Vector2i(dx, dz)
	var align := 0.0
	var align_dir := ""
	for dir in ["x", "z", "x+z", "x-z"]:
		var lines := {}
		for b in bushes:
			var key: int = b.x if dir == "x" else (b.y if dir == "z" else (b.x + b.y if dir == "x+z" else b.x - b.y))
			for mod in [2, 3, 4, 5, 6, 7, 8]:
				var lk := "%d:%d" % [mod, posmod(key, mod)]
				lines[lk] = int(lines.get(lk, 0)) + 1
		for mod in [2, 3, 4, 5, 6, 7, 8]:
			var top := 0
			for r in mod:
				top = maxi(top, int(lines.get("%d:%d" % [mod, r], 0)))
			var score := float(top) / maxf(float(bushes.size()) / float(mod), 1.0)
			if score > align:
				align = score
				align_dir = "%s mod %d" % [dir, mod]
	print("P7_BUSHSTAT tag=%s n=%d density=%.4f nn_mean=%.2f nn_cv=%.3f(poisson~0.52) autocorr_max=%.2f@%s(random~1) align=%.2f(%s,random~1)" % [tag, bushes.size(), dens, mean, cv, ac_max, ac_off, align, align_dir])
	var cell := 4
	var w := int(ceil(float(maxx - minx + 1) / cell))
	var h := int(ceil(float(maxz - minz + 1) / cell))
	var img := Image.create(maxi(w, 1), maxi(h, 1), false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	var grid := {}
	var peak := 1
	for b in bushes:
		var g := Vector2i((b.x - minx) / cell, (b.y - minz) / cell)
		grid[g] = int(grid.get(g, 0)) + 1
		peak = maxi(peak, grid[g])
	for g in grid.keys():
		var v := float(grid[g]) / float(peak)
		img.set_pixel(g.x, g.y, Color(v, v, v))
	var full := Image.create(maxi(w, 1), maxi(h, 1), false, Image.FORMAT_RGB8)
	full.fill(Color.BLACK)
	for b in bushes:
		pass
	var img2 := Image.create(maxx - minx + 1, maxz - minz + 1, false, Image.FORMAT_RGB8)
	img2.fill(Color(0.1, 0.1, 0.1))
	for b in bushes:
		img2.set_pixel(b.x - minx, b.y - minz, Color.GREEN)
	var dir_out := OS.get_environment("P7_OUT")
	img.save_png(dir_out + "/bush-density-%s.png" % tag)
	img2.save_png(dir_out + "/bush-points-%s.png" % tag)
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	var keys := m.keys()
	keys.sort()
	for k in keys:
		hc.update(("%d,%d,%s;" % [k.x, k.y, str(m[k].get("plant_id", ""))]).to_utf8_buffer())
	print("P7_VEGHASH tag=%s %s" % [tag, hc.finish().hex_encode().substr(0, 16)])
	quit(0)