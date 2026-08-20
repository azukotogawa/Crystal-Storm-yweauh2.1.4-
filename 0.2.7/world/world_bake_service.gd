class_name WorldBakeService
extends RefCounted
## Streamed finite-world bake for Engine 1.0.
##
## Loading UI may connect to status_changed for real progress (mode + 0..1).
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
## When true, next bootstrap_for_world forces a full rebuild (loading UI "Rebuild World").
static var force_rebuild_next: bool = false

## mode: "idle"|"loading"|"generating"|"valid"|"error"
## progress: 0.0..1.0 (or -1 if unknown)
## message: human-readable status for loading UI
signal status_changed(mode: String, progress: float, message: String)

var world_seed: int = 0
## Last UI-facing status (loading screen can poll if signal missed).
var last_status_mode: String = "idle"
var last_status_progress: float = 0.0
var last_status_message: String = ""
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
## True while a deferred fill is running. `valid` stays false until world.index is written.
var bake_in_progress: bool = false
## Blocks WorldState.replace_active while a live fill/on-demand bake is happening.
var forbid_session_replace: bool = false
var _veg_by_chunk: Dictionary = {}
var _fill_queue: Array = []
var _fill_queue_i: int = 0
var _fill_inflight: Dictionary = {}
var _packages_known: Dictionary = {}
var _fill_host = null
var _fill_world = null
var _fill_started_ms: int = 0
var _fill_done: int = 0
var _fill_total: int = 0
var _prime_count: int = 0
## Measurement-only (gameplay profile). Does not change bake control flow.
var last_one_coord: Vector2i = Vector2i.ZERO
var last_one_sample_us: int = 0
var last_one_mesh_us: int = 0
var last_one_write_us: int = 0
var last_one_total_us: int = 0
var last_one_main_thread: bool = true
var last_one_source: String = ""
var last_tick_us: int = 0
var last_tick_ops: int = 0
var last_ondemand_us: int = 0
var bake_one_count: int = 0
var bake_one_history_us: PackedInt32Array = PackedInt32Array()
var bake_sample_history_us: PackedInt32Array = PackedInt32Array()
var bake_mesh_history_us: PackedInt32Array = PackedInt32Array()
var bake_write_history_us: PackedInt32Array = PackedInt32Array()
const BAKE_COST_HISTORY := 512
## Bounded worker fill (not 16,384 jobs at once).
const PRI_STREAM := 0
const PRI_NEARBY := 1
const PRI_FILL := 2
const MAX_INFLIGHT := 2
const MAX_PENDING := 12
var _job_pending: Array = []
var _job_pending_set: Dictionary = {}
var _job_inflight: Dictionary = {}
var _job_results: Dictionary = {}
var _job_mutex: Mutex = Mutex.new()
var _job_dup_rejects: int = 0
var worker_jobs_submitted: int = 0
var worker_jobs_completed: int = 0
var worker_inflight_peak: int = 0
var worker_util_samples: int = 0
var worker_util_sum: float = 0.0
const _WorldBakeWorkerJob = preload("res://world/world_bake_worker_job.gd")

## Resident only: Vector2i -> { surface, tiles, plan, vegetation }
var _resident: Dictionary = {}
## Lightweight surface/tile cache for halo sampling (no plan, no vegetation).
## Avoids synchronous full-package ensure_chunk_resident during capture_worker_snapshot.
var _surface_resident: Dictionary = {}
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
## Surface-only loads (halo path) vs full package loads (mesh/veg).
var stats_surface_disk_reads: int = 0
var stats_surface_disk_read_us: int = 0
var stats_full_package_loads: int = 0
var stats_sample_base_calls: int = 0
var stats_sample_base_surface_hits: int = 0
var stats_sample_base_full_hits: int = 0
var stats_sample_base_surface_loads: int = 0
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
	if _active != null and _active.has_method("_clear_job_queue"):
		_active._clear_job_queue()
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


## Default ON: prime start ring then fill in the background.
## Set CRYSTALSTORM_BAKE_DEFER_FILL=0 to restore await-full-bake before stream.
static func defer_fill_from_env() -> bool:
	var raw := OS.get_environment("CRYSTALSTORM_BAKE_DEFER_FILL").strip_edges().to_lower()
	if raw == "0" or raw == "false" or raw == "off":
		return false
	return true


## Default ON with defer-fill: package work runs on WorkerThreadPool.
## CRYSTALSTORM_BAKE_FILL_SYNC=1 restores the old main-thread 1-chunk/frame fill (profile B).
static func use_worker_fill_from_env() -> bool:
	var raw := OS.get_environment("CRYSTALSTORM_BAKE_FILL_SYNC").strip_edges().to_lower()
	if raw == "1" or raw == "true" or raw == "on":
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
	stats_surface_disk_reads = 0
	stats_surface_disk_read_us = 0
	stats_full_package_loads = 0
	stats_sample_base_calls = 0
	stats_sample_base_surface_hits = 0
	stats_sample_base_full_hits = 0
	stats_sample_base_surface_loads = 0
	last_column_source = ""


func package_load_stats() -> Dictionary:
	return {
		"disk_reads_full": stats_disk_reads,
		"disk_read_us_full": stats_disk_read_us,
		"surface_disk_reads": stats_surface_disk_reads,
		"surface_disk_read_us": stats_surface_disk_read_us,
		"full_package_loads": stats_full_package_loads,
		"sample_base_calls": stats_sample_base_calls,
		"sample_base_surface_hits": stats_sample_base_surface_hits,
		"sample_base_full_hits": stats_sample_base_full_hits,
		"sample_base_surface_loads": stats_sample_base_surface_loads,
		"resident_full": _resident.size(),
		"resident_surface": _surface_resident.size(),
	}


func clear_memory() -> void:
	_resident.clear()
	_surface_resident.clear()
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
	bake_in_progress = false
	forbid_session_replace = false
	_veg_by_chunk.clear()
	_fill_queue.clear()
	_fill_queue_i = 0
	_fill_inflight.clear()
	_packages_known.clear()
	_fill_host = null
	_fill_world = null
	_fill_done = 0
	_fill_total = 0
	_prime_count = 0
	_clear_job_queue()
	_job_dup_rejects = 0
	worker_jobs_submitted = 0
	worker_jobs_completed = 0
	worker_inflight_peak = 0
	worker_util_samples = 0
	worker_util_sum = 0.0


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


## Catalog metadata only. Does not mutate the active bake session or open packages.
static func inspect_disk_status(seed: int) -> Dictionary:
	var expected: int = int(full_world_chunk_bounds().get("chunks", 16384))
	var dir := "user://world_bakes/v%d_s%d_full" % [BAKE_VERSION, seed]
	var index_path := dir.path_join("world.index")
	var has_index := FileAccess.file_exists(index_path)
	var packages := 0
	var chunks_rel := dir.path_join("chunks")
	var abs_chunks := ProjectSettings.globalize_path(chunks_rel)
	if DirAccess.dir_exists_absolute(abs_chunks):
		var da := DirAccess.open(chunks_rel)
		if da:
			da.list_dir_begin()
			var n := da.get_next()
			while n != "":
				if not da.current_is_dir() and n.ends_with(".chk"):
					packages += 1
				n = da.get_next()
			da.list_dir_end()
	return {
		"seed": seed,
		"valid": has_index,
		"has_index": has_index,
		"packages": packages,
		"expected": expected,
		"incomplete": not has_index,
		"missing": packages == 0 and not has_index,
	}


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


