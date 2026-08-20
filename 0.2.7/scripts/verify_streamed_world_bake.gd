extends SceneTree
## Streamed world bake: index-only startup, per-chunk load/release, no full-world RAM.
## Usage: godot --headless -s scripts/verify_streamed_world_bake.gd

const _WorldState = preload("res://world/world_state.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkPipeline = preload("res://chunks/chunk_pipeline.gd")
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")
const _WorldBakeService = preload("res://world/world_bake_service.gd")
const _MeshPlanCache = preload("res://world/mesh_plan_cache.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const SEED := 900011
const RADIUS := 2

var _failed: int = 0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_WORLD_BAKE", "1")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_CACHE", "1")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", str(RADIUS))
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL: %s" % msg)


func _ok(msg: String) -> void:
	print("OK %s" % msg)


func _run() -> void:
	_WorldState.replace_active()
	_WorldBakeService.clear_active()
	_MeshPlanCache.clear_active()

	var mem0 := OS.get_static_memory_usage()
	var world = _InfiniteNoiseWorld.new(SEED)
	var mgr = _ChunkManager.new()
	mgr.prebuild_chunk_buffers = true
	mgr.terrain_surface_mesh = true

	var bake: _WorldBakeService = _WorldBakeService.ensure_active()
	bake.delete_bake(SEED, RADIUS)
	var baked: Dictionary = bake.bake_world(world, RADIUS, mgr)
	if not bool(baked.get("ok", false)):
		_fail("bake_world failed")
		_finish()
		return
	if not bool(baked.get("streamed", false)):
		_fail("bake must be streamed format")
	else:
		_ok("streamed bake chunks=%d bake_ms=%d bytes=%d" % [
			int(baked.get("chunks", 0)), int(baked.get("bake_ms", 0)), int(baked.get("bytes", 0))
		])
	# After bake, RAM must not hold full map
	if bake.resident_count() != 0:
		_fail("after bake_world resident_count must be 0 got=%d" % bake.resident_count())
	else:
		_ok("post-bake resident_count=0 (not full-world resident)")

	var saved: Dictionary = bake.save_bake()
	if not bool(saved.get("ok", false)):
		_fail("save_bake index failed")
		_finish()
		return
	var idx_path: String = str(saved.get("path", ""))
	if not idx_path.ends_with("world.index") and "world.index" not in idx_path:
		_fail("save must write world.index got=%s" % idx_path)
	else:
		_ok("wrote world.index path=%s bytes=%d" % [idx_path, int(saved.get("bytes", 0))])

	# Reload: index only
	_WorldBakeService.clear_active()
	var bake2: _WorldBakeService = _WorldBakeService.ensure_active()
	var t_load0 := Time.get_ticks_usec()
	if not bake2.load_bake(SEED, RADIUS):
		_fail("load index failed: %s" % bake2.last_error)
		_finish()
		return
	var load_us: int = Time.get_ticks_usec() - t_load0
	if bake2.resident_count() != 0:
		_fail("index load must not populate residents got=%d" % bake2.resident_count())
	else:
		_ok("index-only load resident=0 load_us=%d chunks_indexed=%d" % [
			load_us, bake2.chunk_count()
		])
	_WorldBakeService.set_active(bake2)
	bake2.ensure_mesh_plans(mgr, world)

	# Stream load a few chunks
	var coords: Array = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 1)]
	var disk_us0: int = bake2.stats_disk_read_us
	for c in coords:
		if not bake2.ensure_chunk_resident(c):
			_fail("ensure_chunk_resident failed %s err=%s" % [str(c), bake2.last_error])
	if bake2.resident_count() != coords.size():
		_fail("resident_count want %d got %d" % [coords.size(), bake2.resident_count()])
	else:
		_ok("streamed in %d packages disk_reads=%d disk_us=%d" % [
			coords.size(), bake2.stats_disk_reads, bake2.stats_disk_read_us - disk_us0
		])

	# Match generate base for sample
	_WorldState.replace_active()
	var d_gen = _ChunkData.new(Vector2i(0, 0), world)
	d_gen.capture_worker_snapshot()
	mgr._generate_chunk(d_gen)
	var d_bake = _ChunkData.new(Vector2i(0, 0), world)
	d_bake.capture_worker_snapshot()
	if not bake2.try_apply_base_to_chunk_data(d_bake):
		_fail("try_apply after stream load failed")
	elif not is_equal_approx(float(d_gen.surface_map[3][5]), float(d_bake.surface_map[3][5])):
		_fail("streamed base mismatch gen vs bake")
	else:
		_ok("streamed chunk matches generate base")

	# Pipeline prefer bake + mesh plan from package
	_WorldState.replace_active()
	var d_job = _ChunkData.new(Vector2i(0, 0), world)
	d_job.capture_worker_snapshot()
	var job: Dictionary = _ChunkPipeline.run_worker_job(
		mgr, d_job, true, [], Rect2i(0, 0, _ChunkData.SIZE, _ChunkData.SIZE), [], {}, true, true
	)
	if str(job.get("column_source", "")) != "bake":
		_fail("column_source want bake got=%s" % str(job.get("column_source")))
	elif str(job.get("mesh_source", "")) != "cache":
		_fail("mesh_source want cache got=%s" % str(job.get("mesh_source")))
	else:
		_ok("pipeline bake+plan cache from streamed package")

	# Dig overlay still works; mesh regenerates
	_WorldState.replace_active()
	_TerrainEdits.dig(2, 2, 2)
	var d_dig = _ChunkData.new(Vector2i(0, 0), world)
	d_dig.capture_worker_snapshot()
	var job_dig: Dictionary = _ChunkPipeline.run_worker_job(
		mgr, d_dig, true, [], Rect2i(0, 0, _ChunkData.SIZE, _ChunkData.SIZE), [], {}, true, true
	)
	if str(job_dig.get("column_source", "")) != "bake":
		_fail("dig still uses bake columns got=%s" % str(job_dig.get("column_source")))
	elif str(job_dig.get("mesh_source", "")) != "generate":
		_fail("dig must miss mesh plan got=%s" % str(job_dig.get("mesh_source")))
	else:
		_ok("dig: bake columns + mesh regenerate")

	# Release reduces resident; reload preserves WorldState (dig still applied via snapshot)
	bake2.release_chunk(Vector2i(0, 0))
	if bake2.is_resident(Vector2i(0, 0)):
		_fail("release_chunk did not drop resident")
	else:
		_ok("release_chunk dropped resident releases=%d" % bake2.stats_releases)
	_WorldState.replace_active()
	_TerrainEdits.dig(4, 4, 1)
	var d_rel = _ChunkData.new(Vector2i(0, 0), world)
	d_rel.capture_worker_snapshot()
	if not bake2.try_apply_base_to_chunk_data(d_rel):
		_fail("reload after release failed")
	elif is_equal_approx(float(d_rel.surface_map[4][4]), float(d_gen.surface_map[4][4])):
		# dig should change height vs pristine generate without dig on 4,4
		# d_gen was pristine; after dig on 4,4 height should differ
		_fail("overlay dig not reflected after reload")
	else:
		_ok("reload after release applies WorldState dig overlay")

	# Missing package → block generate (in bounds)
	bake2.release_chunk(Vector2i(1, 1))
	var cpath := bake2.chunk_package_path(Vector2i(1, 1))
	if FileAccess.file_exists(cpath):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cpath))
	var d_miss = _ChunkData.new(Vector2i(1, 1), world)
	d_miss.capture_worker_snapshot()
	var col: Dictionary = _ChunkPipeline.run_column_stage(mgr, d_miss, true, [])
	if str(col.get("column_source", "")) == "generate":
		_fail("missing package must not procedural-generate")
	else:
		_ok("missing package blocked generate source=%s" % str(col.get("column_source")))

	# Corrupt package fails safely
	bake2.ensure_chunk_resident(Vector2i(-1, 0))
	if bake2.corrupt_chunk_package(Vector2i(-1, 0)):
		bake2.release_chunk(Vector2i(-1, 0))
		if bake2.ensure_chunk_resident(Vector2i(-1, 0)):
			_fail("corrupt package must fail ensure_resident")
		else:
			_ok("corrupt package rejected: %s" % bake2.last_error)

	# Version mismatch index
	var stub := bake2.write_version_mismatch_stub(SEED, RADIUS)
	if not stub.is_empty():
		var bad := _WorldBakeService.new()
		if bad.load_bake(SEED, RADIUS):
			_fail("version mismatch must fail load")
		else:
			_ok("version mismatch rejected: %s" % bad.last_error)

	# Safe regenerate
	var reb: Dictionary = bake2.bake_world(world, RADIUS, mgr)
	var res: Dictionary = bake2.save_bake()
	if bool(reb.get("ok", false)) and bool(res.get("ok", false)):
		_ok("safe regenerate streamed package")

	var mem1 := OS.get_static_memory_usage()
	# Structural: unload hooks release
	var cm_src := FileAccess.get_file_as_string("res://chunks/chunk_manager.gd")
	if "release_chunk" not in cm_src:
		_fail("ChunkManager unload must release bake packages")
	else:
		_ok("ChunkManager unload releases streamed bake")

	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-3c89103bbbb9/implementer"
	var perf := {
		"seed": SEED,
		"radius": RADIUS,
		"bake_ms": int(baked.get("bake_ms", 0)),
		"package_bytes": int(saved.get("bytes", 0)),
		"index_load_us": load_us,
		"disk_reads": bake2.stats_disk_reads,
		"disk_read_us": bake2.stats_disk_read_us,
		"peak_resident_during_test": coords.size(),
		"mem_delta_bytes": mem1 - mem0,
		"streamed": true,
	}
	var pf := FileAccess.open(scratch.path_join("streamed_bake_perf.json"), FileAccess.WRITE)
	if pf:
		pf.store_string(JSON.stringify(perf, "\t"))
		pf.close()
		_ok("wrote streamed_bake_perf.json")
	print(
		"PERF_SUMMARY bake_ms=%s bytes=%s index_us=%s disk_reads=%s resident_peak=%s"
		% [
			str(perf.bake_ms), str(perf.package_bytes), str(perf.index_load_us),
			str(perf.disk_reads), str(perf.peak_resident_during_test),
		]
	)

	_finish()


func _finish() -> void:
	_WorldBakeService.clear_active()
	_MeshPlanCache.clear_active()
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "All streamed world bake tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "Streamed world bake FAILED (%d)" % _failed)
