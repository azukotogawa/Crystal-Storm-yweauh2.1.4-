class_name WorldBakeService
extends RefCounted
## Streamed finite-world bake for Engine 1.0.
##
## Disk layout (v4):
##   user://world_bakes/v4_s{seed}_{full|rN}/
##     world.index          — lightweight bounds + flags (only thing loaded at startup)
##     chunks/cx_cz.chk     — terrain columns + mesh plan + baked vegetation
##     static_meta.json     — optional non-authoritative placement hints
##
## Runtime memory holds only the index + packages for currently streamed chunks.
## Baked vegetation is installed into WorldState when a chunk becomes resident.
## WorldState remains sole authority for digs/builds/crystal/session mutations
## (feature_cleared tombstones prevent re-applying destroyed plants).
## Never procedural-generates static terrain/vegetation for coords covered by a valid index.

const _WorldSettings = preload("res://config/world_settings.gd")

## v4: chunk packages embed baked vegetation (static plants) next to terrain + mesh plan.
const BAKE_VERSION: int = 4
const MAGIC: String = "CSWB"
const CHUNK_MAGIC: String = "CSCH"
const INDEX_MAGIC: String = "CSWI"
const CELLS: int = 16
const CELLS2: int = CELLS * CELLS
const SMOKE_DEFAULT_RADIUS: int = 2
const FLAG_FULL_WORLD: int = 1
const FLAG_STREAMED: int = 2
const FLAG_VEGETATION: int = 4

static var _active = null

var world_seed: int = 0
var min_cx: int = 0
var max_cx: int = 0
var min_cz: int = 0
var max_cz: int = 0
var full_world: bool = false
var radius: int = SMOKE_DEFAULT_RADIUS
var streamed: bool = true
var valid: bool = false
var last_error: String = ""
var last_bake_time_ms: int = 0
var last_load_time_ms: int = 0
var last_save_time_ms: int = 0
var last_bake_bytes: int = 0
var last_column_source: String = ""
var last_static_meta_bytes: int = 0
var package_dir: String = ""
## True when loaded/baked packages include vegetation payloads (v4+).
var vegetation_baked: bool = false
var last_vegetation_entries: int = 0
var last_vegetation_bake_ms: int = 0

## Resident only: Vector2i -> { surface, tiles, plan, vegetation }
var _resident: Dictionary = {}
## Optional monolith fallback (legacy tests): full in-memory map
var _chunks: Dictionary = {}

var stats_bake_hits: int = 0
var stats_generate_hits: int = 0
var stats_column_us_bake: int = 0
var stats_column_us_generate: int = 0
var stats_column_samples_bake: int = 0
var stats_column_samples_generate: int = 0
var stats_blocked_generate: int = 0
var stats_disk_reads: int = 0
var stats_disk_read_us: int = 0
var stats_releases: int = 0
var stats_missing_package_errors: int = 0
## Runtime isolation counters (baked world must stay at 0 for in-package cells).
var stats_generate_chunk_calls: int = 0
var stats_halo_noise_calls: int = 0
var stats_runtime_noise_height_calls: int = 0
var stats_halo_bake_hits: int = 0
var stats_halo_deferred: int = 0
var stats_dirty_bake_hits: int = 0


static func get_active():
	return _active


static func set_active(svc) -> void:
	_active = svc


static func clear_active() -> void:
	_active = null


static func ensure_active():
	if _active == null:
		_active = load("res://world/world_bake_service.gd").new()
	return _active


func reset_runtime_gen_stats() -> void:
	stats_generate_chunk_calls = 0
	stats_halo_noise_calls = 0
	stats_runtime_noise_height_calls = 0
	stats_halo_bake_hits = 0
	stats_halo_deferred = 0
	stats_dirty_bake_hits = 0
	stats_generate_hits = 0
	stats_blocked_generate = 0


func runtime_gen_stats() -> Dictionary:
	return {
		"generate_chunk_calls": stats_generate_chunk_calls,
		"halo_noise_calls": stats_halo_noise_calls,
		"runtime_noise_height_calls": stats_runtime_noise_height_calls,
		"halo_bake_hits": stats_halo_bake_hits,
		"halo_deferred": stats_halo_deferred,
		"dirty_bake_hits": stats_dirty_bake_hits,
		"generate_hits": stats_generate_hits,
		"blocked_generate": stats_blocked_generate,
	}


## World column → chunk coord (SIZE cells per chunk side).
static func world_to_chunk_coord(wx: int, wz: int) -> Vector2i:
	return Vector2i(int(floor(float(wx) / float(CELLS))), int(floor(float(wz) / float(CELLS))))


static func world_to_local(wx: int, wz: int) -> Vector2i:
	var cx: int = int(floor(float(wx) / float(CELLS)))
	var cz: int = int(floor(float(wz) / float(CELLS)))
	return Vector2i(wx - cx * CELLS, wz - cz * CELLS)


func covers_world_cell(wx: int, wz: int) -> bool:
	if not valid:
		return false
	return coord_in_package(world_to_chunk_coord(wx, wz))


## Sample immutable baked base for a world column. Loads package if needed (main thread).
## Returns {} if outside package or package unavailable (caller must not noise for covered cells).
func sample_world_base(wx: int, wz: int) -> Dictionary:
	if not valid:
		return {}
	var coord: Vector2i = world_to_chunk_coord(wx, wz)
	if not coord_in_package(coord):
		return {}
	var local: Vector2i = world_to_local(wx, wz)
	return sample_base(coord, local.x, local.y)


## Compose quantized surface from baked base + WorldState height delta (world units).
static func compose_surface_height(base_h: float, height_delta: float) -> float:
	var layer: float = maxf(_WorldSettings.get_active().layer_height(), 0.001)
	var h: float = base_h + height_delta
	return round(h / layer) * layer


## True when a noise height sample for this world cell would violate bake isolation.
func should_count_runtime_noise_height(wx: float, wz: float) -> bool:
	if not valid or not bake_enabled_from_env():
		return false
	return covers_world_cell(int(floor(wx)), int(floor(wz)))


func note_generate_chunk_call() -> void:
	stats_generate_chunk_calls += 1


func note_halo_noise_call() -> void:
	stats_halo_noise_calls += 1


func note_runtime_noise_height_call() -> void:
	stats_runtime_noise_height_calls += 1


func note_halo_bake_hit() -> void:
	stats_halo_bake_hits += 1


func note_halo_deferred() -> void:
	stats_halo_deferred += 1


func note_dirty_bake_hit() -> void:
	stats_dirty_bake_hits += 1


static func full_world_chunk_bounds() -> Dictionary:
	var half_x: int = 1024
	var half_z: int = 1024
	var wb = load("res://helpers/world_border.gd")
	if wb:
		half_x = int(wb.PLAYABLE_HALF_X)
		half_z = int(wb.PLAYABLE_HALF_Z)
	var min_c := Vector2i(
		int(floor(-float(half_x) / float(CELLS))),
		int(floor(-float(half_z) / float(CELLS)))
	)
	var max_c := Vector2i(
		int(floor(float(half_x - 1) / float(CELLS))),
		int(floor(float(half_z - 1) / float(CELLS)))
	)
	var span_x: int = max_c.x - min_c.x + 1
	var span_z: int = max_c.y - min_c.y + 1
	return {
		"min_cx": min_c.x,
		"max_cx": max_c.x,
		"min_cz": min_c.y,
		"max_cz": max_c.y,
		"chunks": span_x * span_z,
		"span_x": span_x,
		"span_z": span_z,
		"half_x": half_x,
		"half_z": half_z,
	}


## Production playable map side length in chunks (e.g. 128 for PLAYABLE_HALF=1024, CELLS=16).
static func production_chunk_side() -> int:
	var b: Dictionary = full_world_chunk_bounds()
	return int(b.get("span_x", 128))


## Production default: full playable world. Optional test overrides only:
##   CRYSTALSTORM_FULL_WORLD_BAKE=0 or CRYSTALSTORM_BAKE_RADIUS=<n> for smoke/CI.
static func use_full_world_from_env() -> bool:
	var raw := OS.get_environment("CRYSTALSTORM_FULL_WORLD_BAKE").strip_edges().to_lower()
	if raw == "0" or raw == "false" or raw == "off":
		return false
	var rad := OS.get_environment("CRYSTALSTORM_BAKE_RADIUS").strip_edges()
	if not rad.is_empty():
		return false
	# Empty / unset / on → production full world (no env required for players).
	return true