func is_surface_resident(coord: Vector2i) -> bool:
	return _surface_resident.has(coord) or _resident.has(coord) or _chunks.has(coord)


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
	if package_ready(coord):
		return true
	if valid:
		return coord_in_package(coord)
	return false


func package_ready(coord: Vector2i) -> bool:
	if _resident.has(coord) or _chunks.has(coord):
		return true
	if _packages_known.has(coord):
		return true
	if package_dir.is_empty():
		return false
	if FileAccess.file_exists(chunk_package_path(coord)):
		_packages_known[coord] = true
		return true
	return false


func fill_status() -> Dictionary:
	return {
		"bake_in_progress": bake_in_progress,
		"valid": valid,
		"done": _fill_done,
		"total": _fill_total,
		"prime_count": _prime_count,
		"queue_remaining": maxi(_fill_queue.size() - _fill_queue_i, 0),
		"worker_inflight": _job_inflight.size(),
		"worker_pending": _job_pending.size(),
		"worker_submitted": worker_jobs_submitted,
		"worker_completed": worker_jobs_completed,
		"worker_util": worker_utilization(),
		"dup_rejects": _job_dup_rejects,
	}


func worker_utilization() -> float:
	if worker_util_samples <= 0:
		return 0.0
	return worker_util_sum / float(worker_util_samples)


func await_fill_complete() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var frames := 0
	while bake_in_progress and tree and frames < 200000:
		tick_background_fill()
		await tree.process_frame
		frames += 1


func _configure_session_bounds(world, rad: int) -> void:
	world_seed = int(world.world_seed) if world != null and "world_seed" in world else 0
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


func _inventory_existing_packages() -> void:
	_packages_known.clear()
	if package_dir.is_empty():
		return
	var chunks_rel := package_dir.path_join("chunks")
	var abs_dir := ProjectSettings.globalize_path(chunks_rel)
	if not DirAccess.dir_exists_absolute(abs_dir):
		return
	var da := DirAccess.open(chunks_rel)
	if da == null:
		return
	da.list_dir_begin()
	var n := da.get_next()
	while n != "":
		if not da.current_is_dir() and n.ends_with(".chk"):
			var stem := n.substr(0, n.length() - 4)
			var parts: PackedStringArray = stem.split("_")
			if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
				_packages_known[Vector2i(parts[0].to_int(), parts[1].to_int())] = true
		n = da.get_next()
	da.list_dir_end()


func _add_stream_ring(out: Dictionary, cx: int, cz: int, rd: int) -> void:
	for z in range(cz - rd, cz + rd + 2):
		for x in range(cx - rd, cx + rd + 2):
			var c := Vector2i(x, z)
			if coord_in_package(c):
				out[c] = true


func startup_prime_coords(host) -> Array:
	var out: Dictionary = {}
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var oc := Vector2i(dx, dz)
			if coord_in_package(oc):
				out[oc] = true
	var rd := 3
	if host != null and "RENDER_DISTANCE" in host:
		rd = maxi(int(host.RENDER_DISTANCE), 1)
	_add_stream_ring(out, 0, 0, rd)
	# Same spawn-ring columns as Player._resolve_spawn_column, plus their stream rings.
	for dist in [56, 52, 60, 48, 64, 44]:
		var cols: Array[Vector2i] = [
			Vector2i(dist, 0), Vector2i(-dist, 0), Vector2i(0, dist), Vector2i(0, -dist),
			Vector2i(dist, -dist / 2), Vector2i(-dist, dist / 2),
			Vector2i(dist / 2, dist), Vector2i(-dist / 2, -dist),
		]
		for col in cols:
			var cc := Vector2i(
				int(floor(float(col.x) / float(CELLS))),
				int(floor(float(col.y) / float(CELLS)))
			)
			_add_stream_ring(out, cc.x, cc.y, rd)
	return out.keys()


func _bake_one_chunk(coord: Vector2i, world, mesh_host, veg: Array = []) -> Dictionary:
	if world == null or mesh_host == null or not mesh_host.has_method("_build_mesh"):
		return {"ok": false, "bytes": 0, "plan_qn": 0}
	if _fill_inflight.has(coord) or _job_inflight.has(coord):
		return {"ok": false, "bytes": 0, "plan_qn": 0, "busy": true}
	_fill_inflight[coord] = true
	var one: Dictionary = _WorldBakeWorkerJob.execute(coord, world, mesh_host, veg, self)
	_fill_inflight.erase(coord)
	_record_bake_result(coord, one, last_one_source if not last_one_source.is_empty() else "sync")
	if bool(one.get("ok", false)):
		_register_package(coord)
	return one


func _note_bake_cost_history() -> void:
	if bake_one_history_us.size() >= BAKE_COST_HISTORY:
		bake_one_history_us = bake_one_history_us.slice(bake_one_history_us.size() - BAKE_COST_HISTORY + 1)
		bake_sample_history_us = bake_sample_history_us.slice(bake_sample_history_us.size() - BAKE_COST_HISTORY + 1)
		bake_mesh_history_us = bake_mesh_history_us.slice(bake_mesh_history_us.size() - BAKE_COST_HISTORY + 1)
		bake_write_history_us = bake_write_history_us.slice(bake_write_history_us.size() - BAKE_COST_HISTORY + 1)
	bake_one_history_us.append(last_one_total_us)
	bake_sample_history_us.append(last_one_sample_us)
	bake_mesh_history_us.append(last_one_mesh_us)
	bake_write_history_us.append(last_one_write_us)


func last_bake_cost() -> Dictionary:
	return {
		"coord": [last_one_coord.x, last_one_coord.y],
		"sample_us": last_one_sample_us,
		"mesh_us": last_one_mesh_us,
		"write_us": last_one_write_us,
		"total_us": last_one_total_us,
		"main_thread": last_one_main_thread,
		"source": last_one_source,
		"tick_us": last_tick_us,
		"tick_ops": last_tick_ops,
		"ondemand_us": last_ondemand_us,
		"count": bake_one_count,
	}


func _record_bake_result(coord: Vector2i, one: Dictionary, source: String) -> void:
	last_one_coord = coord
	last_one_sample_us = int(one.get("sample_us", 0))
	last_one_mesh_us = int(one.get("mesh_us", 0))
	last_one_write_us = int(one.get("write_us", 0))
	last_one_total_us = int(one.get("total_us", 0))
	last_one_main_thread = bool(one.get("main_thread", true))
	last_one_source = source
	if bool(one.get("ok", false)):
		bake_one_count += 1
		_note_bake_cost_history()


func _register_package(coord: Vector2i) -> void:
	_packages_known[coord] = true
	_fill_done = _packages_known.size()


func _clear_job_queue() -> void:
	for coord in _job_inflight.keys():
		var tid: int = int(_job_inflight[coord])
		WorkerThreadPool.wait_for_task_completion(tid)
	_job_pending.clear()
	_job_pending_set.clear()
	_job_inflight.clear()
	_job_mutex.lock()
	_job_results.clear()
	_job_mutex.unlock()


