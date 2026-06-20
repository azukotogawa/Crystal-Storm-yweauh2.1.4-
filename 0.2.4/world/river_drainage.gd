# river_drainage.gd
# Macro hydrology: D8 flow accumulation patches, spine segments, hydraulic polylines.
class_name RiverDrainage
extends RefCounted

const DRAIN_CELL := 64.0
const PATCH_INTERIOR := 32
const HALO_SIZE := 34
const DRAIN_ACC_THRESHOLD := 12
const TRIBUTARY_ACC_MIN := 5
const TRIBUTARY_SEED_FREQ := 0.72
const ALPINE_ELEV := 88.0
const ALPINE_ACC_MIN := 28
const HYDRAULIC_SAMPLE_STEP := 16.0
const MEANDER_MAX := 5.5
const BANK_LIFT := 2.0
const DEPTH_AT_CENTER := 5.5
const MAX_TRACE_STEPS := 48
const MIN_ACC_CONTINUE := 4
const CORRIDOR_QUERY_RADIUS := 40.0

const D8_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)
]


class RiverSegment:
	var hydraulic_points: PackedVector2Array = PackedVector2Array()
	var water_levels: PackedFloat32Array = PackedFloat32Array()
	var acc: float = 0.0
	var order: int = 0
	var segment_id: int = 0


class DrainagePatch:
	var origin: Vector2i = Vector2i.ZERO
	var segments: Array = []
	var flow_acc: PackedFloat32Array = PackedFloat32Array()
	var flow_dir: PackedInt32Array = PackedInt32Array()

	func acc_interior(lx: int, lz: int) -> float:
		return flow_acc[lz * RiverDrainage.PATCH_INTERIOR + lx]

	func dir_halo(hx: int, hz: int) -> int:
		return flow_dir[hz * RiverDrainage.HALO_SIZE + hx]


static func macro_cell(wx: float, wz: float) -> Vector2i:
	return Vector2i(floori(wx / DRAIN_CELL), floori(wz / DRAIN_CELL))


static func patch_origin_for_macro(cx: int, cz: int) -> Vector2i:
	return Vector2i(cx - 16, cz - 16)


static func halo_index_to_macro(hx: int, hz: int, pcx: int, pcz: int) -> Vector2i:
	return Vector2i(pcx - 1 + hx, pcz - 1 + hz)


static func _cell_hash(cx: int, cz: int, seed: int) -> int:
	return int(abs((cx * 73856093) ^ (cz * 19349663) ^ (seed * 83492791)) % 2147483647)


static func neighbor_patch_origin_for_up_cell(up_cell: Vector2i, pcx: int, pcz: int) -> Vector2i:
	var west := up_cell.x < 0
	var east := up_cell.x >= HALO_SIZE
	var north := up_cell.y < 0
	var south := up_cell.y >= HALO_SIZE
	var npcx := pcx
	var npcz := pcz
	if west:
		npcx -= PATCH_INTERIOR
	if east:
		npcx += PATCH_INTERIOR
	if north:
		npcz -= PATCH_INTERIOR
	if south:
		npcz += PATCH_INTERIOR
	return Vector2i(npcx, npcz)


static func _map_to_neighbor_interior(up_cell: Vector2i, pcx: int, pcz: int) -> int:
	var norigin := neighbor_patch_origin_for_up_cell(up_cell, pcx, pcz)
	var halo_origin := Vector2i(pcx - 1, pcz - 1)
	var up_macro := halo_origin + up_cell
	var local := up_macro - norigin
	return local.y * PATCH_INTERIOR + local.x