static func smoke_radius_from_env() -> int:
	var raw := OS.get_environment("CRYSTALSTORM_BAKE_RADIUS").strip_edges()
	if raw.is_empty():
		return SMOKE_DEFAULT_RADIUS
	return maxi(raw.to_int(), 0)


static func default_radius_from_env() -> int:
	if use_full_world_from_env():
		var b: Dictionary = full_world_chunk_bounds()
		return maxi(absi(int(b.min_cx)), absi(int(b.max_cx)))
	return smoke_radius_from_env()


## Always rebuild missing/invalid bakes for players. Tests may set CRYSTALSTORM_BAKE_ON_NEW=0.
static func bake_on_new_from_env() -> bool:
	var raw := OS.get_environment("CRYSTALSTORM_BAKE_ON_NEW").strip_edges().to_lower()
	if raw == "0" or raw == "false" or raw == "off":
		return false
	return true


## World bake is always on for production. Tests may set CRYSTALSTORM_WORLD_BAKE=0.
static func bake_enabled_from_env() -> bool:
	var raw := OS.get_environment("CRYSTALSTORM_WORLD_BAKE").strip_edges().to_lower()
	if raw == "0" or raw == "false" or raw == "off":
		return false
	return true


static func is_chunk_outside_finite_world(coord: Vector2i) -> bool:
	var b: Dictionary = full_world_chunk_bounds()
	return (
		coord.x < int(b.min_cx) or coord.x > int(b.max_cx)
		or coord.y < int(b.min_cz) or coord.y > int(b.max_cz)
	)


## Interpret unsigned 32-bit FileAccess value as signed int32.
static func _i32(u: int) -> int:
	if u > 2147483647:
		return u - 4294967296
	return u


## Mask to unsigned 32-bit for store_32 / get_32 checksum compare.
static func _u32(v: int) -> int:
	return int(v) & 0xFFFFFFFF


func reset_stats() -> void:
	stats_bake_hits = 0
	stats_generate_hits = 0
	stats_column_us_bake = 0
	stats_column_us_generate = 0
	stats_column_samples_bake = 0
	stats_column_samples_generate = 0
	stats_blocked_generate = 0
	stats_disk_reads = 0
	stats_disk_read_us = 0
	stats_releases = 0
	stats_missing_package_errors = 0
	last_column_source = ""


func clear_memory() -> void:
	_resident.clear()
	_chunks.clear()
	valid = false
	last_error = ""
	world_seed = 0
	radius = SMOKE_DEFAULT_RADIUS
	full_world = false
	streamed = true
	min_cx = 0
	max_cx = 0
	min_cz = 0
	max_cz = 0
	last_bake_bytes = 0
	last_static_meta_bytes = 0
	package_dir = ""
	vegetation_baked = false
	last_vegetation_entries = 0
	last_vegetation_bake_ms = 0


func bounds_dict() -> Dictionary:
	return {
		"min_cx": min_cx,
		"max_cx": max_cx,
		"min_cz": min_cz,
		"max_cz": max_cz,
		"full_world": full_world,
		"streamed": streamed,
		"chunks": expected_chunk_count(),
		"resident": _resident.size(),
	}


func coord_in_package(coord: Vector2i) -> bool:
	return (
		coord.x >= min_cx and coord.x <= max_cx
		and coord.y >= min_cz and coord.y <= max_cz
	)


func bake_dir_for(seed: int, rad: int = -1, as_full: bool = false) -> String:
	if as_full:
		return "user://world_bakes/v%d_s%d_full" % [BAKE_VERSION, seed]
	var r := rad if rad >= 0 else radius
	return "user://world_bakes/v%d_s%d_r%d" % [BAKE_VERSION, seed, r]


func bake_file_path(seed: int, rad: int = -1, as_full: bool = false) -> String:
	# Index path for streamed packages (replaces monolith world.bake).
	return bake_dir_for(seed, rad, as_full).path_join("world.index")


func chunk_package_path(coord: Vector2i) -> String:
	return package_dir.path_join("chunks").path_join("%d_%d.chk" % [coord.x, coord.y])


func has_chunk(coord: Vector2i) -> bool:
	## Index membership (not necessarily resident in RAM).
	return valid and coord_in_package(coord)


func is_resident(coord: Vector2i) -> bool:
	return _resident.has(coord) or _chunks.has(coord)


func resident_count() -> int:
	return _resident.size() + _chunks.size()


func chunk_count() -> int:
	## Covered by index (world size), not resident RAM count.
	if valid:
		return expected_chunk_count()
	return _chunks.size()


func covered_coords() -> Array:
	var out: Array = []
	if not valid:
		return _chunks.keys()
	for cz in range(min_cz, max_cz + 1):
		for cx in range(min_cx, max_cx + 1):
			out.append(Vector2i(cx, cz))
	return out


func expected_chunk_count() -> int:
	return (max_cx - min_cx + 1) * (max_cz - min_cz + 1)


## Block procedural generate for any coord covered by a valid bake index.
func should_block_procedural_generate(coord: Vector2i) -> bool:
	if not bake_enabled_from_env():
		return false
	if not valid:
		return false
	return coord_in_package(coord)


## Assess a loaded bake for production readiness. Does not rebuild.
## Returns { ok, reasons: PackedStringArray, mesh_plans_ok, vegetation_ok, size_label, chunks, version }.
func validate_loaded_bake(expected_seed: int, require_full: bool = true) -> Dictionary:
	var reasons: PackedStringArray = PackedStringArray()
	if not valid:
		reasons.append("index_not_valid")
		return _validation_result(false, reasons, false, false, 0)
	if world_seed != expected_seed and expected_seed >= 0:
		reasons.append("seed_mismatch got=%d want=%d" % [world_seed, expected_seed])
	# Production requires current schema with vegetation.
	if BAKE_VERSION >= 4:
		# Index must be current major version (v4). v3 loads for migration but is invalid for production.
		var index_path := package_dir.path_join("world.index")
		var ver_on_disk := _read_index_version(package_dir)
		if ver_on_disk > 0 and ver_on_disk != BAKE_VERSION:
			reasons.append("bake_version got=%d want=%d" % [ver_on_disk, BAKE_VERSION])
	if require_full:
		var b: Dictionary = full_world_chunk_bounds()
		if not full_world:
			reasons.append("not_full_world")
		if (
			min_cx != int(b.min_cx) or max_cx != int(b.max_cx)
			or min_cz != int(b.min_cz) or max_cz != int(b.max_cz)
		):
			reasons.append(
				"dimensions got=%d..%d x %d..%d want=%d..%d x %d..%d"
				% [min_cx, max_cx, min_cz, max_cz, int(b.min_cx), int(b.max_cx), int(b.min_cz), int(b.max_cz)]
			)
	if not streamed:
		reasons.append("not_streamed")
	if package_dir.is_empty():
		reasons.append("missing_package_dir")
	if not vegetation_baked:
		reasons.append("vegetation_missing")
	# Package integrity + mesh plans (sample corners + origin).
	var plan_ok := true
	var integrity_ok := true
	var samples: Array = _validation_sample_coords()
	var with_plan := 0
	for c_variant in samples:
		var c: Vector2i = c_variant
		if not FileAccess.file_exists(chunk_package_path(c)):
			integrity_ok = false
			reasons.append("missing_package %s" % str(c))
			continue
		var pack: Dictionary = _read_chunk_package(c)
		if pack.is_empty():
			integrity_ok = false
			reasons.append("corrupt_package %s (%s)" % [str(c), last_error])
			continue
		var plan: Array = pack.get("plan", [])
		if plan.is_empty():
			plan_ok = false
		else:
			with_plan += 1
	_resident.clear()
	if samples.size() > 0 and with_plan == 0:
		plan_ok = false
		if "mesh_plans_empty" not in reasons:
			reasons.append("mesh_plans_empty")
	elif not plan_ok:
		reasons.append("mesh_plans_incomplete")
	if not integrity_ok and "package_integrity" not in reasons:
		reasons.append("package_integrity")
	var ok: bool = reasons.is_empty()
	var span_x: int = max_cx - min_cx + 1
	var span_z: int = max_cz - min_cz + 1
	return {
		"ok": ok,
		"reasons": reasons,
		"mesh_plans_ok": plan_ok and integrity_ok,
		"vegetation_ok": vegetation_baked,
		"size_label": "%dx%d" % [span_x, span_z],
		"chunks": expected_chunk_count(),
		"version": BAKE_VERSION,
		"seed": world_seed,
	}