func enqueue_package_job(coord: Vector2i, priority: int = PRI_FILL) -> Dictionary:
	if package_ready(coord):
		return {"ok": true, "ready": true, "duplicate": false, "queued": false}
	if not coord_in_package(coord):
		return {"ok": false, "ready": false, "duplicate": false, "queued": false}
	if _job_inflight.has(coord) or _job_pending_set.has(coord) or _fill_inflight.has(coord):
		_job_dup_rejects += 1
		return {"ok": true, "ready": false, "duplicate": true, "queued": true}
	if priority > PRI_STREAM and _job_pending.size() >= MAX_PENDING:
		return {"ok": false, "ready": false, "duplicate": false, "queued": false, "bounded": true}
	var veg: Array = (_veg_by_chunk.get(coord, []) as Array).duplicate(true)
	var item := {"coord": coord, "priority": priority, "veg": veg}
	if priority == PRI_STREAM:
		_job_pending.push_front(item)
	else:
		var inserted := false
		for i in _job_pending.size():
			if int(_job_pending[i].get("priority", PRI_FILL)) > priority:
				_job_pending.insert(i, item)
				inserted = true
				break
		if not inserted:
			_job_pending.append(item)
	_job_pending_set[coord] = true
	return {"ok": true, "ready": false, "duplicate": false, "queued": true}


func _pump_jobs(allow_fill: bool = true) -> void:
	while _job_inflight.size() < MAX_INFLIGHT and not _job_pending.is_empty():
		var item: Dictionary = _job_pending[0]
		var pri: int = int(item.get("priority", PRI_FILL))
		if pri >= PRI_FILL and not allow_fill:
			break
		_job_pending.pop_front()
		var coord: Vector2i = item.get("coord", Vector2i.ZERO)
		_job_pending_set.erase(coord)
		if package_ready(coord):
			continue
		_submit_pool_job(coord, pri, item.get("veg", []))


func _submit_pool_job(coord: Vector2i, priority: int, veg: Array) -> void:
	var mesh_host = _resolve_mesh_host(_fill_host, _fill_world)
	if mesh_host == null or _fill_world == null:
		return
	var high_pri: bool = priority <= PRI_NEARBY
	var tid: int = WorkerThreadPool.add_task(
		Callable(self, "_pool_bake_task").bind(coord, _fill_world, mesh_host, veg),
		high_pri
	)
	_job_inflight[coord] = tid
	worker_jobs_submitted += 1
	worker_inflight_peak = maxi(worker_inflight_peak, _job_inflight.size())


func _pool_bake_task(coord: Vector2i, world, mesh_host, veg: Array) -> void:
	var one: Dictionary = _WorldBakeWorkerJob.execute(coord, world, mesh_host, veg, self)
	_job_mutex.lock()
	_job_results[coord] = one
	_job_mutex.unlock()


func _collect_jobs() -> int:
	var collected := 0
	var done_coords: Array = []
	for coord in _job_inflight.keys():
		var tid: int = int(_job_inflight[coord])
		if WorkerThreadPool.is_task_completed(tid):
			done_coords.append(coord)
	for coord_v in done_coords:
		var coord: Vector2i = coord_v
		var tid: int = int(_job_inflight[coord])
		WorkerThreadPool.wait_for_task_completion(tid)
		_job_inflight.erase(coord)
		_job_mutex.lock()
		var one: Dictionary = _job_results.get(coord, {})
		_job_results.erase(coord)
		_job_mutex.unlock()
		_record_bake_result(coord, one, last_one_source if last_one_source == "ondemand" else "background")
		if bool(one.get("ok", false)):
			_register_package(coord)
			collected += 1
			worker_jobs_completed += 1
		var profiler = _profiler_if_any()
		if profiler and profiler.has_method("record_worker_us") and int(one.get("total_us", 0)) > 0:
			profiler.record_worker_us(int(one.get("total_us", 0)))
	return collected


func _profiler_if_any():
	var loop = Engine.get_main_loop()
	if loop == null:
		return null
	return loop.root.get_node_or_null("/root/PerfProfiler")


func _wait_job(coord: Vector2i) -> bool:
	if not _job_inflight.has(coord):
		return package_ready(coord)
	var tid: int = int(_job_inflight[coord])
	WorkerThreadPool.wait_for_task_completion(tid)
	_job_inflight.erase(coord)
	_job_mutex.lock()
	var one: Dictionary = _job_results.get(coord, {})
	_job_results.erase(coord)
	_job_mutex.unlock()
	_record_bake_result(coord, one, "ondemand")
	if bool(one.get("ok", false)):
		_register_package(coord)
		worker_jobs_completed += 1
		return true
	return package_ready(coord)


func prime_region(coords: Array, world, host) -> Dictionary:
	var mesh_host = _resolve_mesh_host(host, world)
	if mesh_host == null or not mesh_host.has_method("_build_mesh"):
		return {"ok": false, "baked": 0, "skipped": 0, "error": "no mesh host"}
	var baked := 0
	var skipped := 0
	var bytes_written := 0
	var plan_qn := 0
	for c_v in coords:
		var coord: Vector2i = c_v
		if not coord_in_package(coord):
			continue
		if package_ready(coord):
			skipped += 1
			continue
		var veg: Array = _veg_by_chunk.get(coord, [])
		var one: Dictionary = _bake_one_chunk(coord, world, mesh_host, veg)
		if bool(one.get("ok", false)):
			baked += 1
			bytes_written += int(one.get("bytes", 0))
			plan_qn += int(one.get("plan_qn", 0))
	_prime_count = baked + skipped
	return {
		"ok": true,
		"baked": baked,
		"skipped": skipped,
		"bytes": bytes_written,
		"plan_qn": plan_qn,
	}


func start_background_fill(world, host) -> void:
	_fill_world = world
	_fill_host = host
	_fill_queue.clear()
	_fill_queue_i = 0
	_fill_done = _packages_known.size()
	_fill_total = expected_chunk_count()
	for cz in range(min_cz, max_cz + 1):
		for cx in range(min_cx, max_cx + 1):
			var c := Vector2i(cx, cz)
			if not _packages_known.has(c):
				_fill_queue.append(c)
	if _fill_queue.is_empty():
		_try_commit_index()
		return
	bake_in_progress = true
	forbid_session_replace = true
	_fill_started_ms = Time.get_ticks_msec()
	_emit_status(
		"generating",
		float(_fill_done) / float(maxi(_fill_total, 1)),
		"Generating World... %d / %d chunks" % [_fill_done, _fill_total]
	)


func tick_background_fill(mesh_queue_depth: int = 0) -> int:
	var t_tick := Time.get_ticks_usec()
	last_tick_ops = _collect_jobs()
	worker_util_samples += 1
	worker_util_sum += float(_job_inflight.size()) / float(maxi(MAX_INFLIGHT, 1))
	if not bake_in_progress:
		last_tick_us = Time.get_ticks_usec() - t_tick
		return last_tick_ops
	if _save_transaction_active():
		last_tick_us = Time.get_ticks_usec() - t_tick
		return last_tick_ops
	if not use_worker_fill_from_env():
		last_tick_ops += _tick_sync_fill_one()
		last_tick_us = Time.get_ticks_usec() - t_tick
		return last_tick_ops
	var allow_fill: bool = mesh_queue_depth <= 8
	if allow_fill:
		while (_job_pending.size() + _job_inflight.size()) < MAX_PENDING \
				and _fill_queue_i < _fill_queue.size():
			var coord: Vector2i = _fill_queue[_fill_queue_i]
			_fill_queue_i += 1
			if package_ready(coord):
				continue
			enqueue_package_job(coord, _fill_priority_for(coord))
	_pump_jobs(allow_fill)
	_fill_done = _packages_known.size()
	if _fill_done == 1 or _fill_done % maxi(_fill_total / 40, 1) == 0 \
			or (_fill_queue_i >= _fill_queue.size() and _job_inflight.is_empty() and _job_pending.is_empty()):
		_emit_status(
			"generating",
			float(_fill_done) / float(maxi(_fill_total, 1)),
			"Generating World... %d / %d chunks" % [_fill_done, _fill_total]
		)
	if _fill_queue_i >= _fill_queue.size() and _job_inflight.is_empty() and _job_pending.is_empty():
		_try_commit_index()
	last_tick_us = Time.get_ticks_usec() - t_tick
	return last_tick_ops