static func build_drainage_patch(
	pcx: int,
	pcz: int,
	world_seed: int,
	elev_fn: Callable,
	meander_fn: Callable,
	trib_fn: Callable,
	build_cache: Dictionary,
	allow_stitch: bool = true
) -> DrainagePatch:
	var key := Vector2i(pcx, pcz)
	if build_cache.has(key):
		return build_cache[key]

	var patch := DrainagePatch.new()
	patch.origin = key
	build_cache[key] = patch

	var elev := PackedFloat32Array()
	elev.resize(HALO_SIZE * HALO_SIZE)
	var cells: Array[Vector2i] = []
	for hz in HALO_SIZE:
		for hx in HALO_SIZE:
			var mc := halo_index_to_macro(hx, hz, pcx, pcz)
			var wx := float(mc.x) * DRAIN_CELL
			var wz := float(mc.y) * DRAIN_CELL
			elev[hz * HALO_SIZE + hx] = elev_fn.call(wx, wz)
			cells.append(Vector2i(hx, hz))

	patch.flow_dir.resize(HALO_SIZE * HALO_SIZE)
	for hz in HALO_SIZE:
		for hx in HALO_SIZE:
			var idx := hz * HALO_SIZE + hx
			var e0 := elev[idx]
			var best_dir := -1
			var best_e := e0 + 0.0001
			for di in 8:
				var nx := hx + D8_OFFSETS[di].x
				var nz := hz + D8_OFFSETS[di].y
				if nx < 0 or nx >= HALO_SIZE or nz < 0 or nz >= HALO_SIZE:
					continue
				var ne := elev[nz * HALO_SIZE + nx]
				if ne < best_e - 0.001:
					best_e = ne
					best_dir = di
				elif abs(ne - best_e) < 0.001 and best_dir >= 0:
					var mc := halo_index_to_macro(hx, hz, pcx, pcz)
					var tie := _cell_hash(mc.x, mc.y, world_seed) % 8
					if di == tie:
						best_dir = di
			patch.flow_dir[idx] = best_dir

	var acc_full := PackedFloat32Array()
	acc_full.resize(HALO_SIZE * HALO_SIZE)
	for i in acc_full.size():
		acc_full[i] = 1.0

	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ea := elev[a.y * HALO_SIZE + a.x]
		var eb := elev[b.y * HALO_SIZE + b.x]
		if abs(ea - eb) > 0.001:
			return ea > eb
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y
	)

	for cell in cells:
		var hx := cell.x
		var hz := cell.y
		var idx := hz * HALO_SIZE + hx
		var d := patch.flow_dir[idx]
		if d < 0:
			continue
		var off := D8_OFFSETS[d]
		var nx := hx + off.x
		var nz := hz + off.y
		if nx >= 0 and nx < HALO_SIZE and nz >= 0 and nz < HALO_SIZE:
			var nidx := nz * HALO_SIZE + nx
			acc_full[nidx] += acc_full[idx]

	if allow_stitch:
		for hz in HALO_SIZE:
			for hx in HALO_SIZE:
				var idx := hz * HALO_SIZE + hx
				for di in 8:
					var off := D8_OFFSETS[di]
					var up_hx := hx - off.x
					var up_hz := hz - off.y
					if up_hx >= 0 and up_hx < HALO_SIZE and up_hz >= 0 and up_hz < HALO_SIZE:
						continue
					var up_cell := Vector2i(up_hx, up_hz)
					var norigin := neighbor_patch_origin_for_up_cell(up_cell, pcx, pcz)
					if norigin >= key:
						continue
					if not build_cache.has(norigin):
						build_drainage_patch(
							norigin.x, norigin.y, world_seed, elev_fn, meander_fn, trib_fn, build_cache, false
						)
					if build_cache.has(norigin):
						var nidx := _map_to_neighbor_interior(up_cell, pcx, pcz)
						var neighbor: DrainagePatch = build_cache[norigin]
						if nidx >= 0 and nidx < neighbor.flow_acc.size():
							acc_full[idx] += neighbor.flow_acc[nidx]

	patch.flow_acc.resize(PATCH_INTERIOR * PATCH_INTERIOR)
	for lz in PATCH_INTERIOR:
		for lx in PATCH_INTERIOR:
			var hx2 := lx + 1
			var hz2 := lz + 1
			patch.flow_acc[lz * PATCH_INTERIOR + lx] = acc_full[hz2 * HALO_SIZE + hx2]

	var seg_id := 0
	for lz in PATCH_INTERIOR:
		for lx in PATCH_INTERIOR:
			var hx3 := lx + 1
			var hz3 := lz + 1
			var mc := halo_index_to_macro(hx3, hz3, pcx, pcz)
			var acc := patch.flow_acc[lz * PATCH_INTERIOR + lx]
			var raw_e := elev[hz3 * HALO_SIZE + hx3]
			var trib: float = (float(trib_fn.call(float(mc.x), float(mc.y))) + 1.0) * 0.5
			var spine: bool = acc >= DRAIN_ACC_THRESHOLD or (acc >= TRIBUTARY_ACC_MIN and trib > TRIBUTARY_SEED_FREQ)
			if raw_e > ALPINE_ELEV and acc < ALPINE_ACC_MIN:
				spine = false
			if not spine:
				continue
			var order := 0 if acc >= DRAIN_ACC_THRESHOLD else 1
			var seg := _trace_segment(patch, lx, lz, pcx, pcz, acc, order, seg_id, elev_fn, meander_fn)
			if seg.hydraulic_points.size() >= 2:
				patch.segments.append(seg)
				seg_id += 1

	return patch


