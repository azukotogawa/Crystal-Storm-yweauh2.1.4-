class_name MeshPlanCache
extends RefCounted
## Serializable mesh-plan cache (quads only — never GPU resources).
## Preferred on full column rebuild when WorldState mesh overlays are pristine
## for the chunk. Dig/build/feature/crystal terrain overlays force regenerate.

const PLAN_VERSION: int = 2
const MAGIC: String = "CSMP"
const CELLS: int = 16
const FLAG_FULL_WORLD: int = 1

static var _active = null

var world_seed: int = 0
var radius: int = 0
var min_cx: int = 0
var max_cx: int = 0
var min_cz: int = 0
var max_cz: int = 0
var full_world: bool = false
## When true, mesh plans live inside streamed WorldBake chunk packages (not _plans).
var streamed_from_bake: bool = false
## Vector2i -> Array of quad Dictionaries (CPU plan only) — monolith / non-streamed only.
var _plans: Dictionary = {}
var valid: bool = false
var last_error: String = ""
var last_bake_time_ms: int = 0
var last_load_time_ms: int = 0
var last_bytes: int = 0
var stats_hits: int = 0
var stats_misses: int = 0
var stats_hit_us: int = 0
var stats_miss_gen_us: int = 0
## Last try_get_plan decision (instrumentation only; does not change path).
var last_decision: Dictionary = {}
## Per-miss-reason counters.
var stats_reason: Dictionary = {}
## Full decision log when tracing (CRYSTALSTORM_MESH_PLAN_TRACE=1 or begin_trace).
var decision_log: Array = []
var _trace: bool = false
var rebuild_times_us: PackedInt64Array = PackedInt64Array()

const REASON_HIT := "hit"
const REASON_DISABLED := "other"
const REASON_CACHE_INVALID := "streaming_edge_case"
const REASON_MISSING_PLAN := "missing_plan"
const REASON_VERSION := "version_mismatch"
const REASON_CHECKSUM := "checksum_mismatch"
const REASON_OVERLAY := "overlay_dirty"
const REASON_HEIGHT := "height_delta_dirty"
const REASON_CRYSTAL := "crystal_terrain_dirty"
const REASON_NOT_FULL := "streaming_edge_case"
const REASON_OTHER := "other"


static func get_active():
	return _active


static func set_active(cache) -> void:
	_active = cache


static func clear_active() -> void:
	_active = null


static func ensure_active():
	if _active == null:
		_active = load("res://world/mesh_plan_cache.gd").new()
	return _active


static func enabled_from_env() -> bool:
	var raw := OS.get_environment("CRYSTALSTORM_MESH_PLAN_CACHE").strip_edges().to_lower()
	# Default ON. Set 0/false/off to force generate.
	if raw == "0" or raw == "false" or raw == "off":
		return false
	return true


func begin_trace() -> void:
	_trace = true
	decision_log.clear()
	reset_stats()
	rebuild_times_us = PackedInt64Array()


func end_trace() -> void:
	_trace = false


func is_tracing() -> bool:
	if _trace:
		return true
	var raw := OS.get_environment("CRYSTALSTORM_MESH_PLAN_TRACE").strip_edges().to_lower()
	return raw == "1" or raw == "true" or raw == "on"


func reset_stats() -> void:
	stats_hits = 0
	stats_misses = 0
	stats_hit_us = 0
	stats_miss_gen_us = 0
	stats_reason.clear()
	last_decision = {}


func clear_memory() -> void:
	_plans.clear()
	streamed_from_bake = false
	valid = false
	streamed_from_bake = false
	last_error = ""
	last_bytes = 0


func plan_dir_for(seed: int, rad: int, as_full: bool = false) -> String:
	# Use only as_full arg (not instance full_world) so load paths stay deterministic.
	if as_full:
		return "user://world_bakes/v2_s%d_full" % seed
	return "user://world_bakes/v2_s%d_r%d" % [seed, rad]


