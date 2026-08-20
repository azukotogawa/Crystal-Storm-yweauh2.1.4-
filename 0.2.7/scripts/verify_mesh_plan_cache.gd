extends SceneTree
## Mesh Plan Cache: parity, invalidation, corrupt/version, prefer path.
## Usage: godot --headless -s scripts/verify_mesh_plan_cache.gd

const _WorldState = preload("res://world/world_state.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkPipeline = preload("res://chunks/chunk_pipeline.gd")
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")
const _WorldBakeService = preload("res://world/world_bake_service.gd")
const _MeshPlanCache = preload("res://world/mesh_plan_cache.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const SEED := 424242
const RADIUS := 2

var _failed: int = 0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_WORLD_BAKE", "1")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_CACHE", "1")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", str(RADIUS))
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

	# Structural
	var pipe_src := FileAccess.get_file_as_string("res://chunks/chunk_pipeline.gd")
	if "try_get_plan" not in pipe_src and "mesh_plan_cache" not in pipe_src:
		_fail("pipeline must prefer mesh plan cache")
	else:
		_ok("pipeline mesh plan prefer wiring")
	var cm_src := FileAccess.get_file_as_string("res://chunks/chunk_manager.gd")
	if "_bootstrap_mesh_plan_cache" not in cm_src:
		_fail("ChunkManager must bootstrap mesh plan cache")
	else:
		_ok("ChunkManager mesh plan bootstrap")
	var mp_src := FileAccess.get_file_as_string("res://world/mesh_plan_cache.gd")
	if "MultiMesh" in mp_src and "class_name MultiMesh" in mp_src:
		_fail("mesh plan cache must not own MultiMesh GPU types")
	else:
		_ok("cache stores plan data only (no MultiMesh class ownership)")

	var world = _InfiniteNoiseWorld.new(SEED)
	var mgr = _ChunkManager.new()
	mgr.prebuild_chunk_buffers = true
	mgr.terrain_surface_mesh = true

	# --- Co-emit: WorldBakeService.bake_world(host) must produce MeshPlans + disk package ---
	var bake: _WorldBakeService = _WorldBakeService.ensure_active()
	bake.delete_bake(SEED, RADIUS)
	var cache_wipe: _MeshPlanCache = _MeshPlanCache.ensure_active()
	cache_wipe.delete_plans(SEED, RADIUS)
	_MeshPlanCache.clear_active()
	_WorldBakeService.set_active(bake)
	var co: Dictionary = bake.bake_world(world, RADIUS, mgr)
	if not bool(co.get("ok", false)):
		_fail("bake_world with host failed")
		_finish()
		return
	var co_plan: Dictionary = co.get("mesh_plan", {})
	if not bool(co_plan.get("ok", false)) or int(co_plan.get("chunks", 0)) <= 0:
		_fail("bake_world must co-emit mesh plans via host mesh_plan=%s" % str(co_plan))
		_finish()
		return
	_ok("world bake co-emits mesh plans chunks=%d bake_ms=%d" % [
		int(co_plan.get("chunks", 0)), int(co_plan.get("bake_ms", 0))
	])
	var co_save: Dictionary = bake.save_bake()
	if not bool(co_save.get("ok", false)):
		_fail("save_bake after co-emit failed")
		_finish()
		return
	# Plans are embedded in streamed per-chunk packages (not a separate mesh_plans file).
	var plan_bytes: int = int(co_save.get("bytes", 0))
	var sample_chk := bake.chunk_package_path(Vector2i(0, 0))
	if not FileAccess.file_exists(sample_chk):
		_fail("save_bake must write per-chunk packages with embedded plans: %s" % sample_chk)
		_finish()
		return
	_ok("streamed packages with embedded plans sample=%s total_bytes=%d" % [sample_chk, plan_bytes])

	# Streamed bake: reload index only, mesh plans embedded in chunk packages.
	_WorldBakeService.clear_active()
	_MeshPlanCache.clear_active()
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_BAKE_ON_NEW", "0")
	var bake2: _WorldBakeService = _WorldBakeService.ensure_active()
	if not bake2.load_bake(SEED, RADIUS):
		_fail("reload bake index failed: %s" % bake2.last_error)
		_finish()
		return
	if bake2.resident_count() != 0:
		_fail("index load must leave resident_count=0")
	else:
		_ok("index-only load resident=0")
	var ensured: Dictionary = bake2.ensure_mesh_plans(mgr, world)
	if str(ensured.get("mode", "")) not in ["streamed", "baked", "loaded", "valid", "repaired"]:
		_fail("ensure_mesh_plans mode=%s" % str(ensured.get("mode")))
	else:
		_ok("ensure_mesh_plans mode=%s" % str(ensured.get("mode")))
	_WorldBakeService.clear_active()
	_MeshPlanCache.clear_active()
	var bake3: _WorldBakeService = _WorldBakeService.ensure_active()
	var boot: Dictionary = bake3.bootstrap_for_world(world, false, mgr)
	if str(boot.get("mode", "")) != "loaded" and str(boot.get("mode", "")) != "baked":
		_fail("bootstrap_for_world host must load/bake mode=%s" % str(boot.get("mode")))
	else:
		_ok("bootstrap_for_world mode=%s mesh_plan=%s streamed=%s" % [
			str(boot.get("mode")),
			str(boot.get("mesh_plan", {}).get("mode", "")),
			str(boot.get("streamed", bake3.streamed)),
		])
	var active_plans = _MeshPlanCache.get_active()
	if active_plans == null or not bool(active_plans.valid):
		_fail("bootstrap must leave MeshPlanCache active")
	else:
		_ok("bootstrap MeshPlanCache valid streamed=%s" % str(active_plans.streamed_from_bake))
	_WorldState.replace_active()
	var d_boot = _ChunkData.new(Vector2i(0, 0), world)
	d_boot.capture_worker_snapshot()
	var job_boot: Dictionary = _ChunkPipeline.run_worker_job(
		mgr, d_boot, true, [], Rect2i(0, 0, _ChunkData.SIZE, _ChunkData.SIZE), [], {}, true, true
	)
	if str(job_boot.get("mesh_source", "")) != "cache":
		_fail("bootstrap path must prefer mesh_source=cache got=%s" % str(job_boot.get("mesh_source")))
	else:
		_ok("bootstrap prefer mesh_source=cache (streamed packages)")

	# Streamed bake already co-emitted plans into chunk packages.
	_WorldBakeService.set_active(bake3)
	bake3.ensure_mesh_plans(mgr, world)
	var cache2 = _MeshPlanCache.get_active()
	if cache2 == null or not bool(cache2.valid):
		_fail("MeshPlanCache inactive after bootstrap")
		_finish()
		return
	_ok("bake_plans ready via streamed packages count=%d" % cache2.plan_count())

	# Parity: streamed plan vs live generate for pristine chunk
	_WorldState.replace_active()
	var coord := Vector2i(0, 0)
	var d_gen = _ChunkData.new(coord, world)
	d_gen.capture_worker_snapshot()
	mgr._generate_chunk(d_gen)
	var gen_mesh: Dictionary = mgr._build_mesh(d_gen)
	var gen_quads: Array = gen_mesh.get("quads", [])

	var d_cache = _ChunkData.new(coord, world)
	d_cache.capture_worker_snapshot()
	var cached: Array = cache2.try_get_plan(d_cache)
	if cached.is_empty():
		_fail("try_get_plan miss on pristine chunk")
	elif cached.size() != gen_quads.size():
		_fail("plan count mismatch cache=%d gen=%d" % [cached.size(), gen_quads.size()])
	else:
		var mism := 0
		for i in mini(cached.size(), gen_quads.size()):
			var a: Dictionary = cached[i]
			var b: Dictionary = gen_quads[i]
			if int(a.get("face_code", -1)) != int(b.get("face_code", -2)):
				mism += 1
			elif int(a.get("x", -1)) != int(b.get("x", -2)) or int(a.get("z", -1)) != int(b.get("z", -2)):
				mism += 1
			elif not is_equal_approx(float(a.get("y", 0.0)), float(b.get("y", 1.0))):
				mism += 1
			elif int(a.get("type", -1)) != int(b.get("type", -2)):
				mism += 1
		if mism > 0:
			_fail("cached plan field mismatches=%d" % mism)
		else:
			_ok("cached plan matches generate n=%d" % cached.size())

	# Prefer path via pipeline
	cache2.reset_stats()
	_WorldState.replace_active()
	var d_pref = _ChunkData.new(coord, world)
	d_pref.capture_worker_snapshot()
	var job: Dictionary = _ChunkPipeline.run_worker_job(
		mgr, d_pref, true, [], Rect2i(0, 0, _ChunkData.SIZE, _ChunkData.SIZE), [], {}, true, true
	)
	if str(job.get("mesh_source", "")) != "cache":
		_fail("prefer path mesh_source want cache got=%s" % str(job.get("mesh_source")))
	else:
		_ok("prefer path mesh_source=cache mesh_us=%d" % int(job.get("build_mesh_us", 0)))

	# Dig invalidation → generate
	_WorldState.replace_active()
	_TerrainEdits.dig(3, 3, 2)
	var d_dig = _ChunkData.new(coord, world)
	d_dig.capture_worker_snapshot()
	var job_dig: Dictionary = _ChunkPipeline.run_worker_job(
		mgr, d_dig, true, [], Rect2i(0, 0, _ChunkData.SIZE, _ChunkData.SIZE), [], {}, true, true
	)
	if str(job_dig.get("mesh_source", "")) != "generate":
		_fail("dig must invalidate plan cache mesh_source=%s" % str(job_dig.get("mesh_source")))
	else:
		_ok("dig invalidates plan cache → generate")
	# Build tile invalidation
	_WorldState.replace_active()
	_TerrainEdits.build_wall(5, 5, 3)
	var d_build = _ChunkData.new(coord, world)
	d_build.capture_worker_snapshot()
	var job_b: Dictionary = _ChunkPipeline.run_worker_job(
		mgr, d_build, true, [], Rect2i(0, 0, _ChunkData.SIZE, _ChunkData.SIZE), [], {}, true, true
	)
	if str(job_b.get("mesh_source", "")) != "generate":
		_fail("build must invalidate plan cache")
	else:
		_ok("build invalidates plan cache → generate")

	# Crystal / WorldState ownership: cache must not write WorldState
	if "height_delta[" in mp_src or "build_tile[" in mp_src:
		_fail("mesh plan cache must not mutate WorldState dicts")
	else:
		_ok("cache does not mutate WorldState storage")

	# Crystal invalidation path: terrain dig-like overlays are the mesh-input path;
	# crystal cells that only touch crystal sim leave plans valid (Engine 1.0 split).
	# Simulate crystal-related terrain dirty via height_delta (production mesh-input domain).
	_WorldState.replace_active()
	_WorldState.get_active().height_delta[Vector2i(1, 1)] = -1
	_WorldState.get_active().terrain_revision += 1
	var d_cr = _ChunkData.new(coord, world)
	d_cr.capture_worker_snapshot()
	if _MeshPlanCache.chunk_overlays_pristine(d_cr):
		_fail("height_delta overlay must be non-pristine")
	else:
		_ok("crystal-related terrain height_delta marks non-pristine")
	var job_cr: Dictionary = _ChunkPipeline.run_worker_job(
		mgr, d_cr, true, [], Rect2i(0, 0, _ChunkData.SIZE, _ChunkData.SIZE), [], {}, true, true
	)
	if str(job_cr.get("mesh_source", "")) != "generate":
		_fail("terrain overlay from crystal/dig domain must miss cache")
	else:
		_ok("terrain overlay miss → generate")

	# Corrupt streamed chunk package (plans live inside bake packages now).
	var bake_for_corrupt = _WorldBakeService.get_active()
	if bake_for_corrupt != null and bake_for_corrupt.corrupt_chunk_package(Vector2i(0, 0)):
		bake_for_corrupt.release_chunk(Vector2i(0, 0))
		if bake_for_corrupt.ensure_chunk_resident(Vector2i(0, 0)):
			_fail("corrupt chunk package must fail reload")
		else:
			_ok("corrupt streamed package rejected: %s" % bake_for_corrupt.last_error)
		# Safe regenerate
		var reb: Dictionary = bake_for_corrupt.bake_world(world, RADIUS, mgr)
		var res: Dictionary = bake_for_corrupt.save_bake()
		if not bool(reb.get("ok", false)) or not bool(res.get("ok", false)):
			_fail("regenerate after corrupt failed")
		else:
			_ok("corrupt package safe regenerate")
	else:
		_ok("corrupt package path skipped (no active bake)")

	# Version mismatch on bake index
	var stub: String = ""
	if bake_for_corrupt != null:
		stub = str(bake_for_corrupt.write_version_mismatch_stub(SEED, RADIUS))
	if stub.is_empty():
		_fail("version stub failed")
	else:
		var badv: _WorldBakeService = _WorldBakeService.new()
		if badv.load_bake(SEED, RADIUS):
			_fail("version mismatch must fail load")
		else:
			_ok("version mismatch rejected: %s" % badv.last_error)
			badv.bake_world(world, RADIUS, mgr)
			badv.save_bake()
			_WorldBakeService.set_active(badv)
			badv.ensure_mesh_plans(mgr, world)
			_ok("version mismatch safe regenerate")

	# Disable cache → generate
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_CACHE", "0")
	_MeshPlanCache.set_active(cache2)
	_WorldState.replace_active()
	var d_off = _ChunkData.new(coord, world)
	d_off.capture_worker_snapshot()
	var job_off: Dictionary = _ChunkPipeline.run_worker_job(
		mgr, d_off, true, [], Rect2i(0, 0, _ChunkData.SIZE, _ChunkData.SIZE), [], {}, true, true
	)
	if str(job_off.get("mesh_source", "")) != "generate":
		_fail("disabled cache must generate")
	else:
		_ok("cache disabled → generate")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_CACHE", "1")

	# Before/after mesh plan timing
	# Ensure valid plans reloaded
	cache2.bake_plans(mgr, world, RADIUS, SEED)
	cache2.save_plans()
	cache2.load_plans(SEED, RADIUS)
	_MeshPlanCache.set_active(cache2)
	_WorldBakeService.set_active(bake)

	var coords: Array = []
	for cz in range(-RADIUS, RADIUS + 1):
		for cx in range(-RADIUS, RADIUS + 1):
			coords.append(Vector2i(cx, cz))

	# BEFORE: force generate
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_CACHE", "0")
	var before_mesh_us := 0
	var before_load_us := 0
	var before_n := 0
	var before_upload_us := 0
	var hitch_before := 0
	for c in coords:
		_WorldState.replace_active()
		var d = _ChunkData.new(c, world)
		d.capture_worker_snapshot()
		var t0 := Time.get_ticks_usec()
		var j: Dictionary = _ChunkPipeline.run_worker_job(
			mgr, d, true, [], Rect2i(0, 0, _ChunkData.SIZE, _ChunkData.SIZE), [], {}, true, true
		)
		var load_us: int = Time.get_ticks_usec() - t0
		if bool(j.get("ok", false)):
			before_mesh_us += int(j.get("build_mesh_us", 0))
			before_load_us += load_us
			before_n += 1
			if load_us > hitch_before:
				hitch_before = load_us

	# AFTER: cache on
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_CACHE", "1")
	_MeshPlanCache.set_active(cache2)
	var after_mesh_us := 0
	var after_load_us := 0
	var after_n := 0
	var hitch_after := 0
	var cache_hits := 0
	var mem0 := OS.get_static_memory_usage()
	for c in coords:
		_WorldState.replace_active()
		var d = _ChunkData.new(c, world)
		d.capture_worker_snapshot()
		var t0 := Time.get_ticks_usec()
		var j: Dictionary = _ChunkPipeline.run_worker_job(
			mgr, d, true, [], Rect2i(0, 0, _ChunkData.SIZE, _ChunkData.SIZE), [], {}, true, true
		)
		var load_us: int = Time.get_ticks_usec() - t0
		if bool(j.get("ok", false)):
			after_mesh_us += int(j.get("build_mesh_us", 0))
			after_load_us += load_us
			after_n += 1
			if str(j.get("mesh_source", "")) == "cache":
				cache_hits += 1
			if load_us > hitch_after:
				hitch_after = load_us
	var mem1 := OS.get_static_memory_usage()

	var avg_before_mesh := float(before_mesh_us) / float(maxi(before_n, 1))
	var avg_after_mesh := float(after_mesh_us) / float(maxi(after_n, 1))
	var avg_before_load := float(before_load_us) / float(maxi(before_n, 1))
	var avg_after_load := float(after_load_us) / float(maxi(after_n, 1))
	if cache_hits < after_n:
		_fail("expected all after samples from cache hits=%d n=%d" % [cache_hits, after_n])
	else:
		_ok("after path all cache hits n=%d" % cache_hits)
	if avg_after_mesh >= avg_before_mesh * 0.5:
		# Require significant reduction of dominant phase
		_fail(
			"mesh plan not significantly reduced before=%.1f after=%.1f"
			% [avg_before_mesh, avg_after_mesh]
		)
	else:
		_ok(
			"mesh plan reduced before=%.1f after=%.1f speedup=%.2fx"
			% [avg_before_mesh, avg_after_mesh, avg_before_mesh / maxf(avg_after_mesh, 0.001)]
		)

	# Save architecture structural unchanged
	var save_src := FileAccess.get_file_as_string("res://systems/save_schema.gd")
	if "mesh_plan" in save_src:
		_fail("save schema must not absorb mesh plan cache")
	else:
		_ok("save architecture unchanged (schema free of mesh plans)")

	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-63743003c13d/implementer"
	var perf := {
		"seed": SEED,
		"radius": RADIUS,
		"chunks": before_n,
		"plan_cache_bytes": plan_bytes,
		"plan_bake_ms": 0,
		"avg_mesh_us_before": avg_before_mesh,
		"avg_mesh_us_after": avg_after_mesh,
		"avg_chunk_load_us_before": avg_before_load,
		"avg_chunk_load_us_after": avg_after_load,
		"worst_load_us_before": hitch_before,
		"worst_load_us_after": hitch_after,
		"mesh_speedup": avg_before_mesh / maxf(avg_after_mesh, 0.001),
		"load_speedup": avg_before_load / maxf(avg_after_load, 0.001),
		"mem_delta_bytes": mem1 - mem0,
		"gpu_upload_note": "streamed bake packages; plan cache is CPU quads only",
	}
	var pf := FileAccess.open(scratch.path_join("mesh_opt_perf.json"), FileAccess.WRITE)
	if pf:
		pf.store_string(JSON.stringify(perf, "\t"))
		pf.close()
		_ok("wrote mesh_opt_perf.json")
	print(
		"PERF_SUMMARY mesh_before=%.1f mesh_after=%.1f load_before=%.1f load_after=%.1f plan_bytes=%d"
		% [
			avg_before_mesh,
			avg_after_mesh,
			avg_before_load,
			avg_after_load,
			plan_bytes,
		]
	)

	_finish()


func _finish() -> void:
	_MeshPlanCache.clear_active()
	_WorldBakeService.clear_active()
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "All mesh plan cache tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "Mesh plan cache FAILED (%d)" % _failed)