func _tick_sync_fill_one() -> int:
	if _fill_queue_i >= _fill_queue.size():
		_try_commit_index()
		return 0
	var coord: Vector2i = _fill_queue[_fill_queue_i]
	_fill_queue_i += 1
	if package_ready(coord):
		_fill_done = _packages_known.size()
		if _fill_queue_i >= _fill_queue.size():
			_try_commit_index()
		return 0
	last_one_source = "background"
	var mesh_host = _resolve_mesh_host(_fill_host, _fill_world)
	var veg: Array = _veg_by_chunk.get(coord, [])
	var one: Dictionary = _bake_one_chunk(coord, _fill_world, mesh_host, veg)
	if bool(one.get("ok", false)):
		_fill_done = _packages_known.size()
	if _fill_queue_i >= _fill_queue.size():
		_try_commit_index()
	var profiler = _profiler_if_any()
	if profiler and profiler.has_method("record_us") and bool(one.get("ok", false)):
		profiler.record_us("bake_one_chunk", last_one_total_us)
	return 1 if bool(one.get("ok", false)) else 0


func ensure_package_for_stream(coord: Vector2i) -> bool:
	if package_ready(coord):
		return true
	if not coord_in_package(coord):
		return false
	if valid:
		return false
	if not bake_in_progress and _veg_by_chunk.is_empty():
		return false
	var t0 := Time.get_ticks_usec()
	last_one_source = "ondemand"
	if not use_worker_fill_from_env():
		var mesh_host = _resolve_mesh_host(_fill_host, _fill_world)
		var veg: Array = _veg_by_chunk.get(coord, [])
		var one: Dictionary = _bake_one_chunk(coord, _fill_world, mesh_host, veg)
		last_ondemand_us = Time.get_ticks_usec() - t0
		return bool(one.get("ok", false))
	if _job_inflight.has(coord):
		var ok_wait: bool = _wait_job(coord)
		last_ondemand_us = Time.get_ticks_usec() - t0
		return ok_wait
	enqueue_package_job(coord, PRI_STREAM)
	_force_submit_stream(coord)
	if _job_inflight.has(coord):
		var ok2: bool = _wait_job(coord)
		last_ondemand_us = Time.get_ticks_usec() - t0
		return ok2
	last_ondemand_us = Time.get_ticks_usec() - t0
	return package_ready(coord)


func _fill_priority_for(coord: Vector2i) -> int:
	if _fill_host == null:
		return PRI_FILL
	var player = _fill_host.get("player") if "player" in _fill_host else null
	if player == null:
		return PRI_FILL
	var col: Vector3 = player.get_voxel_position() if player.has_method("get_voxel_position") else Vector3.ZERO
	var pcx := int(floor(col.x / float(CELLS)))
	var pcz := int(floor(col.z / float(CELLS)))
	if maxi(absi(coord.x - pcx), absi(coord.y - pcz)) <= 3:
		return PRI_NEARBY
	return PRI_FILL


func _force_submit_stream(coord: Vector2i) -> void:
	if _job_inflight.has(coord) or package_ready(coord):
		return
	var idx := -1
	for i in _job_pending.size():
		if _job_pending[i].get("coord", Vector2i.ZERO) == coord:
			idx = i
			break
	if idx < 0:
		_pump_jobs(true)
		return
	var item: Dictionary = _job_pending[idx]
	_job_pending.remove_at(idx)
	_job_pending_set.erase(coord)
	_submit_pool_job(coord, PRI_STREAM, item.get("veg", []))


func _try_commit_index() -> bool:
	if valid:
		bake_in_progress = false
		forbid_session_replace = false
		return true
	var expected: int = expected_chunk_count()
	if _packages_known.size() < expected:
		# Recount from disk in case of resume.
		_inventory_existing_packages()
	if _packages_known.size() < expected:
		return false
	vegetation_baked = true
	valid = true
	var saved: Dictionary = save_bake()
	if not bool(saved.get("ok", false)):
		valid = false
		last_error = str(saved.get("error", "index commit failed"))
		return false
	bake_in_progress = false
	forbid_session_replace = false
	log_valid_bake(validate_loaded_bake(world_seed, full_world))
	_emit_status("valid", 1.0, "Loading World...")
	print(
		"[WorldBake] Deferred fill complete packages=%d bake_ms=%s"
		% [_packages_known.size(), str(Time.get_ticks_msec() - _fill_started_ms)]
	)
	return true


func _save_transaction_active() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var save = tree.get_first_node_in_group("save_game_service")
	if save != null and save.has_method("is_transaction_active"):
		return bool(save.is_transaction_active())
	return false


func _bootstrap_deferred_async(world, host, seed: int, want_full: bool) -> Dictionary:
	_configure_session_bounds(world, -1 if want_full else smoke_radius_from_env())
	valid = false
	vegetation_baked = false
	bake_in_progress = false
	_resident.clear()
	_surface_resident.clear()
	_chunks.clear()
	_inventory_existing_packages()
	var veg_t0 := Time.get_ticks_msec()
	_veg_by_chunk = _bake_vegetation_by_chunk(world)
	last_vegetation_bake_ms = Time.get_ticks_msec() - veg_t0
	last_vegetation_entries = 0
	for ck in _veg_by_chunk.keys():
		last_vegetation_entries += (_veg_by_chunk[ck] as Array).size()
	var prime_coords: Array = startup_prime_coords(host)
	var primed: Dictionary = prime_region(prime_coords, world, host)
	start_background_fill(world, host)
	var mode := "partial"
	if valid:
		mode = "baked"
	return {
		"ok": true,
		"mode": mode,
		"seed": seed,
		"full_world": full_world,
		"streamed": streamed,
		"bounds": bounds_dict(),
		"chunks": _packages_known.size(),
		"expected_chunks": expected_chunk_count(),
		"prime": primed,
		"fill": fill_status(),
		"bake_ms": last_vegetation_bake_ms,
		"bytes": 0,
		"mesh_plan": {"mode": "streamed", "chunks": _packages_known.size()},
		"validation": {"ok": valid},
	}


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
	_surface_resident.clear()
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


func _emit_status(mode: String, progress: float, message: String) -> void:
	last_status_mode = mode
	last_status_progress = progress
	last_status_message = message
	status_changed.emit(mode, progress, message)


## Public alias for loading UI / WorldFeatures (presentation only).
func notify_ui_status(mode: String, progress: float, message: String) -> void:
	_emit_status(mode, progress, message)


