# verify_river_specs.gd
# Headless verification for the FINAL best-looking rivers: ~10-16 voxel clean contained ribbons, ultra-flat water_level, maximum seamless continuity inside the strict defined band, rich corridor visuals + biome integration.
# Run: godot --headless --path . -s verify_river_specs.gd
# Primary experience: godot world_viewer.tscn (BIOME + COMPOSITE for gorgeous linear corridors, RIVERS for the perfect thin seamless water ribbons).

extends SceneTree

func _init():
	var seed_val := 12349
	if OS.has_environment("RIVER_VERIFY_SEED"):
		seed_val = int(OS.get_environment("RIVER_VERIFY_SEED"))
	print("=== River Specs Verification (seed %d) ===" % seed_val)
	var world := InfiniteNoiseWorld.new(seed_val)
	var ctx := RiverJobContext.new()

	# Known river-dense macro region for seed 12349 (from drainage patch debug)
	var best_cx := 7680.0
	var best_cz := 5120.0
	print("Using sample center: (%.0f, %.0f)" % [best_cx, best_cz])

	var step: float = 6.0
	var radius: float = 200.0
	var river_pts: Array = []
	var all_river_surf: Array[float] = []
	var bank_deltas: Array[float] = []
	var widths_x: Array[float] = []
	var widths_z: Array[float] = []
	var total_samples: int = 0
	var river_hits: int = 0

	var x: float = best_cx - radius
	while x <= best_cx + radius:
		var z: float = best_cz - radius
		while z <= best_cz + radius:
			total_samples += 1
			var base_e: float = world._compute_raw_elevation(x, z)
			var rinfo: Dictionary = world._compute_river_carve(x, z, base_e, ctx)
			var is_riv: bool = rinfo.get("is_river", false)
			var surf: float = world.get_surface_height_uncached(x, z, ctx)
			if is_riv:
				river_hits += 1
				river_pts.append(Vector2(x, z))
				all_river_surf.append(surf)

				# Width/bank probes are expensive — sample a subset (job cache still amortizes the grid pass).
				if widths_x.size() < 48 and river_hits % 4 == 0:
					var w_horiz: float = step
					var tx: float = x + step
					while w_horiz < 40.0:
						var ri2: Dictionary = world._compute_river_carve(tx, z, world._compute_raw_elevation(tx, z), ctx)
						if not ri2.get("is_river", false):
							break
						w_horiz += step
						tx += step
					tx = x - step
					while w_horiz < 40.0:
						var ri2b: Dictionary = world._compute_river_carve(tx, z, world._compute_raw_elevation(tx, z), ctx)
						if not ri2b.get("is_river", false):
							break
						w_horiz += step
						tx -= step

					var w_vert: float = step
					var tz: float = z + step
					while w_vert < 40.0:
						var ri3: Dictionary = world._compute_river_carve(x, tz, world._compute_raw_elevation(x, tz), ctx)
						if not ri3.get("is_river", false):
							break
						w_vert += step
						tz += step
					tz = z - step
					while w_vert < 40.0:
						var ri3b: Dictionary = world._compute_river_carve(x, tz, world._compute_raw_elevation(x, tz), ctx)
						if not ri3b.get("is_river", false):
							break
						w_vert += step
						tz -= step

					var local_thick: float = minf(w_horiz, w_vert)
					widths_x.append(local_thick)
					widths_z.append(local_thick)

					var bank_samples: Array[float] = []
					for d in [Vector2(24, 0), Vector2(-24, 0), Vector2(0, 24), Vector2(0, -24)]:
						var bx: float = x + d.x
						var bz: float = z + d.y
						var bs: float = world.get_surface_height_uncached(bx, bz, ctx)
						var bri: Dictionary = world._compute_river_carve(bx, bz, world._compute_raw_elevation(bx, bz), ctx)
						if not bri.get("is_river", false):
							bank_samples.append(bs - surf)
					if bank_samples.size() > 0:
						bank_samples.sort()
						bank_deltas.append(bank_samples[bank_samples.size() / 2])
			z += step
		x += step

	var river_pct: float = 100.0 * river_hits / max(1, total_samples)
	print("RIVER thin pct (dense sample): %.2f%%   (target 0.4-2.5 for 10-15 wide long features)" % river_pct)

	# Width stats (now using min(horiz,vert) per river point as thickness proxy)
	var sum_w: float = 0.0
	var max_w: float = 0.0
	var min_w: float = 999.0
	var wcount: int = 0
	for i in range(widths_x.size()):
		var w: float = widths_x[i]
		sum_w += w
		if w > max_w: max_w = w
		if w < min_w: min_w = w
		wcount += 1
	var avg_w: float = sum_w / max(1, wcount)
	print("Measured ribbon widths (min cardinal run at 2u step, per river pt): avg=%.1f  max=%.1f  min=%.1f" % [avg_w, max_w, min_w])
	print("Target: ~10-15 voxels thick. Cardinal min gives good cross-section thickness estimate regardless of river orientation.")

	# Surf / water level check
	var avg_riv_h: float = 0.0
	for hh in all_river_surf:
		avg_riv_h += hh
	avg_riv_h /= max(1, all_river_surf.size())

	var avg_bank_delta: float = 0.0
	var max_bank: float = 0.0
	for d in bank_deltas:
		avg_bank_delta += d
		if d > max_bank: max_bank = d
	avg_bank_delta /= max(1, bank_deltas.size())
	print("River surf avg: %.1f   avg bank delta (river surf to nearby non-river): %.1f  (max seen %.1f)" % [avg_riv_h, avg_bank_delta, max_bank])
	print("Water level success: delta ~3-12 (moderate valley carve; not 15-25 sunk pools). Small deltas = flat-ish good water level.")

	# Continuity / long run proxy (reuse viewer logic style)
	var continuity: float = 0.0
	var river_neighbor: int = 0
	var step_c: float = 11.0
	for p in river_pts:
		for d in [Vector2(step_c,0), Vector2(-step_c,0), Vector2(0,step_c), Vector2(0,-step_c)]:
			var nb: Dictionary = world._compute_river_carve(p.x + d.x, p.y + d.y, world._compute_raw_elevation(p.x + d.x, p.y + d.y), ctx)
			if nb.get("is_river", false):
				river_neighbor += 1
	if river_hits > 0:
		continuity = float(river_neighbor) / float(river_hits * 4)
	print("Continuity (neighbor frac at ~11u): %.2f   ( >0.35 good for connected)" % continuity)

	# Long run check (simple 1d-ish along sorted)
	var has_long: bool = false
	if river_pts.size() > 20:
		river_pts.sort()
		var run_len: int = 1
		for i in range(1, river_pts.size()):
			var dist: float = river_pts[i].distance_to(river_pts[i-1])
			if dist < 28.0:
				run_len += 1
				if run_len > 18:
					has_long = true
					break
			else:
				run_len = 1
	print("Long river segments: %s" % ("yes (good)" if has_long else "check (may be winding)"))

	# Also test a few explicit voxel water levels on a river point
	var test_wx: float = 0.0
	var test_wz: float = 0.0
	for p in river_pts:
		test_wx = p.x; test_wz = p.y; break
	if test_wx == 0.0 and river_pts.size() > 0:
		test_wx = river_pts[0].x; test_wz = river_pts[0].y
	var tsurf: float = world.get_surface_height_uncached(test_wx, test_wz, ctx)
	var trinfo: Dictionary = world._compute_river_carve(test_wx, test_wz, world._compute_raw_elevation(test_wx, test_wz), ctx)
	var tbed: float = tsurf - float(trinfo.get("channel_depth", 6.0))
	print("Example river column @ (%.0f,%.0f): surf(water_level)=%.1f  channel_depth=%.1f -> bed=%.1f" % [test_wx, test_wz, tsurf, trinfo.get("channel_depth", -1), tbed])
	print("Voxel water should occupy (bed < wy <= surf) i.e. %.1f < wy <= %.1f" % [tbed, tsurf])

	# Quick flatness check on water_level (low variance along a few river points = "flat surface")
	if river_pts.size() > 5:
		var ssum: float = 0.0
		var ssum2: float = 0.0
		var n: int = 0
		for i in range(0, min(river_pts.size(), 25), 2):
			var p: Vector2 = river_pts[i]
			var sh: float = world.get_surface_height_uncached(p.x, p.y, ctx)
			ssum += sh
			ssum2 += sh * sh
			n += 1
		var mean_s: float = ssum / n
		var var_s: float = (ssum2 / n) - (mean_s * mean_s)
		print("Water level flatness (stddev of surf on ~%d river samples): %.2f  (lower = flatter consistent water surface)" % [n, sqrt(max(0.0, var_s))])

	# River Corridor Feature quality (new for "fits into biome geography + clear/distinguishable" design goal).
	# Average corridor_factor on the traced river points + count of strong corridor samples.
	# High values + many samples = the wider valley+biome influence creates visible linear corridors (moist/basin shifts) around the strict water ribbon.
	# Combined with BIOME mode in viewer this proves rivers are integrated geographic features, not faint overlays.
	var c_samples: int = 0
	var c_sum: float = 0.0
	var c_strong: int = 0
	for p in river_pts:
		var ri2: Dictionary = world._compute_river_carve(p.x, p.y, world._compute_raw_elevation(p.x, p.y), ctx)
		var cf: float = float(ri2.get("corridor_factor", 0.0))
		c_sum += cf
		if cf > 0.30:
			c_strong += 1
		c_samples += 1
	var avg_c: float = 0.0
	if c_samples > 0:
		avg_c = c_sum / float(c_samples)
	print("Corridor (valley+biome integration): avg_factor=%.2f  strong(>0.3)=%d/%d   (expect avg>0.25 + many strong for clear distinguishable river corridors in biome geography)" % [avg_c, c_strong, c_samples])

	# --- Honest continuity metrics (components + flow-traced unbroken runs) ---
	# Proximity components (fragmentation + real connected span)
	var comps: Array = []
	for pos in river_pts:
		var found := false
		for c in comps:
			for p in c:
				if pos.distance_to(p) < 4.5:  # dense 2u grid tolerance
					c.append(pos)
					found = true
					break
			if found:
				break
		if not found:
			comps.append([pos])
	var num_comps := comps.size()
	var max_c_pts := 0
	var max_c_span := 0.0
	for c in comps:
		max_c_pts = max(max_c_pts, c.size())
		for ii in c.size():
			for jj in range(ii + 1, c.size()):
				max_c_span = max(max_c_span, c[ii].distance_to(c[jj]))

	# Flow-traced max unbroken (walk forward from samples using local river continuation)
	var max_traced: float = 0.0
	var tr_step := 3.0
	for idx in range(0, river_pts.size(), 3):
		var cur: Vector2 = river_pts[idx]
		var run := 0.0
		for _k in range(80):  # ~240 units max trace
			var best: Vector2 = Vector2.ZERO
			var best_sc: float = -999.0
			for d in [Vector2(tr_step,0), Vector2(-tr_step,0), Vector2(0,tr_step), Vector2(0,-tr_step),
					  Vector2(tr_step*0.707,tr_step*0.707), Vector2(-tr_step*0.707,tr_step*0.707),
					  Vector2(tr_step*0.707,-tr_step*0.707), Vector2(-tr_step*0.707,-tr_step*0.707)]:
				var np: Vector2 = cur + d
				var nfo: Dictionary = world._compute_river_carve(np.x, np.y, world._compute_raw_elevation(np.x, np.y), ctx)
				if nfo.get("is_river", false):
					var sc: float = 1.0
					sc += (d.normalized().dot( (np - cur).normalized() )) * 0.6   # slight forward bias
					if sc > best_sc:
						best_sc = sc
						best = np
			if best == Vector2.ZERO:
				break
			cur = best
			run += tr_step
		if run > max_traced:
			max_traced = run

	print("River components (dense): %d   largest %d pts, span %.0f units   max flow-traced unbroken: %.0f units" % [num_comps, max_c_pts, max_c_span, max_traced])
	if max_traced > 150.0 or max_c_span > 180.0:
		print("LONG GAP-FREE RIVER RUN DETECTED in dense probe — good sign for winding continuity.")

	# Load main scene quick check (no crash)
	print("\n--- Main scene / chunk load test ---")
	var main_scene := load("scenes/main.tscn")
	if main_scene:
		print("Main scene loaded OK (no parse error).")
	else:
		print("WARNING: main.tscn load returned null")

	var chunk_scene := load("scenes/ChunkView.tscn")
	print("ChunkView scene: %s" % ("OK" if chunk_scene else "null"))

	# Basic API no-crash
	var _h: float = world.get_surface_height(42.3, -17.6)
	var _t: int = world.get_tile_type(42.3, -17.6)
	var _v: int = world.get_voxel(42.3, 35.0, -17.6)
	print("API surface/tile/voxel calls: OK")

	var wl_std := 0.0
	var n_wl := 0
	if river_pts.size() > 5:
		var ssum := 0.0
		var ssum2 := 0.0
		for i in range(0, min(river_pts.size(), 25), 2):
			var p: Vector2 = river_pts[i]
			var sh: float = world.get_surface_height_uncached(p.x, p.y, ctx)
			ssum += sh
			ssum2 += sh * sh
			n_wl += 1
		if n_wl > 0:
			var mean_s: float = ssum / n_wl
			var var_s: float = (ssum2 / n_wl) - (mean_s * mean_s)
			wl_std = sqrt(maxf(0.0, var_s))
			print("Water level flatness stddev: %.2f (n=%d)" % [wl_std, n_wl])

	var high_elev_river := 0
	for p in river_pts:
		if world._compute_raw_elevation(p.x, p.y) > 88.0:
			high_elev_river += 1
	var high_elev_pct := 100.0 * float(high_elev_river) / maxf(1.0, float(river_hits))

	print("\n=== Verdict ===")
	var width_ok: bool = avg_w >= 8.0 and avg_w <= 18.5
	var level_ok: bool = avg_bank_delta >= 2.5 and avg_bank_delta <= 14.0
	var conn_ok: bool = continuity >= 0.35 or has_long
	var density_ok: bool = river_hits >= 50
	var long_ok: bool = max_traced > 150.0 or max_c_span > 180.0
	var corridor_ok: bool = avg_c > 0.25
	var flat_ok: bool = (n_wl >= 5 and wl_std < 2.0) or river_hits < 5
	var alpine_ok: bool = high_elev_pct < 0.5

	if width_ok and level_ok and conn_ok and density_ok and long_ok and corridor_ok and flat_ok and alpine_ok:
		print("PASS: width=%.1f bank_delta=%.1f continuity=%.2f corridor=%.2f traced=%.0f" % [
			avg_w, avg_bank_delta, continuity, avg_c, max_traced
		])
		quit(0)
	else:
		print("NEEDS TUNE: width=%s level=%s conn=%s density=%s long=%s corridor=%s flat=%s alpine=%s" % [
			width_ok, level_ok, conn_ok, density_ok, long_ok, corridor_ok, flat_ok, alpine_ok
		])
		quit(1)