func plan_file_path(seed: int, rad: int, as_full: bool = false) -> String:
	return plan_dir_for(seed, rad, as_full).path_join("mesh_plans.v%d" % PLAN_VERSION)


func has_plan(coord: Vector2i) -> bool:
	return valid and _plans.has(coord)


func plan_count() -> int:
	if streamed_from_bake:
		var bake = load("res://world/world_bake_service.gd").get_active()
		if bake != null and bake.valid:
			return int(bake.expected_chunk_count())
	return _plans.size()


## True when frozen worker overlays have no mesh-input mutations for this chunk.
static func chunk_overlays_pristine(data) -> bool:
	return classify_overlay_dirt(data).is_empty()


## Returns first dirt reason string, or "" if pristine.
## Categories: height_delta_dirty | overlay_dirty | crystal_terrain_dirty
## Baked static vegetation feature tiles are pristine (part of world bake).
static func classify_overlay_dirt(data) -> String:
	return str(overlay_dirt_detail(data).get("reason", ""))


## True when a feature tile should invalidate the baked mesh plan (runtime-only).
static func _feature_tile_is_runtime_dirt(data, lx: int, lz: int, ft: int) -> bool:
	if ft < 0:
		return false
	# Baked vegetation installed from package remains pristine.
	if data.has_method("get_worker_feature_is_baked") and bool(data.get_worker_feature_is_baked(lx, lz)):
		return false
	return true


## Detailed overlay breakdown for instrumentation reports.
static func overlay_dirt_detail(data) -> Dictionary:
	var height_n := 0
	var build_n := 0
	var feature_n := 0
	var baked_feature_n := 0
	var crystal_n := 0
	if data == null or not data.has_method("has_worker_overlay_snapshot") \
			or not data.has_worker_overlay_snapshot():
		return {
			"height_n": 0, "build_n": 0, "feature_n": 0, "baked_feature_n": 0,
			"reason": REASON_OTHER,
		}
	var VT = load("res://helpers/voxel_types.gd")
	for lx in CELLS:
		for lz in CELLS:
			if absf(float(data.get_worker_height_delta(lx, lz))) > 0.0001:
				height_n += 1
			if int(data.get_worker_build_tile(lx, lz)) >= 0:
				build_n += 1
			if data.has_method("get_worker_feature_tile"):
				var ft: int = int(data.get_worker_feature_tile(lx, lz))
				if ft < 0:
					continue
				if data.has_method("get_worker_feature_is_baked") \
						and bool(data.get_worker_feature_is_baked(lx, lz)):
					baked_feature_n += 1
					continue
				feature_n += 1
				if VT != null and VT.has_method("is_crystal_tile") and bool(VT.is_crystal_tile(ft)):
					crystal_n += 1
	var reason := ""
	if crystal_n > 0:
		reason = REASON_CRYSTAL
	elif height_n > 0:
		reason = REASON_HEIGHT
	elif build_n > 0 or feature_n > 0:
		reason = REASON_OVERLAY
	return {
		"height_n": height_n,
		"build_n": build_n,
		"feature_n": feature_n,
		"baked_feature_n": baked_feature_n,
		"crystal_n": crystal_n,
		"reason": reason,
	}


## Build plans by running the real mesh stage host for each chunk (pristine WorldState).
func bake_plans(host, world, rad: int, seed: int = -1) -> Dictionary:
	return bake_plans_bounds(host, world, -rad, rad, -rad, rad, seed, false)