static func _trace_segment(
	patch: DrainagePatch,
	start_lx: int,
	start_lz: int,
	pcx: int,
	pcz: int,
	start_acc: float,
	order: int,
	seg_id: int,
	elev_fn: Callable,
	meander_fn: Callable
) -> RiverSegment:
	var seg := RiverSegment.new()
	seg.acc = start_acc
	seg.order = order
	seg.segment_id = seg_id

	var world_pts: Array[Vector2] = []
	var lx := start_lx
	var lz := start_lz
	var visited: Dictionary = {}
	for _step in MAX_TRACE_STEPS:
		var vkey := Vector2i(lx, lz)
		if visited.has(vkey):
			break
		visited[vkey] = true
		var hx := lx + 1
		var hz := lz + 1
		var mc := halo_index_to_macro(hx, hz, pcx, pcz)
		var wx := float(mc.x) * DRAIN_CELL + DRAIN_CELL * 0.5
		var wz := float(mc.y) * DRAIN_CELL + DRAIN_CELL * 0.5
		world_pts.append(Vector2(wx, wz))
		var acc := patch.flow_acc[lz * PATCH_INTERIOR + lx]
		if acc < MIN_ACC_CONTINUE:
			break
		var d := patch.flow_dir[hz * HALO_SIZE + hx]
		if d < 0:
			break
		var off := D8_OFFSETS[d]
		var nlx := lx + off.x
		var nlz := lz + off.y
		if nlx < 0 or nlx >= PATCH_INTERIOR or nlz < 0 or nlz >= PATCH_INTERIOR:
			break
		lx = nlx
		lz = nlz

	if world_pts.size() < 2:
		return seg

	_build_hydraulic_polyline(seg, world_pts, elev_fn, meander_fn)
	return seg


static func _build_hydraulic_polyline(seg: RiverSegment, spine_pts: Array[Vector2], elev_fn: Callable, meander_fn: Callable) -> void:
	var total_len := 0.0
	for i in range(spine_pts.size() - 1):
		total_len += spine_pts[i].distance_to(spine_pts[i + 1])
	if total_len < 1.0:
		return

	var samples: Array[Vector2] = []
	var dist := 0.0
	while dist <= total_len + 0.01:
		var p := _point_at_dist(spine_pts, dist)
		var tangent := _tangent_at_dist(spine_pts, dist)
		var perp := Vector2(-tangent.y, tangent.x)
		var mend: Variant = meander_fn.call(p.x, p.y)
		if mend is Vector2:
			p += perp * clampf(mend.x, -MEANDER_MAX, MEANDER_MAX)
		samples.append(p)
		dist += HYDRAULIC_SAMPLE_STEP

	if samples.is_empty():
		samples.append(spine_pts[0])

	seg.hydraulic_points = PackedVector2Array(samples)
	seg.water_levels.resize(samples.size())
	var wl_prev: float = float(elev_fn.call(samples[0].x, samples[0].y)) - DEPTH_AT_CENTER - BANK_LIFT
	seg.water_levels[0] = wl_prev
	for i in range(1, samples.size()):
		var raw: float = float(elev_fn.call(samples[i].x, samples[i].y))
		var dist_step: float = samples[i - 1].distance_to(samples[i])
		var slope: float = clampf((float(elev_fn.call(samples[i - 1].x, samples[i - 1].y)) - raw) / max(dist_step, 1.0), 0.0, 0.012)
		wl_prev = wl_prev - slope * dist_step
		seg.water_levels[i] = round(wl_prev * 2.0) / 2.0


static func _point_at_dist(pts: Array[Vector2], target: float) -> Vector2:
	var acc := 0.0
	for i in range(pts.size() - 1):
		var seg_len := pts[i].distance_to(pts[i + 1])
		if acc + seg_len >= target:
			var t: float = (target - acc) / max(seg_len, 0.001)
			return pts[i].lerp(pts[i + 1], t)
		acc += seg_len
	return pts[pts.size() - 1]


static func _tangent_at_dist(pts: Array[Vector2], target: float) -> Vector2:
	var acc := 0.0
	for i in range(pts.size() - 1):
		var seg_len := pts[i].distance_to(pts[i + 1])
		if acc + seg_len >= target:
			var d := pts[i + 1] - pts[i]
			if d.length_squared() < 0.001:
				return Vector2(1, 0)
			return d.normalized()
		acc += seg_len
	if pts.size() >= 2:
		var d2 := pts[pts.size() - 1] - pts[pts.size() - 2]
		if d2.length_squared() >= 0.001:
			return d2.normalized()
	return Vector2(1, 0)