func _validation_result(
	ok: bool, reasons: PackedStringArray, mesh_ok: bool, veg_ok: bool, chunks: int
) -> Dictionary:
	return {
		"ok": ok,
		"reasons": reasons,
		"mesh_plans_ok": mesh_ok,
		"vegetation_ok": veg_ok,
		"size_label": "0x0",
		"chunks": chunks,
		"version": BAKE_VERSION,
		"seed": world_seed,
	}


func _validation_sample_coords() -> Array:
	if not valid:
		return []
	var out: Array = []
	var candidates: Array = [
		Vector2i(min_cx, min_cz),
		Vector2i(max_cx, min_cz),
		Vector2i(min_cx, max_cz),
		Vector2i(max_cx, max_cz),
		Vector2i(0, 0),
		Vector2i(mini(maxi(0, min_cx), max_cx), mini(maxi(0, min_cz), max_cz)),
	]
	var seen: Dictionary = {}
	for c_variant in candidates:
		var c: Vector2i = c_variant
		if not coord_in_package(c):
			continue
		if seen.has(c):
			continue
		seen[c] = true
		out.append(c)
	return out


func _read_index_version(dir: String) -> int:
	var index_path := dir.path_join("world.index")
	if not FileAccess.file_exists(index_path):
		return -1
	var f := FileAccess.open(index_path, FileAccess.READ)
	if f == null:
		return -1
	var magic := f.get_buffer(4).get_string_from_utf8()
	if magic != INDEX_MAGIC and magic != MAGIC:
		f.close()
		return -1
	var ver: int = int(f.get_32())
	f.close()
	return ver


func log_valid_bake(validation: Dictionary) -> void:
	print("[WorldBake] Valid bake found")
	print("version=%d" % int(validation.get("version", BAKE_VERSION)))
	print("size=%s" % str(validation.get("size_label", "")))
	print("chunks=%d" % int(validation.get("chunks", expected_chunk_count())))
	print("mesh_plans=%s" % ("valid" if bool(validation.get("mesh_plans_ok", false)) else "invalid"))
	print("vegetation=%s" % ("valid" if bool(validation.get("vegetation_ok", false)) else "invalid"))


func log_invalid_bake(reasons: PackedStringArray) -> void:
	print("[WorldBake] Bake invalid — rebuilding...")
	if reasons.is_empty():
		print("reason=missing_or_unreadable")
	else:
		for r in reasons:
			print("reason=%s" % str(r))


func bootstrap_for_world(world, force_bake: bool = false, host = null) -> Dictionary:
	if world == null:
		return {"ok": false, "error": "no world"}
	if not bake_enabled_from_env() and not force_bake:
		clear_memory()
		return {"ok": true, "mode": "disabled"}
	var seed: int = int(world.world_seed) if "world_seed" in world else 0
	set_active(self)
	var want_full := use_full_world_from_env()
	var loaded := false
	if not force_bake:
		loaded = load_bake_for_seed(seed, want_full)
	var validation: Dictionary = {}
	if loaded:
		validation = validate_loaded_bake(seed, want_full)
		# Plans incomplete can be repaired without full rebuild.
		if bool(validation.get("ok", false)):
			var plan_info: Dictionary = ensure_mesh_plans(host, world)
			# Re-validate mesh plan flag after optional one-shot repair.
			if str(plan_info.get("mode", "")) == "repaired":
				validation = validate_loaded_bake(seed, want_full)
			if bool(validation.get("ok", false)):
				log_valid_bake(validation)
				return {
					"ok": true,
					"mode": "loaded",
					"seed": seed,
					"full_world": full_world,
					"streamed": streamed,
					"bounds": bounds_dict(),
					"chunks": chunk_count(),
					"resident": resident_count(),
					"mesh_plan": plan_info,
					"validation": validation,
				}
			# Repair failed integrity → fall through to rebuild.
			var reasons2: PackedStringArray = validation.get("reasons", PackedStringArray())
			log_invalid_bake(reasons2)
		else:
			# Only mesh-plan issues → try repair before full rebuild.
			var reasons: PackedStringArray = validation.get("reasons", PackedStringArray())
			var only_plans := _reasons_only_mesh_plan(reasons)
			if only_plans and host != null:
				print("[WorldBake] Mesh plans incomplete — repairing once and writing to disk...")
				var plan_info2: Dictionary = ensure_mesh_plans(host, world, true)
				validation = validate_loaded_bake(seed, want_full)
				if bool(validation.get("ok", false)):
					log_valid_bake(validation)
					return {
						"ok": true,
						"mode": "loaded",
						"seed": seed,
						"full_world": full_world,
						"streamed": streamed,
						"bounds": bounds_dict(),
						"chunks": chunk_count(),
						"resident": resident_count(),
						"mesh_plan": plan_info2,
						"validation": validation,
						"repaired_plans": true,
					}
			log_invalid_bake(reasons)
	else:
		var miss_reasons: PackedStringArray = PackedStringArray()
		if last_error.is_empty():
			miss_reasons.append("no_bake_for_seed")
		else:
			miss_reasons.append(last_error)
		log_invalid_bake(miss_reasons)

	if force_bake or bake_on_new_from_env():
		# Production auto-bake: full world unless smoke radius override is set.
		var rad: int = -1
		if not want_full:
			rad = smoke_radius_from_env()
		var baked: Dictionary = bake_world(world, rad, host)
		if not bool(baked.get("ok", false)):
			return baked
		var saved: Dictionary = save_bake()
		# One-shot plan refresh for live town/ruin stamps after offline bake, then persist meta.
		var post_plans: Dictionary = ensure_mesh_plans(host, world, false)
		_write_plan_seed_meta()
		var post: Dictionary = validate_loaded_bake(seed, want_full)
		baked["mesh_plan"] = post_plans
		if bool(post.get("ok", false)):
			log_valid_bake(post)
		else:
			print(
				"[WorldBake] Rebuild finished but validation still failing: %s"
				% str(post.get("reasons", []))
			)
		return {
			"ok": bool(saved.get("ok", false)),
			"mode": "baked",
			"seed": seed,
			"full_world": full_world,
			"streamed": streamed,
			"bounds": bounds_dict(),
			"chunks": chunk_count(),
			"bake_ms": last_bake_time_ms,
			"bytes": last_bake_bytes,
			"mesh_plan": baked.get("mesh_plan", {}),
			"mesh_plan_bytes": saved.get("mesh_plan_bytes", 0),
			"static_meta_bytes": last_static_meta_bytes,
			"error": last_error,
			"validation": post,
		}
	clear_memory()
	return {"ok": true, "mode": "miss", "seed": seed}


func _reasons_only_mesh_plan(reasons: PackedStringArray) -> bool:
	if reasons.is_empty():
		return false
	for r in reasons:
		var s := str(r)
		if s.begins_with("mesh_plans"):
			continue
		return false
	return true