func bake_plans_bounds(
	host,
	world,
	p_min_cx: int,
	p_max_cx: int,
	p_min_cz: int,
	p_max_cz: int,
	seed: int = -1,
	as_full: bool = false
) -> Dictionary:
	if host == null or world == null:
		last_error = "bake_plans: missing host/world"
		valid = false
		return {"ok": false, "error": last_error}
	var t0 := Time.get_ticks_msec()
	var _WorldState = load("res://world/world_state.gd")
	var _ChunkData = load("res://chunks/chunk_data.gd")
	var prev_active = _WorldState.get_active()
	_WorldState.replace_active()
	min_cx = p_min_cx
	max_cx = p_max_cx
	min_cz = p_min_cz
	max_cz = p_max_cz
	full_world = as_full
	radius = maxi(absi(min_cx), absi(max_cx))
	world_seed = seed if seed >= 0 else (int(world.world_seed) if "world_seed" in world else 0)
	_plans.clear()
	var count := 0
	for cz in range(min_cz, max_cz + 1):
		for cx in range(min_cx, max_cx + 1):
			var coord := Vector2i(cx, cz)
			var data = _ChunkData.new(coord, world)
			data.capture_worker_snapshot()
			var bake = load("res://world/world_bake_service.gd").get_active()
			if bake != null and bake.has_method("try_apply_base_to_chunk_data") \
					and bake.try_apply_base_to_chunk_data(data):
				pass
			elif host.has_method("_generate_chunk"):
				host._generate_chunk(data)
			if data.has_method("_bind_macro_surface_if_needed"):
				data._bind_macro_surface_if_needed()
			var built: Dictionary = host._build_mesh(data)
			var quads: Array = built.get("quads", [])
			var plan: Array = []
			plan.resize(quads.size())
			for i in quads.size():
				var q: Dictionary = quads[i]
				plan[i] = q.duplicate(true)
			_plans[coord] = plan
			count += 1
	if prev_active != null:
		_WorldState.set_active(prev_active)
	else:
		_WorldState.replace_active()
	last_bake_time_ms = Time.get_ticks_msec() - t0
	valid = count > 0
	last_error = "" if valid else "empty plans"
	return {
		"ok": valid,
		"chunks": count,
		"bake_ms": last_bake_time_ms,
		"seed": world_seed,
		"radius": radius,
		"full_world": full_world,
		"bounds": {"min_cx": min_cx, "max_cx": max_cx, "min_cz": min_cz, "max_cz": max_cz},
	}


func save_plans(path: String = "") -> Dictionary:
	if not valid or _plans.is_empty():
		last_error = "save_plans: nothing to save"
		return {"ok": false, "error": last_error}
	var file_path := path if not path.is_empty() else plan_file_path(world_seed, radius, full_world)
	var dir_path := file_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
	var f := FileAccess.open(file_path, FileAccess.WRITE)
	if f == null:
		last_error = "save_plans: open failed"
		return {"ok": false, "error": last_error}
	f.store_buffer(MAGIC.to_utf8_buffer())
	f.store_32(PLAN_VERSION)
	f.store_64(world_seed)
	f.store_32(min_cx)
	f.store_32(max_cx)
	f.store_32(min_cz)
	f.store_32(max_cz)
	var flags: int = FLAG_FULL_WORLD if full_world else 0
	f.store_32(flags)
	f.store_32(_plans.size())
	var checksum: int = (
		PLAN_VERSION ^ world_seed ^ min_cx ^ max_cx ^ min_cz ^ max_cz ^ flags ^ _plans.size()
	)
	var keys: Array = _plans.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	for coord in keys:
		var c: Vector2i = coord
		var plan: Array = _plans[c]
		f.store_32(c.x)
		f.store_32(c.y)
		f.store_32(plan.size())
		checksum = checksum ^ c.x ^ c.y ^ plan.size()
		f.store_var(plan, false)
		checksum = checksum ^ _plan_checksum(plan)
	f.store_32(checksum)
	f.close()
	last_bytes = int(FileAccess.get_file_as_bytes(file_path).size()) if FileAccess.file_exists(file_path) else 0
	last_error = ""
	return {"ok": true, "path": file_path, "bytes": last_bytes, "checksum": checksum}


func load_plans(seed: int, rad: int, path: String = "") -> bool:
	if not path.is_empty():
		return _load_plans_file(path, seed)
	# Try full package then radius.
	if load_plans_for_bounds(seed, -rad, rad, -rad, rad, false):
		return true
	var legacy := "user://world_bakes/v1_s%d_r%d/mesh_plans.v1" % [seed, rad]
	return _load_plans_file(legacy, seed)