func bootstrap_for_world(world, force_bake: bool = false, host = null) -> Dictionary:
	if world == null:
		return {"ok": false, "error": "no world"}
	if force_rebuild_next:
		force_bake = true
		force_rebuild_next = false
	if not bake_enabled_from_env() and not force_bake:
		clear_memory()
		_emit_status("idle", 1.0, "World bake disabled")
		return {"ok": true, "mode": "disabled"}
	var seed: int = int(world.world_seed) if "world_seed" in world else 0
	set_active(self)
	var want_full := use_full_world_from_env()
	var loaded := false
	_emit_status("loading", 0.05, "Loading World...")
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
				_emit_status("valid", 1.0, "Loading World...")
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
			_emit_status(
				"generating",
				0.1,
				"Generating World... This only happens the first time you play or after major world updates."
			)
		else:
			# Only mesh-plan issues → try repair before full rebuild.
			var reasons: PackedStringArray = validation.get("reasons", PackedStringArray())
			var only_plans := _reasons_only_mesh_plan(reasons)
			if only_plans and host != null:
				print("[WorldBake] Mesh plans incomplete — repairing once and writing to disk...")
				_emit_status("generating", 0.15, "Repairing mesh plans...")
				var plan_info2: Dictionary = ensure_mesh_plans(host, world, true)
				validation = validate_loaded_bake(seed, want_full)
				if bool(validation.get("ok", false)):
					log_valid_bake(validation)
					_emit_status("valid", 1.0, "Loading World...")
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
			_emit_status(
				"generating",
				0.1,
				"Generating World... This only happens the first time you play or after major world updates."
			)
	else:
		var miss_reasons: PackedStringArray = PackedStringArray()
		if last_error.is_empty():
			miss_reasons.append("no_bake_for_seed")
		else:
			miss_reasons.append(last_error)
		log_invalid_bake(miss_reasons)
		_emit_status(
			"generating",
			0.05,
			"Generating World... This only happens the first time you play or after major world updates."
		)

	if force_bake or bake_on_new_from_env():
		# Production auto-bake: full world unless smoke radius override is set.
		var rad: int = -1
		if not want_full:
			rad = smoke_radius_from_env()
		_emit_status(
			"generating",
			0.12,
			"Generating World... This only happens the first time you play or after major world updates."
		)
		var baked: Dictionary = bake_world(world, rad, host)
		return _finish_bootstrap_after_bake(baked, seed, want_full, host)
	clear_memory()
	return {"ok": true, "mode": "miss", "seed": seed}


## Async production path: cooperative bake so loading UI stays responsive (128×128).
func bootstrap_for_world_async(world, force_bake: bool = false, host = null) -> Dictionary:
	var _STP = load("res://systems/startup_total_profiler.gd")
	if _STP and _STP.is_enabled():
		_STP.begin("WorldBakeService.bootstrap_for_world_async", "bake_package_loading")
	if world == null:
		return {"ok": false, "error": "no world"}
	if force_rebuild_next:
		force_bake = true
		force_rebuild_next = false
	if not bake_enabled_from_env() and not force_bake:
		clear_memory()
		_emit_status("idle", 1.0, "World bake disabled")
		if _STP and _STP.is_enabled():
			_STP.end("WorldBakeService.bootstrap_for_world_async", {"mode": "disabled"})
		return {"ok": true, "mode": "disabled"}
	var seed: int = int(world.world_seed) if "world_seed" in world else 0
	set_active(self)
	var want_full := use_full_world_from_env()
	var loaded := false
	_emit_status("loading", 0.05, "Loading World...")
	if not force_bake:
		var t_load := Time.get_ticks_usec()
		loaded = load_bake_for_seed(seed, want_full)
		if _STP and _STP.is_enabled():
			_STP.add_us("index_load_us", Time.get_ticks_usec() - t_load)
			_STP.event("bake.load_bake_for_seed", {
				"loaded": loaded,
				"want_full": want_full,
				"seed": seed,
				"package_dir": package_dir,
				"valid": valid,
				"us": Time.get_ticks_usec() - t_load,
			}, "disk_io")
	var validation: Dictionary = {}
	if loaded:
		var t_val := Time.get_ticks_usec()
		validation = validate_loaded_bake(seed, want_full)
		if _STP and _STP.is_enabled():
			_STP.add_us("validate_us", Time.get_ticks_usec() - t_val)
			_STP.event("bake.validate_loaded_bake", {
				"ok": bool(validation.get("ok", false)),
				"reasons": validation.get("reasons", PackedStringArray()),
				"chunks": validation.get("chunks", 0),
				"us": Time.get_ticks_usec() - t_val,
			}, "disk_io")
		if bool(validation.get("ok", false)):
			var plan_info: Dictionary = ensure_mesh_plans(host, world)
			if str(plan_info.get("mode", "")) == "repaired":
				validation = validate_loaded_bake(seed, want_full)
			if bool(validation.get("ok", false)):
				log_valid_bake(validation)
				_emit_status("valid", 1.0, "Loading World...")
				if _STP and _STP.is_enabled():
					_STP.set_gauge("mode", "loaded")
					_STP.end("WorldBakeService.bootstrap_for_world_async", {"mode": "loaded"})
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
			var reasons2: PackedStringArray = validation.get("reasons", PackedStringArray())
			log_invalid_bake(reasons2)
			_emit_status(
				"generating",
				0.1,
				"Generating World... This only happens the first time you play or after major world updates."
			)
		else:
			var reasons: PackedStringArray = validation.get("reasons", PackedStringArray())
			var only_plans := _reasons_only_mesh_plan(reasons)
			if only_plans and host != null:
				print("[WorldBake] Mesh plans incomplete — repairing once and writing to disk...")
				_emit_status("generating", 0.15, "Repairing mesh plans...")
				var plan_info2: Dictionary = ensure_mesh_plans(host, world, true)
				validation = validate_loaded_bake(seed, want_full)
				if bool(validation.get("ok", false)):
					log_valid_bake(validation)
					_emit_status("valid", 1.0, "Loading World...")
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
			_emit_status(
				"generating",
				0.1,
				"Generating World... This only happens the first time you play or after major world updates."
			)
	else:
		var miss_reasons: PackedStringArray = PackedStringArray()
		if last_error.is_empty():
			miss_reasons.append("no_bake_for_seed")
		else:
			miss_reasons.append(last_error)
		log_invalid_bake(miss_reasons)
		_emit_status(
			"generating",
			0.05,
			"Generating World... This only happens the first time you play or after major world updates."
		)

	if force_bake or bake_on_new_from_env():
		var rad: int = -1
		if not want_full:
			rad = smoke_radius_from_env()
		_emit_status(
			"generating",
			0.12,
			"Generating World... This only happens the first time you play or after major world updates."
		)
		if defer_fill_from_env():
			if _STP and _STP.is_enabled():
				_STP.set_gauge("mode", "partial")
				_STP.event("bake.deferred_prime.enter", {"want_full": want_full, "seed": seed}, "world_generation")
			var partial: Dictionary = _bootstrap_deferred_async(world, host, seed, want_full)
			if _STP and _STP.is_enabled():
				_STP.event("bake.deferred_prime.exit", {
					"mode": str(partial.get("mode", "")),
					"chunks": partial.get("chunks", 0),
					"valid": valid,
				}, "world_generation")
				_STP.end("WorldBakeService.bootstrap_for_world_async", {"mode": str(partial.get("mode", "partial"))})
			return partial
		if _STP and _STP.is_enabled():
			_STP.set_gauge("mode", "baking")
			_STP.event("bake.bake_world_async.enter", {"want_full": want_full, "rad": rad, "seed": seed}, "world_generation")
		var baked: Dictionary = await bake_world_async(world, rad, host)
		var finished: Dictionary = _finish_bootstrap_after_bake(baked, seed, want_full, host)
		if _STP and _STP.is_enabled():
			_STP.set_gauge("mode", "baked")
			_STP.event("bake.bake_world_async.exit", {
				"ok": bool(finished.get("ok", false)),
				"bake_ms": finished.get("bake_ms", 0),
				"chunks": finished.get("chunks", 0),
				"bytes": finished.get("bytes", 0),
			}, "world_generation")
			_STP.end("WorldBakeService.bootstrap_for_world_async", {"mode": "baked"})
		return finished
	clear_memory()
	if _STP and _STP.is_enabled():
		_STP.set_gauge("mode", "miss")
		_STP.end("WorldBakeService.bootstrap_for_world_async", {"mode": "miss"})
	return {"ok": true, "mode": "miss", "seed": seed}