## Ensure mesh plans exist on disk. Repair at most once; write packages + plan_seed_meta.
## force_fill: repair even if sampling is ambiguous.
func ensure_mesh_plans(host, world, force_fill: bool = false) -> Dictionary:
	# Streamed packages already embed mesh plans per chunk — no monolith load.
	if streamed and valid:
		var need_fill: bool = force_fill
		var need_plans := false
		var need_stamps := false
		if not need_fill:
			need_plans = packages_need_mesh_plan_fill()
			need_stamps = seed_stamps_require_plan_refresh()
			need_fill = need_plans or need_stamps
		var mode := "streamed"
		if need_fill:
			print(
				"[WorldBake] Mesh plans incomplete — repairing once and writing to disk (plans=%s stamps=%s)..."
				% [str(need_plans or force_fill), str(need_stamps)]
			)
			var fill: Dictionary = fill_mesh_plans_in_packages(host, world)
			if not bool(fill.get("ok", false)):
				push_warning("[WorldBake] mesh plan fill failed: %s" % str(fill.get("error", "")))
				mode = "repair_failed"
			else:
				_write_plan_seed_meta()
				mode = "repaired"
				print(
					"[WorldBake] filled mesh plans packages=%s avg_qn=%.1f fill_ms=%s (written to disk)"
					% [
						str(fill.get("packages", 0)),
						float(fill.get("avg_plan_qn", 0.0)),
						str(fill.get("fill_ms", 0)),
					]
				)
		else:
			# Valid plans already on disk — ensure meta stamp so we never re-enter repair.
			if not FileAccess.file_exists(_plan_seed_meta_path()):
				_write_plan_seed_meta()
			mode = "valid"
		var mp_script = load("res://world/mesh_plan_cache.gd")
		if mp_script:
			var plans = mp_script.ensure_active()
			plans.world_seed = world_seed
			plans.min_cx = min_cx
			plans.max_cx = max_cx
			plans.min_cz = min_cz
			plans.max_cz = max_cz
			plans.full_world = full_world
			plans.radius = radius
			plans.valid = true
			plans.streamed_from_bake = true
			mp_script.set_active(plans)
		var stats: Dictionary = sample_package_plan_stats(mini(expected_chunk_count(), 8))
		# Sampling may have loaded packages; drop them so startup resident count stays 0.
		_resident.clear()
		return {
			"ok": true,
			"mode": mode,
			"chunks": expected_chunk_count(),
			"bytes": last_bake_bytes,
			"plan_stats": stats,
		}
	# Legacy monolith mesh plan path: load if present; rebuild automatically when missing.
	var mp_script2 = load("res://world/mesh_plan_cache.gd")
	if mp_script2 == null:
		return {"ok": false, "mode": "unavailable"}
	if not mp_script2.enabled_from_env():
		return {"ok": true, "mode": "disabled"}
	var plans2 = mp_script2.ensure_active()
	var r: int = maxi(absi(min_cx), absi(max_cx))
	if r <= 0:
		r = radius
	if plans2.has_method("load_plans") and plans2.load_plans(world_seed, r):
		mp_script2.set_active(plans2)
		return {
			"ok": true,
			"mode": "loaded",
			"chunks": plans2.plan_count(),
			"bytes": plans2.last_bytes,
			"bake_ms": 0,
		}
	if host == null or world == null:
		return {
			"ok": true,
			"mode": "miss",
			"chunks": 0,
			"bytes": 0,
			"note": "legacy bake without plans and no host to rebuild",
		}
	var baked: Dictionary = plans2.bake_plans(host, world, r, world_seed)
	if not bool(baked.get("ok", false)):
		return {"ok": false, "mode": "bake_failed", "error": plans2.last_error}
	var saved: Dictionary = plans2.save_plans()
	mp_script2.set_active(plans2)
	return {
		"ok": bool(saved.get("ok", false)),
		"mode": "baked",
		"chunks": plans2.plan_count(),
		"bytes": plans2.last_bytes,
		"bake_ms": plans2.last_bake_time_ms,
	}


## Resolve a mesh host that can _build_mesh (ChunkManager). Creates a temporary one if needed.
func _resolve_mesh_host(host, world):
	if host != null and host.has_method("_build_mesh"):
		if world != null and "world" in host and host.world == null:
			host.world = world
		return host
	var CM = load("res://chunks/chunk_manager.gd")
	if CM == null:
		return null
	var mgr = CM.new()
	if world != null:
		mgr.world = world
	return mgr


## Sample package plan sizes (loads into RAM then may release).
func sample_package_plan_stats(max_samples: int = 8) -> Dictionary:
	if not valid:
		return {"sampled": 0, "with_plan": 0, "empty_plan": 0, "avg_plan_qn": 0.0, "total_qn": 0}
	var coords: Array = covered_coords()
	var n: int = mini(coords.size(), maxi(max_samples, 1))
	var with_plan := 0
	var empty := 0
	var total_qn := 0
	for i in n:
		var c: Vector2i = coords[i]
		if not ensure_chunk_resident(c):
			empty += 1
			continue
		var plan: Array = get_mesh_plan(c)
		var qn: int = plan.size()
		total_qn += qn
		if qn > 0:
			with_plan += 1
		else:
			empty += 1
	return {
		"sampled": n,
		"with_plan": with_plan,
		"empty_plan": empty,
		"avg_plan_qn": float(total_qn) / float(maxi(n, 1)),
		"total_qn": total_qn,
	}


func packages_need_mesh_plan_fill() -> bool:
	if not valid or package_dir.is_empty():
		return false
	var stats: Dictionary = sample_package_plan_stats(mini(8, expected_chunk_count()))
	var sampled: int = int(stats.get("sampled", 0))
	if sampled <= 0:
		return true
	var empty: int = int(stats.get("empty_plan", 0))
	var with_plan: int = int(stats.get("with_plan", 0))
	# Repair only when plans are broadly missing (not a single sparse empty column).
	if with_plan == 0:
		return true
	return empty * 2 >= sampled


func _plan_seed_meta_path() -> String:
	return package_dir.path_join("plan_seed_meta.json")


## Count world-seeded tile stamps that affect mesh plans, excluding baked-static vegetation
## (re-installing veg packages must not force plan repair every boot).
func _current_seed_stamp_count() -> int:
	var ws = load("res://world/world_state.gd").get_active()
	if ws == null or not ("seeded_tile_keys" in ws):
		return 0
	var n := 0
	for key in ws.seeded_tile_keys.keys():
		var fc: Dictionary = ws.feature_cells.get(key, {})
		if bool(fc.get("_baked_static", false)):
			continue
		n += 1
	return n


func seed_stamps_require_plan_refresh() -> bool:
	if package_dir.is_empty():
		return false
	# Empty/incomplete plans always need a one-shot fill first.
	if packages_need_mesh_plan_fill():
		return true
	var want: int = _current_seed_stamp_count()
	var path := _plan_seed_meta_path()
	if not FileAccess.file_exists(path):
		# Valid plans already on disk — caller writes meta without refill.
		return false
	var txt := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if int(data.get("world_seed", -1)) != world_seed:
		return true
	var have: int = int(data.get("seeded_tile_count", -1))
	# Town/ruin stamp set changed → one-shot plan refresh, then meta rewrite.
	return have >= 0 and have != want


func _write_plan_seed_meta() -> void:
	if package_dir.is_empty():
		return
	var path := _plan_seed_meta_path()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"seeded_tile_count": _current_seed_stamp_count(),
		"world_seed": world_seed,
		"bake_version": BAKE_VERSION,
	}, "\t"))
	f.close()


## Rewrite every package with a complete mesh plan (terrain+veg already on disk).
## Uses the LIVE WorldState session when available (post feature_seeding) so town/ruin
## world-seed stamps are captured in plans and remain plan-compatible at runtime.
func fill_mesh_plans_in_packages(host, world) -> Dictionary:
	if not valid:
		return {"ok": false, "error": "bake not valid"}
	var mesh_host = _resolve_mesh_host(host, world)
	if mesh_host == null or not mesh_host.has_method("_build_mesh"):
		return {"ok": false, "error": "no mesh host"}
	if world == null:
		return {"ok": false, "error": "no world"}
	var t0 := Time.get_ticks_msec()
	var _ChunkData = load("res://chunks/chunk_data.gd")
	var _FeatureRegistry = load("res://world/feature_registry.gd")
	# Ensure package vegetation is resident in the live session (idempotent).
	var coords: Array = covered_coords()
	for c_variant in coords:
		var c: Vector2i = c_variant
		if not ensure_chunk_resident(c):
			continue
		var pack: Dictionary = _resident.get(c, {})
		var veg: Array = pack.get("vegetation", [])
		if not veg.is_empty() and _FeatureRegistry and _FeatureRegistry.has_method("apply_baked_vegetation_chunk"):
			_FeatureRegistry.apply_baked_vegetation_chunk(c, veg)
	var filled := 0
	var total_qn := 0
	var empty_after := 0
	for c_variant2 in coords:
		var coord: Vector2i = c_variant2
		if not ensure_chunk_resident(coord):
			continue
		var pack2: Dictionary = _resident.get(coord, {})
		var surface: PackedFloat32Array = pack2.get("surface", PackedFloat32Array())
		var tiles: PackedInt32Array = pack2.get("tiles", PackedInt32Array())
		var veg2: Array = pack2.get("vegetation", [])
		if surface.size() != CELLS2 or tiles.size() != CELLS2:
			continue
		var data = _ChunkData.new(coord, world)
		# Live session snapshot (towns/ruins/veg already applied).
		data.capture_worker_snapshot()
		_apply_pack_to_data(data, surface, tiles)
		if data.has_method("_bind_macro_surface_if_needed"):
			data._bind_macro_surface_if_needed()
		var built: Dictionary = mesh_host._build_mesh(data)
		var quads: Array = built.get("quads", [])
		var plan: Array = []
		plan.resize(quads.size())
		for qi in quads.size():
			plan[qi] = (quads[qi] as Dictionary).duplicate(true)
		if plan.is_empty():
			empty_after += 1
		total_qn += plan.size()
		_write_chunk_package(coord, surface, tiles, plan, veg2)
		pack2["plan"] = plan
		_resident[coord] = pack2
		filled += 1
	# Drop RAM after fill (stream on demand).
	_resident.clear()
	var avg_qn: float = float(total_qn) / float(maxi(filled, 1))
	return {
		"ok": filled > 0 and empty_after == 0,
		"packages": filled,
		"empty_after": empty_after,
		"avg_plan_qn": avg_qn,
		"total_qn": total_qn,
		"fill_ms": Time.get_ticks_msec() - t0,
	}