func load_plans_for_bounds(
	seed: int,
	p_min_cx: int,
	p_max_cx: int,
	p_min_cz: int,
	p_max_cz: int,
	as_full: bool
) -> bool:
	var path_full := plan_file_path(seed, 0, true)
	if as_full and FileAccess.file_exists(path_full):
		return _load_plans_file(path_full, seed)
	var rad := maxi(absi(p_min_cx), absi(p_max_cx))
	var path_r := plan_file_path(seed, rad, false)
	if FileAccess.file_exists(path_r):
		return _load_plans_file(path_r, seed)
	if FileAccess.file_exists(path_full):
		return _load_plans_file(path_full, seed)
	var legacy := "user://world_bakes/v1_s%d_r%d/mesh_plans.v1" % [seed, rad]
	if FileAccess.file_exists(legacy):
		return _load_plans_file(legacy, seed)
	last_error = "load_plans: missing for seed=%d" % seed
	valid = false
	return false


func _load_plans_file(file_path: String, seed: int) -> bool:
	var t0 := Time.get_ticks_msec()
	if not FileAccess.file_exists(file_path):
		last_error = "load_plans: missing %s" % file_path
		valid = false
		_plans.clear()
		return false
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		last_error = "load_plans: open failed"
		valid = false
		return false
	var magic := f.get_buffer(4).get_string_from_utf8()
	if magic != MAGIC:
		last_error = "load_plans: bad magic"
		valid = false
		f.close()
		return false
	var ver: int = int(f.get_32())
	if ver != 1 and ver != PLAN_VERSION:
		last_error = "load_plans: version mismatch got=%d" % ver
		valid = false
		f.close()
		return false
	var file_seed: int = int(f.get_64())
	if file_seed != seed:
		last_error = "load_plans: seed mismatch"
		valid = false
		f.close()
		return false
	var count: int = 0
	var checksum: int = 0
	_plans.clear()
	if ver == 1:
		var file_radius: int = int(f.get_32())
		count = int(f.get_32())
		min_cx = -file_radius
		max_cx = file_radius
		min_cz = -file_radius
		max_cz = file_radius
		radius = file_radius
		full_world = false
		checksum = 1 ^ file_seed ^ file_radius ^ count
	else:
		min_cx = int(f.get_32())
		max_cx = int(f.get_32())
		min_cz = int(f.get_32())
		max_cz = int(f.get_32())
		var flags: int = int(f.get_32())
		full_world = (flags & FLAG_FULL_WORLD) != 0
		radius = maxi(absi(min_cx), absi(max_cx))
		count = int(f.get_32())
		checksum = PLAN_VERSION ^ file_seed ^ min_cx ^ max_cx ^ min_cz ^ max_cz ^ flags ^ count
	if count <= 0 or count > 500000:
		last_error = "load_plans: bad count"
		valid = false
		f.close()
		return false
	for _i in count:
		var cx: int = int(f.get_32())
		var cz: int = int(f.get_32())
		var qn: int = int(f.get_32())
		checksum = checksum ^ cx ^ cz ^ qn
		var plan = f.get_var(false)
		if typeof(plan) != TYPE_ARRAY:
			last_error = "load_plans: plan not array"
			valid = false
			_plans.clear()
			f.close()
			return false
		if (plan as Array).size() != qn:
			last_error = "load_plans: quad count mismatch"
			valid = false
			_plans.clear()
			f.close()
			return false
		checksum = checksum ^ _plan_checksum(plan)
		_plans[Vector2i(cx, cz)] = plan
	if f.get_position() + 4 > f.get_length():
		last_error = "load_plans: missing checksum"
		valid = false
		_plans.clear()
		f.close()
		return false
	var file_cs: int = int(f.get_32())
	f.close()
	if file_cs != checksum:
		last_error = "load_plans: checksum mismatch"
		valid = false
		_plans.clear()
		return false
	world_seed = file_seed
	valid = true
	last_load_time_ms = Time.get_ticks_msec() - t0
	last_bytes = int(FileAccess.get_file_as_bytes(file_path).size())
	last_error = ""
	return true