func _finish_bootstrap_after_bake(
	baked: Dictionary, seed: int, want_full: bool, host
) -> Dictionary:
	if not bool(baked.get("ok", false)):
		return baked
	var saved: Dictionary = save_bake()
	var world_ref = null
	if host != null and "world" in host:
		world_ref = host.world
	# One-shot plan refresh for live town/ruin stamps after offline bake, then persist meta.
	var post_plans: Dictionary = ensure_mesh_plans(host, world_ref, false)
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
		_surface_resident.clear()
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
	_surface_resident.clear()
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
	_surface_resident.clear()
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
	_veg_by_chunk = veg_by_chunk
	set_active(self)

	var total_chunks: int = maxi((max_cx - min_cx + 1) * (max_cz - min_cz + 1), 1)
	var progress_emit_every: int = maxi(total_chunks / 40, 1)
	for cz in range(min_cz, max_cz + 1):
		for cx in range(min_cx, max_cx + 1):
			var coord := Vector2i(cx, cz)
			var veg: Array = veg_by_chunk.get(coord, [])
			var one: Dictionary = _bake_one_chunk(coord, world, mesh_host, veg)
			plan_qn_total += int(one.get("plan_qn", 0))
			if bool(one.get("ok", false)):
				plan_count += 1
			bytes_written += int(one.get("bytes", 0))
			count += 1
			if count == 1 or count % progress_emit_every == 0 or count >= total_chunks:
				var p: float = clampf(float(count) / float(total_chunks), 0.0, 1.0)
				_emit_status(
					"generating",
					0.15 + p * 0.8,
					"Generating World... %d / %d chunks" % [count, total_chunks]
				)

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
	_surface_resident.clear()
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


## Cooperative bake for production boot / loading UI: yields to SceneTree so the
## main loop can process frames (progress bar, avoid "frozen" window).
## Same packages/determinism as bake_world; only scheduling differs.
func bake_world_async(world, rad: int = -1, host = null) -> Dictionary:
	if world == null:
		last_error = "bake_world: null world"
		valid = false
		return {"ok": false, "error": last_error}
	var t0 := Time.get_ticks_msec()
	world_seed = int(world.world_seed) if "world_seed" in world else 0
	valid = false
	vegetation_baked = false
	_resident.clear()
	_surface_resident.clear()
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

	_emit_status("generating", 0.12, "Generating World... preparing vegetation...")
	var tree := Engine.get_main_loop() as SceneTree
	var _STP = load("res://systems/startup_total_profiler.gd")
	var prof_on: bool = _STP != null and _STP.is_enabled()
	if tree:
		await tree.process_frame

	if prof_on:
		_STP.begin("bake.vegetation_scatter", "vegetation_generation")
	var veg_t0 := Time.get_ticks_msec()
	var veg_by_chunk: Dictionary = _bake_vegetation_by_chunk(world)
	last_vegetation_bake_ms = Time.get_ticks_msec() - veg_t0
	last_vegetation_entries = 0
	for ck in veg_by_chunk.keys():
		last_vegetation_entries += (veg_by_chunk[ck] as Array).size()
	if prof_on:
		_STP.add_us("vegetation_us", last_vegetation_bake_ms * 1000)
		_STP.end("bake.vegetation_scatter", {
			"vegetation_ms": last_vegetation_bake_ms,
			"entries": last_vegetation_entries,
		})
	if tree:
		await tree.process_frame

	var count := 0
	var plan_count := 0
	var plan_qn_total := 0
	var bytes_written := 0
	var mesh_host = _resolve_mesh_host(host, world)
	var co_mesh: bool = mesh_host != null and mesh_host.has_method("_build_mesh")
	if not co_mesh:
		last_error = "bake_world: cannot resolve mesh host for plans"
		valid = false
		return {"ok": false, "error": last_error}
	_veg_by_chunk = veg_by_chunk
	set_active(self)

	var total_chunks: int = maxi((max_cx - min_cx + 1) * (max_cz - min_cz + 1), 1)
	var progress_emit_every: int = maxi(total_chunks / 40, 1)
	# Yield often enough for UI; denser for huge full-world bakes.
	var yield_every: int = 4 if total_chunks > 1000 else maxi(progress_emit_every, 1)
	if prof_on:
		_STP.set_gauge("chunks_total", total_chunks)
		_STP.begin("bake.chunk_loop", "world_generation")
	for cz in range(min_cz, max_cz + 1):
		for cx in range(min_cx, max_cx + 1):
			var coord := Vector2i(cx, cz)
			var veg: Array = veg_by_chunk.get(coord, [])
			var t_one := Time.get_ticks_usec() if prof_on else 0
			var one: Dictionary = _bake_one_chunk(coord, world, mesh_host, veg)
			if prof_on:
				_STP.add_us("mesh_plan_us", Time.get_ticks_usec() - t_one)
			plan_qn_total += int(one.get("plan_qn", 0))
			if bool(one.get("ok", false)):
				plan_count += 1
			bytes_written += int(one.get("bytes", 0))
			count += 1
			if prof_on:
				_STP.note_bake_progress(count, total_chunks)
			if count == 1 or count % progress_emit_every == 0 or count >= total_chunks:
				var p: float = clampf(float(count) / float(total_chunks), 0.0, 1.0)
				_emit_status(
					"generating",
					0.15 + p * 0.8,
					"Generating World... %d / %d chunks" % [count, total_chunks]
				)
			if tree and (count % yield_every == 0):
				var t_y := Time.get_ticks_usec() if prof_on else 0
				await tree.process_frame
				if prof_on:
					_STP.add_us("yield_wait_us", Time.get_ticks_usec() - t_y)

	if prof_on:
		_STP.end("bake.chunk_loop", {"chunks": count, "bytes": bytes_written})

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
	_resident.clear()
	_surface_resident.clear()
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
	var tmp_path := path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("WorldBake: failed to write %s" % tmp_path)
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
	var abs_tmp := ProjectSettings.globalize_path(tmp_path)
	var abs_final := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(abs_final)
	var renamed := DirAccess.rename_absolute(abs_tmp, abs_final)
	if renamed != OK:
		# Fallback: copy bytes if rename is blocked.
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(tmp_path)
		var out := FileAccess.open(path, FileAccess.WRITE)
		if out:
			out.store_buffer(bytes)
			out.close()
		DirAccess.remove_absolute(abs_tmp)
	if FileAccess.file_exists(path):
		return int(FileAccess.get_file_as_bytes(path).size())
	return 0