## Bake all chunks in span; write each package immediately (streamed). Does not retain world in RAM.
func bake_world(world, rad: int = -1, host = null) -> Dictionary:
	if world == null:
		last_error = "bake_world: null world"
		valid = false
		return {"ok": false, "error": last_error}
	var t0 := Time.get_ticks_msec()
	world_seed = int(world.world_seed) if "world_seed" in world else 0
	# Invalidate until bake completes so halo/column paths never sample half-written packages.
	valid = false
	vegetation_baked = false
	_resident.clear()
	_chunks.clear()
	streamed = true
	if rad >= 0:
		full_world = false
		radius = rad
		min_cx = -rad
		max_cx = rad
		min_cz = -rad
		max_cz = rad
	elif use_full_world_from_env():
		var b: Dictionary = full_world_chunk_bounds()
		full_world = true
		min_cx = int(b.min_cx)
		max_cx = int(b.max_cx)
		min_cz = int(b.min_cz)
		max_cz = int(b.max_cz)
		radius = maxi(absi(min_cx), absi(max_cx))
	else:
		full_world = false
		radius = smoke_radius_from_env()
		min_cx = -radius
		max_cx = radius
		min_cz = -radius
		max_cz = radius

	package_dir = bake_dir_for(world_seed, radius if not full_world else -1, full_world)
	var chunks_dir := package_dir.path_join("chunks")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(chunks_dir))

	# Offline vegetation scatter (same rules as VegetationManager) → per-chunk packages.
	var veg_t0 := Time.get_ticks_msec()
	var veg_by_chunk: Dictionary = _bake_vegetation_by_chunk(world)
	last_vegetation_bake_ms = Time.get_ticks_msec() - veg_t0
	last_vegetation_entries = 0
	for ck in veg_by_chunk.keys():
		last_vegetation_entries += (veg_by_chunk[ck] as Array).size()

	var count := 0
	var plan_count := 0
	var plan_qn_total := 0
	var bytes_written := 0
	# Always emit mesh plans — resolve/create mesh host if caller omitted one.
	var mesh_host = _resolve_mesh_host(host, world)
	var co_mesh: bool = mesh_host != null and mesh_host.has_method("_build_mesh")
	if not co_mesh:
		last_error = "bake_world: cannot resolve mesh host for plans"
		valid = false
		return {"ok": false, "error": last_error}
	var _WorldState = load("res://world/world_state.gd")
	var _ChunkData = load("res://chunks/chunk_data.gd")
	var _FeatureRegistry = load("res://world/feature_registry.gd")
	var prev_ws = null
	if _WorldState:
		prev_ws = _WorldState.get_active()
		_WorldState.replace_active()
		# Temporary session: install baked vegetation so mesh plans include feature tiles.
		if _FeatureRegistry and _FeatureRegistry.has_method("apply_baked_vegetation_chunk"):
			for ck in veg_by_chunk.keys():
				_FeatureRegistry.apply_baked_vegetation_chunk(ck, veg_by_chunk[ck])
	set_active(self)

	for cz in range(min_cz, max_cz + 1):
		for cx in range(min_cx, max_cx + 1):
			var coord := Vector2i(cx, cz)
			var surface := PackedFloat32Array()
			var tiles := PackedInt32Array()
			surface.resize(CELLS2)
			tiles.resize(CELLS2)
			var i := 0
			for lz in CELLS:
				for lx in CELLS:
					var wx := float(cx * CELLS + lx)
					var wz := float(cz * CELLS + lz)
					surface[i] = float(world.get_surface_height_worker(wx, wz, 0.0))
					tiles[i] = int(world.get_tile_type_worker(wx, wz, -1, -1))
					i += 1
			var plan: Array = []
			var data = _ChunkData.new(coord, world)
			data.capture_worker_snapshot()
			_apply_pack_to_data(data, surface, tiles)
			if data.has_method("_bind_macro_surface_if_needed"):
				data._bind_macro_surface_if_needed()
			var built: Dictionary = mesh_host._build_mesh(data)
			var quads: Array = built.get("quads", [])
			plan.resize(quads.size())
			for qi in quads.size():
				plan[qi] = (quads[qi] as Dictionary).duplicate(true)
			plan_qn_total += plan.size()
			plan_count += 1
			var veg: Array = veg_by_chunk.get(coord, [])
			var wbytes: int = _write_chunk_package(coord, surface, tiles, plan, veg)
			bytes_written += wbytes
			count += 1

	if _WorldState:
		if prev_ws != null:
			_WorldState.set_active(prev_ws)
		else:
			_WorldState.replace_active()

	last_bake_time_ms = Time.get_ticks_msec() - t0
	last_bake_bytes = bytes_written
	valid = count > 0 and plan_count == count
	vegetation_baked = valid
	var avg_qn: float = float(plan_qn_total) / float(maxi(plan_count, 1))
	if plan_qn_total <= 0:
		last_error = "bake_world: all mesh plans empty"
		valid = false
		return {"ok": false, "error": last_error, "packages": count}
	last_error = "" if valid else "empty bake"
	# Do not keep per-chunk data in RAM after bake.
	_resident.clear()
	_chunks.clear()

	var mesh_plan_info := {
		"ok": plan_count > 0,
		"chunks": plan_count,
		"avg_plan_qn": avg_qn,
		"total_plan_qn": plan_qn_total,
		"bake_ms": last_bake_time_ms,
		"streamed": true,
	}
	return {
		"ok": valid,
		"seed": world_seed,
		"full_world": full_world,
		"streamed": true,
		"bounds": bounds_dict(),
		"radius": radius,
		"chunks": count,
		"expected_chunks": expected_chunk_count(),
		"bake_ms": last_bake_time_ms,
		"bytes": bytes_written,
		"vegetation_entries": last_vegetation_entries,
		"vegetation_bake_ms": last_vegetation_bake_ms,
		"mesh_plan": mesh_plan_info,
		"static_meta": _capture_static_meta(world),
		"error": last_error,
	}


func _bake_vegetation_by_chunk(world) -> Dictionary:
	var Veg = load("res://world/vegetation_manager.gd")
	if Veg == null or not Veg.has_method("bake_scatter_map"):
		return {}
	var attempts: int = 12000
	var densities := {}
	if world != null and "world_config" in world and world.world_config != null:
		var wg = world.world_config
		if "vegetation_scatter_attempts" in wg:
			attempts = int(wg.vegetation_scatter_attempts)
		if "grass_density" in wg:
			densities["grass_density"] = float(wg.grass_density)
		if "tree_density" in wg:
			densities["tree_density"] = float(wg.tree_density)
		if "bush_density" in wg:
			densities["bush_density"] = float(wg.bush_density)
	var env_att := OS.get_environment("CRYSTALSTORM_VEG_BAKE_ATTEMPTS").strip_edges()
	if not env_att.is_empty():
		attempts = maxi(env_att.to_int(), 0)
	# Scatter only inside this package's world rectangle (density-scaled attempts).
	var bounds := {
		"min_wx": min_cx * CELLS,
		"max_wx": (max_cx + 1) * CELLS - 1,
		"min_wz": min_cz * CELLS,
		"max_wz": (max_cz + 1) * CELLS - 1,
	}
	var world_map: Dictionary = Veg.bake_scatter_map(world, attempts, densities, bounds)
	return Veg.bucket_by_chunk(world_map, CELLS)