func _plan_checksum(plan: Array) -> int:
	var cs: int = plan.size()
	# Sample endpoints + mid for speed; full XOR of face codes + positions.
	for i in plan.size():
		var q: Dictionary = plan[i]
		cs = cs ^ int(q.get("x", 0)) ^ int(q.get("z", 0)) ^ int(q.get("face_code", 0)) \
			^ int(q.get("type", 0)) ^ int(float(q.get("y", 0.0)) * 100.0)
	return cs


## Try to return cached plan quads. Empty array = miss (caller generates).
## Side effect: fills last_decision + optional decision_log (trace).
func try_get_plan(data) -> Array:
	var decision: Dictionary = evaluate_plan_decision(data, true)
	last_decision = decision
	if bool(decision.get("hit", false)):
		return decision.get("plan", []) as Array
	return []


## Full decision diagnosis. When apply_stats=true, updates hit/miss counters (for real path).
## Order matches original try_get_plan: enabled → valid → overlays → plan fetch.
func evaluate_plan_decision(data, apply_stats: bool = false) -> Dictionary:
	var coord := Vector2i.ZERO
	if data != null and "position" in data:
		coord = data.position
	var dec := {
		"coord_x": coord.x,
		"coord_z": coord.y,
		"package_exists": false,
		"package_in_index": false,
		"package_resident": false,
		"mesh_plan_exists_in_package": false,
		"mesh_plan_loaded": false,
		"plan_quad_count": 0,
		"cache_hit": false,
		"hit": false,
		"mesh_source": "rebuild",
		"rebuild_reason": REASON_OTHER,
		"rebuild_triggered": true,
		"overlay_detail": {},
		"streamed_from_bake": streamed_from_bake,
		"cache_valid": valid,
		"plan": [],
		"detail": "",
	}
	var bake = load("res://world/world_bake_service.gd").get_active()
	if bake != null and bake.valid:
		if bake.has_method("coord_in_package") and bake.coord_in_package(coord):
			dec["package_in_index"] = true
			dec["package_exists"] = true
		if bake.has_method("is_resident"):
			dec["package_resident"] = bool(bake.is_resident(coord))

	if not enabled_from_env():
		dec["rebuild_reason"] = REASON_DISABLED
		dec["detail"] = "mesh_plan_cache_disabled"
		_finish_decision(dec, apply_stats, false, 0)
		return dec
	if not valid or data == null:
		dec["rebuild_reason"] = REASON_CACHE_INVALID
		dec["detail"] = "cache_invalid_or_null_data"
		_finish_decision(dec, apply_stats, false, 0)
		return dec

	# Same gate as production: any frozen mesh-input overlay rejects the baked plan.
	var dirt: Dictionary = overlay_dirt_detail(data)
	dec["overlay_detail"] = dirt
	var dirt_reason: String = str(dirt.get("reason", ""))
	if not dirt_reason.is_empty():
		dec["rebuild_reason"] = dirt_reason
		dec["detail"] = "feature_n=%d build_n=%d height_n=%d" % [
			int(dirt.get("feature_n", 0)),
			int(dirt.get("build_n", 0)),
			int(dirt.get("height_n", 0)),
		]
		# Plan may still exist — report presence without using it.
		_fill_plan_presence(dec, bake, coord)
		_finish_decision(dec, apply_stats, false, 0)
		return dec

	var t0 := Time.get_ticks_usec()
	var plan: Array = []
	if streamed_from_bake:
		if bake != null and bake.has_method("get_mesh_plan"):
			plan = bake.get_mesh_plan(coord)
	elif _plans.has(coord):
		plan = _plans[coord]
	if not plan.is_empty():
		dec["mesh_plan_exists_in_package"] = true
		dec["mesh_plan_loaded"] = true
		dec["plan_quad_count"] = plan.size()
	if plan.is_empty():
		dec["rebuild_reason"] = REASON_MISSING_PLAN
		dec["detail"] = "empty_plan_after_lookup streamed=%s" % str(streamed_from_bake)
		_fill_plan_presence(dec, bake, coord)
		_finish_decision(dec, apply_stats, false, 0)
		return dec

	var out: Array = []
	out.resize(plan.size())
	for i in plan.size():
		var q: Dictionary = plan[i]
		out[i] = q.duplicate(true)
	var us: int = Time.get_ticks_usec() - t0
	dec["hit"] = true
	dec["cache_hit"] = true
	dec["mesh_source"] = "cache"
	dec["rebuild_triggered"] = false
	dec["rebuild_reason"] = REASON_HIT
	dec["plan"] = out
	dec["plan_quad_count"] = out.size()
	dec["mesh_plan_exists_in_package"] = true
	dec["mesh_plan_loaded"] = true
	_finish_decision(dec, apply_stats, true, us)
	return dec


