extends SceneTree

const _Veg = preload("res://world/vegetation_manager.gd")
const HALF := 96
const R := 8


func _init() -> void:
	call_deferred("_run")


func _metrics(pts: Array) -> Dictionary:
	var by := {}
	for p in pts:
		by[p] = true
	var nn_sum := 0.0
	var near_pairs := 0
	var aligned := 0
	var offs := {}
	for p in pts:
		var best := 1e9
		for dx in range(-R, R + 1):
			for dz in range(-R, R + 1):
				if dx == 0 and dz == 0:
					continue
				var d2 := dx * dx + dz * dz
				if d2 > R * R:
					continue
				if by.has(p + Vector2i(dx, dz)):
					best = minf(best, sqrt(float(d2)))
					near_pairs += 1
					if dx == 0 or dz == 0 or absi(dx) == absi(dz):
						aligned += 1
					var k := Vector2i(dx, dz)
					offs[k] = int(offs.get(k, 0)) + 1
		nn_sum += minf(best, float(R))
	var cells := 0
	var cells_al := 0
	for dx in range(-R, R + 1):
		for dz in range(-R, R + 1):
			if (dx == 0 and dz == 0) or dx * dx + dz * dz > R * R:
				continue
			cells += 1
			if dx == 0 or dz == 0 or absi(dx) == absi(dz):
				cells_al += 1
	var n := maxi(pts.size(), 1)
	var area := float((2 * HALF) * (2 * HALF))
	var expect_nn := 0.5 / sqrt(float(n) / area)
	var peak := 0
	for k in offs:
		peak = maxi(peak, int(offs[k]))
	var mean_off := float(near_pairs) / float(cells)
	return {
		"n": pts.size(),
		"clark_evans": (nn_sum / float(n)) / expect_nn,
		"align_ratio": (float(aligned) / maxf(float(near_pairs), 1.0)) / (float(cells_al) / float(cells)),
		"offset_peak": float(peak) / maxf(mean_off, 0.001),
	}


func _run() -> void:
	var tag := OS.get_environment("P6_TAG")
	if tag == "":
		tag = "run"
	var world := InfiniteNoiseWorld.new(12349)
	var bounds := {"min_wx": -HALF, "max_wx": HALF - 1, "min_wz": -HALF, "max_wz": HALF - 1}
	var map: Dictionary = _Veg.bake_scatter_map(world, 18000, {}, bounds)
	var trees: Array = []
	var big: Array = []
	var biomes := {}
	var img := Image.create(2 * HALF, 2 * HALF, false, Image.FORMAT_RGB8)
	var tint := {"plains": Color(0.25, 0.3, 0.15), "forest": Color(0.1, 0.25, 0.1), "marsh": Color(0.15, 0.2, 0.25), "steppe": Color(0.3, 0.27, 0.15)}
	for x in 2 * HALF:
		for z in 2 * HALF:
			var b: String = str(world.get_biome(float(x - HALF), 0.0, float(z - HALF)).get("name", "plains"))
			img.set_pixel(x, z, tint.get(b, Color(0.2, 0.2, 0.2)))
	for k in map:
		var e: Dictionary = map[k]
		var pid := str(e.get("plant_id", ""))
		var b := str(e.get("biome", ""))
		if not biomes.has(b):
			biomes[b] = {}
		biomes[b][pid] = int(biomes[b].get(pid, 0)) + 1
		var px: int = k.x + HALF
		var pz: int = k.y + HALF
		if pid == "tree":
			trees.append(k)
			big.append(k)
			img.set_pixel(px, pz, Color(1, 1, 1))
		elif pid == "bush" or pid == "fern":
			big.append(k)
			img.set_pixel(px, pz, Color(0.3, 0.9, 0.3))
		else:
			img.set_pixel(px, pz, img.get_pixel(px, pz).lightened(0.25))
	img.save_png("user://p6_veg_%s.png" % tag)
	var mt := _metrics(trees)
	var mb := _metrics(big)
	print("P6_PATTERN_BIOMES %s" % JSON.stringify(biomes))
	print("P6_PATTERN tag=%s total=%d trees=%d tree_CE=%.3f tree_align=%.3f tree_peak=%.2f big=%d big_CE=%.3f big_align=%.3f big_peak=%.2f png=%s" % [tag, map.size(), mt.n, mt.clark_evans, mt.align_ratio, mt.offset_peak, mb.n, mb.clark_evans, mb.align_ratio, mb.offset_peak, ProjectSettings.globalize_path("user://p6_veg_%s.png" % tag)])
	quit()