func _capture_static_meta(world) -> Dictionary:
	var meta := {
		"seed": world_seed,
		"full_world": full_world,
		"streamed": streamed,
		"bounds": bounds_dict(),
		"playable_half": full_world_chunk_bounds(),
	}
	var fr = load("res://world/feature_registry.gd")
	if fr:
		meta["feature_registry"] = "present"
	if world != null and "world_seed" in world:
		meta["world_seed"] = int(world.world_seed)
	return meta


func _write_chunk_package(
	coord: Vector2i,
	surface: PackedFloat32Array,
	tiles: PackedInt32Array,
	plan: Array,
	vegetation: Array = []
) -> int:
	var path := chunk_package_path(coord)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("WorldBake: failed to write %s" % path)
		return 0
	f.store_buffer(CHUNK_MAGIC.to_utf8_buffer())
	f.store_32(BAKE_VERSION)
	# store_64 for signed chunk coords (store_32 is unsigned-hostile for negatives).
	f.store_64(coord.x)
	f.store_64(coord.y)
	var checksum: int = BAKE_VERSION ^ coord.x ^ coord.y
	for i in CELLS2:
		var h: float = float(surface[i])
		f.store_float(h)
		checksum = checksum ^ int(h * 1000.0)
		var tv: int = int(tiles[i])
		f.store_32(tv)
		checksum = checksum ^ tv
	f.store_32(plan.size())
	checksum = checksum ^ plan.size()
	f.store_var(plan, false)
	# v4+: baked vegetation entries (local lx/lz + plant meta).
	f.store_32(vegetation.size())
	checksum = checksum ^ vegetation.size()
	f.store_var(vegetation, false)
	# Terrain+veg counts checksum (store_var payloads validated by size + load success).
	f.store_32(_u32(checksum))
	f.close()
	if FileAccess.file_exists(path):
		return int(FileAccess.get_file_as_bytes(path).size())
	return 0


func _read_chunk_package(coord: Vector2i) -> Dictionary:
	var path := chunk_package_path(coord)
	var t0 := Time.get_ticks_usec()
	var SPP = load("res://systems/stream_phase_profiler.gd")
	var spp_on: bool = SPP != null and SPP.is_enabled()
	if not FileAccess.file_exists(path):
		last_error = "missing chunk package %s" % path
		stats_missing_package_errors += 1
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		last_error = "open failed %s" % path
		stats_missing_package_errors += 1
		return {}
	# v3/v4 packages are uncompressed — decompression always 0.
	if spp_on:
		SPP.record("decompression", 0, coord)
	var magic := f.get_buffer(4).get_string_from_utf8()
	if magic != CHUNK_MAGIC:
		last_error = "bad chunk magic %s" % path
		f.close()
		stats_missing_package_errors += 1
		return {}
	var ver: int = int(f.get_32())
	# Accept v3 (no veg) and v4+ (with veg).
	if ver != BAKE_VERSION and ver != 3:
		last_error = "chunk version mismatch %d" % ver
		f.close()
		return {}
	var cx: int = int(f.get_64())
	var cz: int = int(f.get_64())
	if cx != coord.x or cz != coord.y:
		last_error = "chunk coord mismatch file=(%d,%d) want=%s" % [cx, cz, str(coord)]
		f.close()
		return {}
	var checksum: int = ver ^ cx ^ cz
	# package_file_read: open + header + raw column floats/ints (no Variant decode).
	var surface := PackedFloat32Array()
	var tiles := PackedInt32Array()
	surface.resize(CELLS2)
	tiles.resize(CELLS2)
	for i in CELLS2:
		var h: float = f.get_float()
		surface[i] = h
		checksum = checksum ^ int(h * 1000.0)
		var tv: int = int(f.get_32())
		tiles[i] = tv
		checksum = checksum ^ tv
	var qn: int = int(f.get_32())
	checksum = checksum ^ qn
	var file_read_us: int = Time.get_ticks_usec() - t0
	# deserialization: plan + vegetation Variant blobs + trailer.
	var t_deser0 := Time.get_ticks_usec()
	var plan = f.get_var(false)
	if typeof(plan) != TYPE_ARRAY:
		last_error = "plan not array"
		f.close()
		return {}
	if (plan as Array).size() != qn:
		last_error = "plan count mismatch"
		f.close()
		return {}
	var vegetation: Array = []
	if ver >= 4:
		var vn: int = int(f.get_32())
		checksum = checksum ^ vn
		var veg_raw = f.get_var(false)
		if typeof(veg_raw) != TYPE_ARRAY:
			last_error = "vegetation not array"
			f.close()
			return {}
		if (veg_raw as Array).size() != vn:
			last_error = "vegetation count mismatch"
			f.close()
			return {}
		vegetation = veg_raw as Array
	var file_cs: int = int(f.get_32())
	f.close()
	var deser_us: int = Time.get_ticks_usec() - t_deser0
	if spp_on:
		SPP.record("package_file_read", file_read_us, coord)
		SPP.record("deserialization", deser_us, coord)
	stats_disk_reads += 1
	stats_disk_read_us += Time.get_ticks_usec() - t0
	if file_cs != _u32(checksum):
		last_error = "chunk checksum mismatch %s want=%d got=%d" % [path, _u32(checksum), file_cs]
		stats_missing_package_errors += 1
		return {}
	return {"surface": surface, "tiles": tiles, "plan": plan, "vegetation": vegetation}


## Load chunk package into RAM if needed. Returns false if missing/corrupt.
## Vegetation stamps are installed once when the package first becomes resident
## (not on every ensure hit — that re-walked FeatureRegistry on every stream start).
func ensure_chunk_resident(coord: Vector2i) -> bool:
	if not valid:
		last_error = "ensure_chunk_resident: bake not valid"
		return false
	if not coord_in_package(coord):
		last_error = "ensure_chunk_resident: coord out of package %s" % str(coord)
		return false
	if _resident.has(coord) or _chunks.has(coord):
		return true
	# Streamed packages (and any package_dir with chunks/) load on demand.
	if not package_dir.is_empty():
		var pack: Dictionary = _read_chunk_package(coord)
		if pack.is_empty():
			push_error("[WorldBake] %s" % last_error)
			return false
		_resident[coord] = pack
		_install_resident_vegetation(coord, pack)
		return true
	last_error = "ensure_chunk_resident: no package_dir and not in monolith"
	return _chunks.has(coord)


## Ensure package bytes/surfaces are in RAM for mesh-halo sampling without reinstalling vegetation.
## Use for neighbor ring prefetch around a stream start; full ensure_chunk_resident for the target.
func ensure_package_data_resident(coord: Vector2i) -> bool:
	if not valid:
		return false
	if not coord_in_package(coord):
		return false
	if _resident.has(coord) or _chunks.has(coord):
		return true
	if package_dir.is_empty():
		return _chunks.has(coord)
	var pack: Dictionary = _read_chunk_package(coord)
	if pack.is_empty():
		return false
	_resident[coord] = pack
	return true


func _install_resident_vegetation(coord: Vector2i, pack: Dictionary) -> void:
	if pack.is_empty():
		return
	var veg: Array = pack.get("vegetation", [])
	if veg.is_empty():
		var SPP0 = load("res://systems/stream_phase_profiler.gd")
		if SPP0 and SPP0.is_enabled():
			SPP0.record("baked_vegetation_install", 0, coord)
		return
	var t0 := Time.get_ticks_usec()
	var fr = load("res://world/feature_registry.gd")
	if fr and fr.has_method("apply_baked_vegetation_chunk"):
		fr.apply_baked_vegetation_chunk(coord, veg)
	var SPP = load("res://systems/stream_phase_profiler.gd")
	if SPP and SPP.is_enabled():
		SPP.record("baked_vegetation_install", Time.get_ticks_usec() - t0, coord)


func release_chunk(coord: Vector2i) -> void:
	if _resident.has(coord):
		_resident.erase(coord)
		stats_releases += 1
	# Monolith _chunks intentionally retained only for legacy non-streamed mode.


func get_mesh_plan(coord: Vector2i) -> Array:
	if not ensure_chunk_resident(coord):
		return []
	if _resident.has(coord):
		return _resident[coord].get("plan", [])
	return []