func _fill_plan_presence(dec: Dictionary, bake, coord: Vector2i) -> void:
	if bake == null or not bake.valid:
		return
	if not bake.has_method("get_mesh_plan"):
		return
	if bake.has_method("coord_in_package") and not bake.coord_in_package(coord):
		return
	# Idempotent if already resident from stream prefetch.
	var plan: Array = bake.get_mesh_plan(coord)
	dec["mesh_plan_exists_in_package"] = not plan.is_empty()
	dec["mesh_plan_loaded"] = not plan.is_empty()
	dec["plan_quad_count"] = plan.size()
	if bake.has_method("is_resident"):
		dec["package_resident"] = bool(bake.is_resident(coord))


func _finish_decision(dec: Dictionary, apply_stats: bool, hit: bool, hit_us: int) -> void:
	if apply_stats:
		if hit:
			stats_hits += 1
			stats_hit_us += hit_us
		else:
			stats_misses += 1
			var r: String = str(dec.get("rebuild_reason", REASON_OTHER))
			stats_reason[r] = int(stats_reason.get(r, 0)) + 1
	if is_tracing():
		var log_entry: Dictionary = dec.duplicate(true)
		log_entry.erase("plan")  # don't retain full quad arrays in log
		decision_log.append(log_entry)


func record_rebuild_time(us: int) -> void:
	if us < 0:
		return
	rebuild_times_us.append(us)
	stats_miss_gen_us += us


func record_miss_generate_us(us: int) -> void:
	# Kept for callers; prefer record_rebuild_time after decision already counted miss.
	stats_miss_gen_us += us


func summary_report() -> Dictionary:
	var total: int = stats_hits + stats_misses
	var hit_rate: float = 0.0
	var rebuild_rate: float = 0.0
	if total > 0:
		hit_rate = 100.0 * float(stats_hits) / float(total)
		rebuild_rate = 100.0 * float(stats_misses) / float(total)
	var avg_rebuild: float = 0.0
	var worst_rebuild: int = 0
	var sum_r: int = 0
	for v in rebuild_times_us:
		var iv: int = int(v)
		sum_r += iv
		if iv > worst_rebuild:
			worst_rebuild = iv
	if rebuild_times_us.size() > 0:
		avg_rebuild = float(sum_r) / float(rebuild_times_us.size())
	return {
		"total_decisions": total,
		"hits": stats_hits,
		"misses": stats_misses,
		"hit_rate_pct": hit_rate,
		"rebuild_rate_pct": rebuild_rate,
		"avg_rebuild_us": avg_rebuild,
		"avg_rebuild_ms": avg_rebuild / 1000.0,
		"worst_rebuild_us": worst_rebuild,
		"worst_rebuild_ms": float(worst_rebuild) / 1000.0,
		"reasons": stats_reason.duplicate(),
		"streamed_from_bake": streamed_from_bake,
		"cache_valid": valid,
		"decision_log_n": decision_log.size(),
	}