func _read_chunk_package(coord: Vector2i) -> Dictionary:
	var path := chunk_package_path(coord)
	var t0 := Time.get_ticks_usec()
	var leaf: Dictionary = {} if _res_measure else {}
	var SPP = load("res://systems/stream_phase_profiler.gd")
	var spp_on: bool = SPP != null and SPP.is_enabled()
	var t_leaf := Time.get_ticks_usec() if _res_measure else 0
	if not FileAccess.file_exists(path):
		last_error = "missing chunk package %s" % path
		stats_missing_package_errors += 1
		return {}
	if _res_measure:
		_res_add("file_exists", Time.get_ticks_usec() - t_leaf)
		t_leaf = Time.get_ticks_usec()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		last_error = "open failed %s" % path
		stats_missing_package_errors += 1
		return {}
	if _res_measure:
		_res_add("file_open", Time.get_ticks_usec() - t_leaf)
		t_leaf = Time.get_ticks_usec()
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
	if _res_measure:
		_res_add("header_parse", Time.get_ticks_usec() - t_leaf)
		t_leaf = Time.get_ticks_usec()
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
	var col_us: int = Time.get_ticks_usec() - t_leaf if _res_measure else 0
	if _res_measure:
		_res_add("column_surface_tiles_loop", col_us)
		leaf["column_loop_us"] = col_us
		t_leaf = Time.get_ticks_usec()
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
	if _res_measure:
		_res_add("get_var_plan", Time.get_ticks_usec() - t_leaf)
		leaf["plan_us"] = Time.get_ticks_usec() - t_leaf
		leaf["plan_quads"] = qn
		t_leaf = Time.get_ticks_usec()
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
		if _res_measure:
			_res_add("get_var_vegetation", Time.get_ticks_usec() - t_leaf)
			leaf["veg_us"] = Time.get_ticks_usec() - t_leaf
			leaf["veg_n"] = vn
			t_leaf = Time.get_ticks_usec()
	var file_cs: int = int(f.get_32())
	f.close()
	if _res_measure:
		_res_add("file_close_trailer", Time.get_ticks_usec() - t_leaf)
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
	if _res_measure:
		leaf["total_read_us"] = Time.get_ticks_usec() - t0
		leaf["deser_us"] = deser_us
		leaf["file_read_us"] = file_read_us
		leaf["coord"] = [coord.x, coord.y]
		if int(leaf.get("total_read_us", 0)) >= int(_res_worst.get("read_total_us", 0)):
			_res_worst["read_total_us"] = leaf["total_read_us"]
			_res_worst["read_detail"] = leaf.duplicate()
	return {"surface": surface, "tiles": tiles, "plan": plan, "vegetation": vegetation}


## Read only header + surface + tiles. Skips plan/vegetation Variant blobs.
## Used for halo height sampling — full package not required.
func _read_chunk_package_columns_only(coord: Vector2i) -> Dictionary:
	var path := chunk_package_path(coord)
	var t0 := Time.get_ticks_usec()
	if not FileAccess.file_exists(path):
		last_error = "missing chunk package %s" % path
		stats_missing_package_errors += 1
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		last_error = "open failed %s" % path
		stats_missing_package_errors += 1
		return {}
	var magic := f.get_buffer(4).get_string_from_utf8()
	if magic != CHUNK_MAGIC:
		last_error = "bad chunk magic %s" % path
		f.close()
		stats_missing_package_errors += 1
		return {}
	var ver: int = int(f.get_32())
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
	var surface := PackedFloat32Array()
	var tiles := PackedInt32Array()
	surface.resize(CELLS2)
	tiles.resize(CELLS2)
	for i in CELLS2:
		surface[i] = f.get_float()
		tiles[i] = int(f.get_32())
	# Stop before plan get_var / vegetation — halo only needs columns.
	f.close()
	stats_surface_disk_reads += 1
	stats_surface_disk_read_us += Time.get_ticks_usec() - t0
	if _res_measure:
		_res_add("surface_columns_only_read", Time.get_ticks_usec() - t0)
	return {"surface": surface, "tiles": tiles}


## Ensure surface+tiles are in RAM for halo sampling (no plan, no veg install).
func ensure_surface_data_resident(coord: Vector2i) -> bool:
	_maybe_enable_res_measure_from_env()
	var t_all := Time.get_ticks_usec() if _res_measure else 0
	if not package_ready(coord) and not (valid and coord_in_package(coord)):
		return false
	if _surface_resident.has(coord) or _resident.has(coord) or _chunks.has(coord):
		if _res_measure:
			_res_add("ensure_surface.cache_hit", Time.get_ticks_usec() - t_all)
		return true
	if package_dir.is_empty():
		return _chunks.has(coord)
	var pack: Dictionary = _read_chunk_package_columns_only(coord)
	if pack.is_empty():
		return false
	_surface_resident[coord] = pack
	if _res_measure:
		_res_add("ensure_surface.disk_load", Time.get_ticks_usec() - t_all)
	return true


func _note_surface_from_full_pack(coord: Vector2i, pack: Dictionary) -> void:
	if pack.is_empty() or _surface_resident.has(coord):
		return
	var surface = pack.get("surface", null)
	var tiles = pack.get("tiles", null)
	if surface is PackedFloat32Array and tiles is PackedInt32Array:
		_surface_resident[coord] = {"surface": surface, "tiles": tiles}


## Load chunk package into RAM if needed. Returns false if missing/corrupt.
## Vegetation stamps are installed once when the package first becomes resident
## (not on every ensure hit — that re-walked FeatureRegistry on every stream start).
func ensure_chunk_resident(coord: Vector2i) -> bool:
	_maybe_enable_res_measure_from_env()
	var t_all := Time.get_ticks_usec() if _res_measure else 0
	if not coord_in_package(coord) and valid:
		last_error = "ensure_chunk_resident: coord out of package %s" % str(coord)
		return false
	if not package_ready(coord) and not FileAccess.file_exists(chunk_package_path(coord)):
		last_error = "ensure_chunk_resident: package not ready %s" % str(coord)
		return false
	if _resident.has(coord) or _chunks.has(coord):
		if _res_measure:
			_res_add("ensure_chunk_resident.cache_hit", Time.get_ticks_usec() - t_all)
		return true
	# Streamed packages (and any package_dir with chunks/) load on demand.
	if not package_dir.is_empty():
		var t_read := Time.get_ticks_usec() if _res_measure else 0
		var pack: Dictionary = _read_chunk_package(coord)
		if _res_measure:
			var rus := Time.get_ticks_usec() - t_read
			_res_add("ensure_chunk_resident._read_chunk_package", rus)
			_res_read_us += rus
			_res_read_max_us = maxi(_res_read_max_us, rus)
		if pack.is_empty():
			push_error("[WorldBake] %s" % last_error)
			return false
		_resident[coord] = pack
		_note_surface_from_full_pack(coord, pack)
		stats_full_package_loads += 1
		var t_veg := Time.get_ticks_usec() if _res_measure else 0
		_install_resident_vegetation(coord, pack)
		if _res_measure:
			_res_add("ensure_chunk_resident.veg_install", Time.get_ticks_usec() - t_veg)
			_res_add("ensure_chunk_resident.total", Time.get_ticks_usec() - t_all)
		return true
	last_error = "ensure_chunk_resident: no package_dir and not in monolith"
	return _chunks.has(coord)


## Ensure package bytes/surfaces are in RAM for mesh-halo sampling without reinstalling vegetation.
## Use for neighbor ring prefetch around a stream start; full ensure_chunk_resident for the target.
## Measurement (CRYSTALSTORM_BAKE_RESIDENT_MEASURE=1).
var _res_measure: bool = false
var _res_env_checked: bool = false
var _res_n: int = 0
var _res_hit: int = 0
var _res_miss: int = 0
var _res_total_us: int = 0
var _res_max_us: int = 0
var _res_read_us: int = 0
var _res_read_max_us: int = 0
var _res_phase: Dictionary = {}  # leaf -> {n, total_us, max_us}
var _res_worst: Dictionary = {}