func save_bake(path: String = "") -> Dictionary:
	if not valid:
		last_error = "save_bake: nothing to save"
		return {"ok": false, "error": last_error}
	var t0 := Time.get_ticks_msec()
	if package_dir.is_empty():
		package_dir = bake_dir_for(world_seed, radius if not full_world else -1, full_world)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(package_dir))
	var index_path := path if not path.is_empty() else package_dir.path_join("world.index")
	var f := FileAccess.open(index_path, FileAccess.WRITE)
	if f == null:
		last_error = "save index failed"
		return {"ok": false, "error": last_error}
	f.store_buffer(INDEX_MAGIC.to_utf8_buffer())
	f.store_32(BAKE_VERSION)
	f.store_64(world_seed)
	f.store_64(min_cx)
	f.store_64(max_cx)
	f.store_64(min_cz)
	f.store_64(max_cz)
	var flags: int = FLAG_STREAMED
	if full_world:
		flags |= FLAG_FULL_WORLD
	if vegetation_baked:
		flags |= FLAG_VEGETATION
	f.store_32(flags)
	f.store_32(expected_chunk_count())
	var checksum: int = (
		BAKE_VERSION ^ world_seed ^ min_cx ^ max_cx ^ min_cz ^ max_cz ^ flags ^ expected_chunk_count()
	)
	f.store_32(_u32(checksum))
	f.close()

	var meta_path := package_dir.path_join("static_meta.json")
	var mf := FileAccess.open(meta_path, FileAccess.WRITE)
	if mf:
		mf.store_string(JSON.stringify(_capture_static_meta(null), "\t"))
		mf.close()
		last_static_meta_bytes = int(FileAccess.get_file_as_bytes(meta_path).size())

	# Sum package sizes on disk.
	var total := 0
	if FileAccess.file_exists(index_path):
		total += int(FileAccess.get_file_as_bytes(index_path).size())
	var chunks_path := ProjectSettings.globalize_path(package_dir.path_join("chunks"))
	if DirAccess.dir_exists_absolute(chunks_path):
		var da := DirAccess.open(package_dir.path_join("chunks"))
		if da:
			da.list_dir_begin()
			var n := da.get_next()
			while n != "":
				if not da.current_is_dir() and n.ends_with(".chk"):
					var fp := package_dir.path_join("chunks").path_join(n)
					total += int(FileAccess.get_file_as_bytes(fp).size())
				n = da.get_next()
			da.list_dir_end()
	last_bake_bytes = total
	last_save_time_ms = Time.get_ticks_msec() - t0
	last_error = ""
	return {
		"ok": true,
		"path": index_path,
		"bytes": last_bake_bytes,
		"save_ms": last_save_time_ms,
		"mesh_plan_bytes": 0,
		"static_meta_bytes": last_static_meta_bytes,
		"streamed": true,
		"full_world": full_world,
	}


func load_bake_for_seed(seed: int, prefer_full: bool = true) -> bool:
	if prefer_full:
		if load_index(bake_dir_for(seed, -1, true), seed):
			return true
	var r := smoke_radius_from_env()
	if load_index(bake_dir_for(seed, r, false), seed):
		return true
	# Legacy v2 monolith (optional fall-through for old packages).
	return _try_load_legacy_monolith(seed, r)


func load_bake(seed: int, rad: int = -1, path: String = "") -> bool:
	if not path.is_empty():
		if path.ends_with("world.index") or path.ends_with(".index"):
			return load_index(path.get_base_dir(), seed)
		return _try_load_legacy_file(path, seed)
	if rad >= 0:
		if load_index(bake_dir_for(seed, rad, false), seed):
			return true
		return _try_load_legacy_monolith(seed, rad)
	return load_bake_for_seed(seed, use_full_world_from_env())


func load_index(dir: String, expected_seed: int = -1) -> bool:
	var t0 := Time.get_ticks_msec()
	var index_path := dir.path_join("world.index")
	if not FileAccess.file_exists(index_path):
		last_error = "load_bake: missing index %s" % index_path
		valid = false
		return false
	var f := FileAccess.open(index_path, FileAccess.READ)
	if f == null:
		last_error = "load_bake: open index failed"
		valid = false
		return false
	var magic := f.get_buffer(4).get_string_from_utf8()
	if magic != INDEX_MAGIC and magic != MAGIC:
		last_error = "load_bake: bad index magic"
		valid = false
		f.close()
		return false
	var ver: int = int(f.get_32())
	if ver != BAKE_VERSION and ver != 3 and ver != 2:
		last_error = "load_bake: version mismatch got=%d" % ver
		valid = false
		f.close()
		return false
	var file_seed: int = int(f.get_64())
	if expected_seed >= 0 and file_seed != expected_seed:
		last_error = "load_bake: seed mismatch"
		valid = false
		f.close()
		return false
	# v3+ uses store_64 for signed bounds; legacy used store_32.
	if ver >= 3:
		min_cx = int(f.get_64())
		max_cx = int(f.get_64())
		min_cz = int(f.get_64())
		max_cz = int(f.get_64())
	else:
		min_cx = _i32(f.get_32())
		max_cx = _i32(f.get_32())
		min_cz = _i32(f.get_32())
		max_cz = _i32(f.get_32())
	var flags: int = int(f.get_32())
	full_world = (flags & FLAG_FULL_WORLD) != 0
	streamed = (flags & FLAG_STREAMED) != 0 or ver >= 3
	vegetation_baked = (flags & FLAG_VEGETATION) != 0 or ver >= 4
	var count: int = int(f.get_32())
	var checksum: int = ver ^ file_seed ^ min_cx ^ max_cx ^ min_cz ^ max_cz ^ flags ^ count
	if ver == 2:
		checksum = 2 ^ file_seed ^ min_cx ^ max_cx ^ min_cz ^ max_cz ^ flags ^ count
	var file_cs: int = int(f.get_32())
	f.close()
	if ver >= 3 and file_cs != _u32(checksum):
		last_error = "load_bake: index checksum mismatch"
		valid = false
		return false
	world_seed = file_seed
	radius = maxi(absi(min_cx), absi(max_cx))
	package_dir = dir
	_resident.clear()
	_chunks.clear()
	valid = true
	last_load_time_ms = Time.get_ticks_msec() - t0
	last_bake_bytes = 0
	last_error = ""
	# Startup: index only — no chunk packages loaded.
	return true


func _try_load_legacy_monolith(seed: int, rad: int) -> bool:
	for as_full in [true, false]:
		var p := "user://world_bakes/v2_s%d_%s/world.bake" % [
			seed, "full" if as_full else ("r%d" % rad)
		]
		if FileAccess.file_exists(p):
			return _try_load_legacy_file(p, seed)
	var legacy := "user://world_bakes/v1_s%d_r%d/world.bake" % [seed, rad]
	if FileAccess.file_exists(legacy):
		return _try_load_legacy_file(legacy, seed)
	last_error = "load_bake: no package for seed=%d" % seed
	valid = false
	return false


func _try_load_legacy_file(file_path: String, expected_seed: int) -> bool:
	# Load entire monolith into _chunks (legacy compatibility; not used for v3).
	var t0 := Time.get_ticks_msec()
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		return false
	var magic := f.get_buffer(4).get_string_from_utf8()
	if magic != MAGIC:
		f.close()
		return false
	var ver: int = int(f.get_32())
	var file_seed: int = int(f.get_64())
	if expected_seed >= 0 and file_seed != expected_seed:
		f.close()
		return false
	_chunks.clear()
	_resident.clear()
	if ver == 1:
		var file_radius: int = int(f.get_32())
		var count: int = int(f.get_32())
		min_cx = -file_radius
		max_cx = file_radius
		min_cz = -file_radius
		max_cz = file_radius
		radius = file_radius
		full_world = false
		streamed = false
		for _i in count:
			var cx: int = int(f.get_32())
			var cz: int = int(f.get_32())
			var surface := PackedFloat32Array()
			var tiles := PackedInt32Array()
			surface.resize(CELLS2)
			tiles.resize(CELLS2)
			for i in CELLS2:
				surface[i] = f.get_float()
				tiles[i] = int(f.get_32())
			_chunks[Vector2i(cx, cz)] = {"surface": surface, "tiles": tiles, "plan": []}
		f.get_32()  # checksum ignored for legacy
	else:
		min_cx = int(f.get_32())
		max_cx = int(f.get_32())
		min_cz = int(f.get_32())
		max_cz = int(f.get_32())
		var flags: int = int(f.get_32())
		full_world = (flags & FLAG_FULL_WORLD) != 0
		streamed = false
		radius = maxi(absi(min_cx), absi(max_cx))
		var count2: int = int(f.get_32())
		for _j in count2:
			var cx2: int = int(f.get_32())
			var cz2: int = int(f.get_32())
			var surface2 := PackedFloat32Array()
			var tiles2 := PackedInt32Array()
			surface2.resize(CELLS2)
			tiles2.resize(CELLS2)
			for i2 in CELLS2:
				surface2[i2] = f.get_float()
				tiles2[i2] = int(f.get_32())
			_chunks[Vector2i(cx2, cz2)] = {"surface": surface2, "tiles": tiles2, "plan": []}
		if f.get_position() + 4 <= f.get_length():
			f.get_32()
	f.close()
	world_seed = file_seed
	package_dir = file_path.get_base_dir()
	valid = not _chunks.is_empty()
	last_load_time_ms = Time.get_ticks_msec() - t0
	last_bake_bytes = int(FileAccess.get_file_as_bytes(file_path).size()) if FileAccess.file_exists(file_path) else 0
	return valid