func invalidate_chunk(coord: Vector2i) -> void:
	_plans.erase(coord)


func delete_plans(seed: int, rad: int) -> void:
	for as_full in [true, false]:
		var file_path := plan_file_path(seed, rad, as_full)
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	var legacy := "user://world_bakes/v1_s%d_r%d/mesh_plans.v1" % [seed, rad]
	if FileAccess.file_exists(legacy):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy))


func corrupt_file(seed: int, rad: int) -> bool:
	var file_path := plan_file_path(seed, rad, full_world)
	if not FileAccess.file_exists(file_path):
		file_path = plan_file_path(seed, rad, false)
	if not FileAccess.file_exists(file_path):
		return false
	var bytes := FileAccess.get_file_as_bytes(file_path)
	if bytes.size() < 8:
		return false
	bytes[bytes.size() - 1] = bytes[bytes.size() - 1] ^ 0xFF
	var f := FileAccess.open(file_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.close()
	return true


func write_version_mismatch_stub(seed: int, rad: int) -> String:
	var file_path := plan_file_path(seed, rad)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(file_path.get_base_dir()))
	var f := FileAccess.open(file_path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_buffer(MAGIC.to_utf8_buffer())
	f.store_32(PLAN_VERSION + 77)
	f.store_64(seed)
	f.store_32(rad)
	f.store_32(0)
	f.store_32(0)
	f.close()
	return file_path


## Bootstrap: load plans if present; if column bake is valid for same seed/radius and host
## is available, auto-bake+save plans (production default — no special env required).
## WorldBakeService.bootstrap_for_world(host=…) is the preferred entry (co-emits with columns).
func bootstrap_for_world(host, world, rad: int = -1, force_bake: bool = false) -> Dictionary:
	if world == null:
		return {"ok": false, "error": "no world"}
	if not enabled_from_env() and not force_bake:
		clear_memory()
		return {"ok": true, "mode": "disabled"}
	var seed: int = int(world.world_seed) if "world_seed" in world else 0
	var r := rad
	if r < 0:
		var wb = load("res://world/world_bake_service.gd")
		r = wb.default_radius_from_env() if wb else 6
	if not force_bake and load_plans(seed, r):
		return {"ok": true, "mode": "loaded", "chunks": plan_count(), "bytes": last_bytes}
	# Prefer WorldBakeService.ensure_mesh_plans when column bake is already active.
	var wb_script = load("res://world/world_bake_service.gd")
	var bake = wb_script.get_active() if wb_script else null
	if bake != null and bool(bake.valid) and int(bake.world_seed) == seed \
			and int(bake.radius) == r and host != null:
		var ensured: Dictionary = bake.ensure_mesh_plans(host, world)
		if bool(ensured.get("ok", false)) and str(ensured.get("mode", "")) in ["loaded", "baked"]:
			return ensured
	var bake_new := force_bake
	var raw := OS.get_environment("CRYSTALSTORM_MESH_PLAN_BAKE_ON_NEW").strip_edges().to_lower()
	if raw == "1" or raw == "true" or raw == "on":
		bake_new = true
	# Default: bake plans whenever host is available and column bake path is enabled.
	if not bake_new and host != null and raw.is_empty():
		bake_new = true
	if raw == "0" or raw == "false" or raw == "off":
		bake_new = force_bake
	if bake_new and host != null:
		var baked: Dictionary = bake_plans(host, world, r, seed)
		if not bool(baked.get("ok", false)):
			return baked
		var saved: Dictionary = save_plans()
		return {
			"ok": bool(saved.get("ok", false)),
			"mode": "baked",
			"chunks": plan_count(),
			"bytes": last_bytes,
			"bake_ms": last_bake_time_ms,
		}
	clear_memory()
	return {"ok": true, "mode": "miss", "seed": seed, "radius": r}