func _maybe_enable_res_measure_from_env() -> void:
	if _res_env_checked or _res_measure:
		return
	_res_env_checked = true
	var raw := OS.get_environment("CRYSTALSTORM_BAKE_RESIDENT_MEASURE").strip_edges().to_lower()
	if raw == "1" or raw == "true" or raw == "on":
		set_resident_measure_enabled(true)


func set_resident_measure_enabled(enabled: bool) -> void:
	_res_measure = enabled
	_res_env_checked = true
	if enabled:
		reset_resident_measure()


func reset_resident_measure() -> void:
	_res_n = 0
	_res_hit = 0
	_res_miss = 0
	_res_total_us = 0
	_res_max_us = 0
	_res_read_us = 0
	_res_read_max_us = 0
	_res_phase.clear()
	_res_worst.clear()


## Measure-only: drop RAM package cache so next ensure reloads from disk (cold path).
func drop_resident_packages_for_measure() -> int:
	var n: int = _resident.size() + _surface_resident.size()
	_resident.clear()
	_surface_resident.clear()
	return n


func get_resident_measure() -> Dictionary:
	var phases: Array = []
	for k in _res_phase.keys():
		var row: Dictionary = _res_phase[k]
		phases.append({
			"phase": k,
			"n": int(row.get("n", 0)),
			"total_us": int(row.get("total_us", 0)),
			"total_ms": float(row.get("total_us", 0)) / 1000.0,
			"max_us": int(row.get("max_us", 0)),
			"max_ms": float(row.get("max_us", 0)) / 1000.0,
			"avg_us": float(row.get("total_us", 0)) / float(maxi(int(row.get("n", 0)), 1)),
		})
	phases.sort_custom(func(a, b): return int(a.total_us) > int(b.total_us))
	var leaf_names := {
		"file_exists": true, "file_open": true, "header_parse": true,
		"column_surface_tiles_loop": true, "get_var_plan": true,
		"get_var_vegetation": true, "file_close_trailer": true,
		"store_resident_dict": true, "cache_hit_early_return": true,
		"ensure_chunk_resident.veg_install": true,
		"ensure_chunk_resident.cache_hit": true,
		"surface_columns_only_read": true,
		"ensure_surface.cache_hit": true,
		"ensure_surface.disk_load": true,
	}
	var leaves: Array = []
	for ph in phases:
		if leaf_names.has(str(ph.get("phase", ""))):
			leaves.append(ph)
	leaves.sort_custom(func(a, b): return int(a.max_us) > int(b.max_us))
	var dominant_leaf := ""
	var dominant_leaf_max_us := 0
	var dominant_leaf_total_us := 0
	if leaves.size() > 0:
		dominant_leaf = str(leaves[0].get("phase", ""))
		dominant_leaf_max_us = int(leaves[0].get("max_us", 0))
		dominant_leaf_total_us = int(leaves[0].get("total_us", 0))
	return {
		"calls": _res_n,
		"cache_hits": _res_hit,
		"cache_misses": _res_miss,
		"total_us": _res_total_us,
		"total_ms": float(_res_total_us) / 1000.0,
		"avg_us": float(_res_total_us) / float(maxi(_res_n, 1)),
		"max_us": _res_max_us,
		"max_ms": float(_res_max_us) / 1000.0,
		"read_package_us": _res_read_us,
		"read_package_max_us": _res_read_max_us,
		"read_package_max_ms": float(_res_read_max_us) / 1000.0,
		"phases": phases,
		"exclusive_leaves": leaves,
		"dominant_exclusive_leaf": dominant_leaf,
		"dominant_exclusive_leaf_max_us": dominant_leaf_max_us,
		"dominant_exclusive_leaf_max_ms": float(dominant_leaf_max_us) / 1000.0,
		"dominant_exclusive_leaf_total_us": dominant_leaf_total_us,
		"worst_call": _res_worst.duplicate(true),
	}


func _res_add(phase: String, us: int) -> void:
	if not _res_measure:
		return
	if not _res_phase.has(phase):
		_res_phase[phase] = {"n": 0, "total_us": 0, "max_us": 0}
	var row: Dictionary = _res_phase[phase]
	row["n"] = int(row["n"]) + 1
	row["total_us"] = int(row["total_us"]) + us
	row["max_us"] = maxi(int(row["max_us"]), us)


func ensure_package_data_resident(coord: Vector2i) -> bool:
	## Halo-neighbor prefetch: surface+tiles only (no plan get_var, no vegetation).
	## Full package load remains ensure_chunk_resident for mesh apply / plan / veg.
	_maybe_enable_res_measure_from_env()
	var t_all := Time.get_ticks_usec() if _res_measure else 0
	if _res_measure:
		_res_n += 1
	var had := is_surface_resident(coord)
	var ok := ensure_surface_data_resident(coord)
	if _res_measure:
		var tot := Time.get_ticks_usec() - t_all
		_res_total_us += tot
		_res_max_us = maxi(_res_max_us, tot)
		if had:
			_res_hit += 1
		elif ok:
			_res_miss += 1
		_res_add("ensure_package_data_resident", tot)
	return ok


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
	if _surface_resident.has(coord):
		_surface_resident.erase(coord)
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
	var _STP = load("res://systems/startup_total_profiler.gd")
	if _STP and _STP.is_enabled():
		_STP.begin("bake.save_index", "disk_io")
	var t0 := Time.get_ticks_msec()
	if package_dir.is_empty():
		package_dir = bake_dir_for(world_seed, radius if not full_world else -1, full_world)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(package_dir))
	var index_path := path if not path.is_empty() else package_dir.path_join("world.index")
	var f := FileAccess.open(index_path, FileAccess.WRITE)
	if f == null:
		last_error = "save index failed"
		if _STP and _STP.is_enabled():
			_STP.end("bake.save_index", {"error": last_error})
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
	var t_sum := Time.get_ticks_usec()
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
	if _STP and _STP.is_enabled():
		_STP.add_us("save_index_us", Time.get_ticks_usec() - t_sum)
		_STP.event("bake.save_index_size_sum", {
			"us": Time.get_ticks_usec() - t_sum,
			"bytes": total,
		}, "disk_io")
	last_bake_bytes = total
	last_save_time_ms = Time.get_ticks_msec() - t0
	last_error = ""
	if _STP and _STP.is_enabled():
		_STP.end("bake.save_index", {"save_ms": last_save_time_ms, "bytes": last_bake_bytes})
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
	_surface_resident.clear()
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
	_surface_resident.clear()
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
	if data == null:
		return false
	var coord: Vector2i = data.position
	if not package_ready(coord):
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
	## Halo / base height sample: surface+tiles only — never force full package + veg.
	stats_sample_base_calls += 1
	if not has_chunk(coord):
		return {}
	var pack: Dictionary = {}
	if _resident.has(coord):
		pack = _resident[coord]
		stats_sample_base_full_hits += 1
	elif _chunks.has(coord):
		pack = _chunks[coord]
		stats_sample_base_full_hits += 1
	elif _surface_resident.has(coord):
		pack = _surface_resident[coord]
		stats_sample_base_surface_hits += 1
	else:
		if not ensure_surface_data_resident(coord):
			return {}
		pack = _surface_resident.get(coord, {})
		stats_sample_base_surface_loads += 1
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
	_surface_resident.erase(coord)
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