func delete_bake(seed: int, rad: int = -1) -> void:
	for as_full in [true, false]:
		var r := rad if rad >= 0 else radius
		var dir_path := bake_dir_for(seed, r, as_full)
		var abs_dir := ProjectSettings.globalize_path(dir_path)
		if DirAccess.dir_exists_absolute(abs_dir):
			_rm_tree(abs_dir)
	for ver in [1, 2]:
		var legacy := "user://world_bakes/v%d_s%d_r%d" % [ver, seed, rad if rad >= 0 else SMOKE_DEFAULT_RADIUS]
		var abs_l := ProjectSettings.globalize_path(legacy)
		if DirAccess.dir_exists_absolute(abs_l):
			_rm_tree(abs_l)


func _rm_tree(abs_dir: String) -> void:
	var da := DirAccess.open(abs_dir)
	if da == null:
		return
	da.list_dir_begin()
	var n := da.get_next()
	while n != "":
		if n != "." and n != "..":
			var p := abs_dir.path_join(n)
			if da.current_is_dir():
				_rm_tree(p)
			else:
				DirAccess.remove_absolute(p)
		n = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(abs_dir)


func _apply_pack_to_data(data, surface: PackedFloat32Array, tiles: PackedInt32Array) -> void:
	var t0 := Time.get_ticks_usec()
	if data.has_method("_ensure_surface_map_storage"):
		data._ensure_surface_map_storage()
	# Keep immutable baked base on ChunkData so dirty rebuilds never re-noise.
	if data.has_method("store_baked_base"):
		data.store_baked_base(surface, tiles)
	var layer: float = maxf(_WorldSettings.get_active().layer_height(), 0.001)
	var i := 0
	for lz in CELLS:
		for lx in CELLS:
			var base_h: float = float(surface[i])
			var base_t: int = int(tiles[i])
			i += 1
			var hdelta: float = 0.0
			var build_t: int = -1
			var feat_t: int = -1
			if data.has_method("has_worker_overlay_snapshot") and data.has_worker_overlay_snapshot():
				hdelta = float(data.get_worker_height_delta(lx, lz))
				build_t = int(data.get_worker_build_tile(lx, lz))
				if data.has_method("get_worker_feature_tile"):
					feat_t = int(data.get_worker_feature_tile(lx, lz))
			var h: float = base_h + hdelta
			h = round(h / layer) * layer
			data.surface_map[lx][lz] = h
			if build_t >= 0:
				data.tile_map[lx][lz] = build_t
			elif feat_t >= 0:
				data.tile_map[lx][lz] = feat_t
			else:
				data.tile_map[lx][lz] = base_t
	if data.get("_has_halo_surface") and data.has_method("_refresh_halo_interior_from_maps"):
		data._refresh_halo_interior_from_maps()
	if data.has_method("derive_micro_from_terrain_edits"):
		data.derive_micro_from_terrain_edits()
	var SPP = load("res://systems/stream_phase_profiler.gd")
	if SPP and SPP.is_enabled() and data != null:
		var c: Vector2i = data.position if "position" in data else Vector2i.ZERO
		SPP.record("worldstate_overlay_apply", Time.get_ticks_usec() - t0, c)


func try_apply_base_to_chunk_data(data) -> bool:
	if not bake_enabled_from_env():
		return false
	if not valid or data == null:
		return false
	var coord: Vector2i = data.position
	if not coord_in_package(coord):
		return false
	var t0 := Time.get_ticks_usec()
	var pack: Dictionary = {}
	if streamed:
		if not ensure_chunk_resident(coord):
			return false
		pack = _resident.get(coord, {})
	else:
		if not _chunks.has(coord):
			return false
		pack = _chunks[coord]
	if pack.is_empty():
		return false
	var surface: PackedFloat32Array = pack.get("surface", PackedFloat32Array())
	var tiles: PackedInt32Array = pack.get("tiles", PackedInt32Array())
	if surface.size() != CELLS2 or tiles.size() != CELLS2:
		return false
	_apply_pack_to_data(data, surface, tiles)
	var us: int = Time.get_ticks_usec() - t0
	stats_bake_hits += 1
	stats_column_us_bake += us
	stats_column_samples_bake += 1
	last_column_source = "bake"
	return true


func record_generate_column_us(us: int) -> void:
	stats_generate_hits += 1
	stats_column_us_generate += us
	stats_column_samples_generate += 1
	last_column_source = "generate"


func record_blocked_generate() -> void:
	stats_blocked_generate += 1
	last_column_source = "blocked"


func avg_column_us_bake() -> float:
	if stats_column_samples_bake <= 0:
		return 0.0
	return float(stats_column_us_bake) / float(stats_column_samples_bake)


func avg_column_us_generate() -> float:
	if stats_column_samples_generate <= 0:
		return 0.0
	return float(stats_column_us_generate) / float(stats_column_samples_generate)


func sample_base(coord: Vector2i, lx: int, lz: int) -> Dictionary:
	if not has_chunk(coord):
		return {}
	if not ensure_chunk_resident(coord):
		return {}
	var pack: Dictionary = _resident.get(coord, _chunks.get(coord, {}))
	if pack.is_empty():
		return {}
	var surface: PackedFloat32Array = pack.get("surface", PackedFloat32Array())
	var tiles: PackedInt32Array = pack.get("tiles", PackedInt32Array())
	var i: int = lz * CELLS + lx
	if i < 0 or i >= CELLS2:
		return {}
	return {"surface": float(surface[i]), "tile": int(tiles[i])}


func corrupt_bake_file(seed: int, rad: int = -1) -> bool:
	# Corrupt one chunk package or the index.
	var dir := bake_dir_for(seed, rad if rad >= 0 else radius, false)
	var idx := dir.path_join("world.index")
	if FileAccess.file_exists(idx):
		var bytes := FileAccess.get_file_as_bytes(idx)
		if bytes.size() < 8:
			return false
		bytes[bytes.size() - 1] = bytes[bytes.size() - 1] ^ 0xFF
		var f := FileAccess.open(idx, FileAccess.WRITE)
		if f == null:
			return false
		f.store_buffer(bytes)
		f.close()
		return true
	return false


func corrupt_chunk_package(coord: Vector2i) -> bool:
	var path := chunk_package_path(coord)
	if not FileAccess.file_exists(path):
		return false
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 8:
		return false
	bytes[bytes.size() - 1] = bytes[bytes.size() - 1] ^ 0xFF
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.close()
	_resident.erase(coord)
	return true


func write_version_mismatch_stub(seed: int, rad: int = -1) -> String:
	var dir := bake_dir_for(seed, rad if rad >= 0 else SMOKE_DEFAULT_RADIUS, false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var index_path := dir.path_join("world.index")
	var f := FileAccess.open(index_path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_buffer(INDEX_MAGIC.to_utf8_buffer())
	f.store_32(BAKE_VERSION + 99)
	f.store_64(seed)
	f.store_64(-2)
	f.store_64(2)
	f.store_64(-2)
	f.store_64(2)
	f.store_32(FLAG_STREAMED)
	f.store_32(0)
	f.store_32(0)
	f.close()
	return index_path