static func query_nearest_segment(
	wx: float,
	wz: float,
	world_seed: int,
	elev_fn: Callable,
	meander_fn: Callable,
	trib_fn: Callable,
	ctx: RiverJobContext,
	global_cache: Dictionary,
	use_global: bool
) -> Dictionary:
	var mc := macro_cell(wx, wz)
	var pcx := patch_origin_for_macro(mc.x, mc.y).x
	var pcz := patch_origin_for_macro(mc.x, mc.y).y

	var best_dist := 999999.0
	var best_seg: RiverSegment = null
	var best_u := 0.0
	var best_tangent := Vector2(1, 0)

	var patch_offsets: Array[Vector2i] = [Vector2i(0, 0)]
	for pz_off in [-PATCH_INTERIOR, 0, PATCH_INTERIOR]:
		for px_off in [-PATCH_INTERIOR, 0, PATCH_INTERIOR]:
			if px_off == 0 and pz_off == 0:
				continue
			patch_offsets.append(Vector2i(px_off, pz_off))

	for pass_i in 2:
		for poff in patch_offsets:
			var opcx: int = pcx + poff.x
			var opcz: int = pcz + poff.y
			var dpatch := get_drainage_patch(opcx, opcz, world_seed, elev_fn, meander_fn, trib_fn, ctx, global_cache, use_global)
			if dpatch == null:
				continue
			for seg in dpatch.segments:
				if not seg is RiverSegment:
					continue
				var q := _dist_to_polyline(Vector2(wx, wz), seg)
				if q.dist < best_dist:
					best_dist = q.dist
					best_seg = seg
					best_u = q.u
					best_tangent = q.tangent
		if best_dist < CORRIDOR_QUERY_RADIUS * 0.85:
			break
		if pass_i == 0:
			patch_offsets = []
			for pz_off in [-PATCH_INTERIOR, 0, PATCH_INTERIOR]:
				for px_off in [-PATCH_INTERIOR, 0, PATCH_INTERIOR]:
					patch_offsets.append(Vector2i(px_off, pz_off))

	return {
		"segment": best_seg,
		"dist": best_dist,
		"u": best_u,
		"tangent": best_tangent,
	}


static func get_drainage_patch(
	pcx: int,
	pcz: int,
	world_seed: int,
	elev_fn: Callable,
	meander_fn: Callable,
	trib_fn: Callable,
	ctx: RiverJobContext,
	global_cache: Dictionary,
	use_global: bool
) -> DrainagePatch:
	var key := Vector2i(pcx, pcz)
	if ctx:
		ctx.patch_lookups += 1
		if ctx.patch_cache.has(key):
			ctx.patch_cache_hits += 1
			return ctx.patch_cache[key]
	elif use_global and global_cache.has(key):
		return global_cache[key]

	var build_cache: Dictionary = {}
	if ctx:
		build_cache = ctx.patch_cache
	elif use_global:
		build_cache = global_cache

	var patch := build_drainage_patch(pcx, pcz, world_seed, elev_fn, meander_fn, trib_fn, build_cache, true)
	if use_global and ctx == null:
		while global_cache.size() > 64:
			global_cache.erase(global_cache.keys()[0])
		global_cache[key] = patch
	return patch


static func _dist_to_polyline(p: Vector2, seg: RiverSegment) -> Dictionary:
	var pts := seg.hydraulic_points
	if pts.size() < 2:
		return {"dist": 999999.0, "u": 0.0, "tangent": Vector2(1, 0)}

	var total_len := 0.0
	for i in range(pts.size() - 1):
		total_len += pts[i].distance_to(pts[i + 1])

	var best_dist := 999999.0
	var best_u := 0.0
	var best_tangent := Vector2(1, 0)
	var acc_len := 0.0

	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var ab := b - a
		var seg_len := ab.length()
		if seg_len < 0.001:
			continue
		var t: float = clampf((p - a).dot(ab) / (seg_len * seg_len), 0.0, 1.0)
		var closest := a + ab * t
		var d := p.distance_to(closest)
		if d < best_dist:
			best_dist = d
			best_u = (acc_len + t * seg_len) / max(total_len, 0.001)
			best_tangent = ab / seg_len
		acc_len += seg_len

	return {"dist": best_dist, "u": best_u, "tangent": best_tangent}


static func interp_water_level(seg: RiverSegment, u: float) -> float:
	if seg.water_levels.is_empty():
		return 0.0
	if seg.water_levels.size() == 1:
		return seg.water_levels[0]
	var idx_f := u * float(seg.water_levels.size() - 1)
	var idx := int(floor(idx_f))
	idx = clampi(idx, 0, seg.water_levels.size() - 2)
	var frac := idx_f - float(idx)
	return lerpf(seg.water_levels[idx], seg.water_levels[idx + 1], frac)


static func stitch_test_local(up_cell: Vector2i, pcx: int, pcz: int) -> Vector2i:
	var halo_origin := Vector2i(pcx - 1, pcz - 1)
	var up_macro := halo_origin + up_cell
	var norigin := neighbor_patch_origin_for_up_cell(up_cell, pcx, pcz)
	return up_macro - norigin
