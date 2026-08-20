extends SceneTree
## Full finite-world bake: bounds from WorldBorder, prefer bake, no outside generate.
## Usage: godot --headless -s scripts/verify_full_world_bake.gd
## Env CRYSTALSTORM_FULL_WORLD_BAKE_RUN=1 forces a real full-map bake (slow; measured).
## Default: structural full-bounds checks + smoke-radius package behaving under full-world APIs.

const _WorldState = preload("res://world/world_state.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkPipeline = preload("res://chunks/chunk_pipeline.gd")
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")
const _WorldBakeService = preload("res://world/world_bake_service.gd")
const _MeshPlanCache = preload("res://world/mesh_plan_cache.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const SEED := 777001

var _failed: int = 0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_WORLD_BAKE", "1")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_CACHE", "1")
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

	# --- Full playable bounds (not radius-2) ---
	var bounds: Dictionary = _WorldBakeService.full_world_chunk_bounds()
	var exp_chunks: int = int(bounds.get("chunks", 0))
	if exp_chunks < 1000:
		_fail("full world chunk span too small: %d (want full playable map)" % exp_chunks)
	else:
		_ok(
			"full_world_chunk_bounds min=(%d,%d) max=(%d,%d) chunks=%d half=%d"
			% [
				int(bounds.min_cx), int(bounds.min_cz),
				int(bounds.max_cx), int(bounds.max_cz),
				exp_chunks, int(bounds.half_x),
			]
		)
	# Radius-2 smoke is NOT full world
	var smoke_count: int = 5 * 5
	if exp_chunks <= smoke_count:
		_fail("full world must exceed smoke radius package size")
	else:
		_ok("full world span >> smoke radius (%d > %d)" % [exp_chunks, smoke_count])

	# Outside finite world detection
	var outside := Vector2i(int(bounds.max_cx) + 5, int(bounds.max_cz) + 5)
	if not _WorldBakeService.is_chunk_outside_finite_world(outside):
		_fail("chunk beyond playable must be outside finite world")
	else:
		_ok("outside finite world detected %s" % str(outside))
	var inside := Vector2i(0, 0)
	if _WorldBakeService.is_chunk_outside_finite_world(inside):
		_fail("origin must be inside finite world")
	else:
		_ok("origin inside finite world")

	# Structural: pipeline blocks generate when full bake active + miss
	var pipe_src := FileAccess.get_file_as_string("res://chunks/chunk_pipeline.gd")
	if "should_block_procedural_generate" not in pipe_src:
		_fail("pipeline must block procedural generate under full-world bake")
	else:
		_ok("pipeline block-generate wiring")
	var cm_src := FileAccess.get_file_as_string("res://chunks/chunk_manager.gd")
	if "is_chunk_outside_finite_world" not in cm_src and "_WorldBakeService_is_outside" not in cm_src:
		_fail("ChunkManager must skip stream outside finite world")
	else:
		_ok("ChunkManager outside-world stream skip")

	var world = _InfiniteNoiseWorld.new(SEED)
	var mgr = _ChunkManager.new()
	mgr.prebuild_chunk_buffers = true
	mgr.terrain_surface_mesh = true

	var do_full := OS.get_environment("CRYSTALSTORM_FULL_WORLD_BAKE_RUN").strip_edges() == "1"
	var bake: _WorldBakeService = _WorldBakeService.ensure_active()
	var mem0 := OS.get_static_memory_usage()
	var bake_result: Dictionary
	var plan_bytes := 0
	var col_bytes := 0

	if do_full:
		OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "1")
		OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "")
		OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "1")
		bake.delete_bake(SEED, -1)
		print("FULL_WORLD_BAKE_RUN starting expected_chunks=%d ..." % exp_chunks)
		bake_result = bake.bake_world(world, -1, mgr)
	else:
		# Smoke: explicit radius package but exercise full-world bounds APIs + runtime prefer.
		OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
		OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
		bake.delete_bake(SEED, 2)
		bake_result = bake.bake_world(world, 2, mgr)

	if not bool(bake_result.get("ok", false)):
		_fail("bake_world failed: %s" % str(bake_result.get("error", "")))
		_finish()
		return

	if do_full:
		if not bool(bake_result.get("full_world", false)):
			_fail("full bake must set full_world flag")
		if int(bake_result.get("chunks", 0)) != exp_chunks:
			_fail(
				"full bake chunk count %d != expected %d"
				% [int(bake_result.get("chunks", 0)), exp_chunks]
			)
		else:
			_ok("full bake covers entire playable map chunks=%d bake_ms=%d" % [
				exp_chunks, int(bake_result.get("bake_ms", 0))
			])
		var b: Dictionary = bake_result.get("bounds", {})
		if int(b.get("min_cx", 0)) != int(bounds.min_cx) or int(b.get("max_cx", 0)) != int(bounds.max_cx):
			_fail("full bake bounds mismatch package vs WorldBorder")
		else:
			_ok("full bake bounds match WorldBorder span")
	else:
		_ok(
			"smoke bake chunks=%d bake_ms=%d (set CRYSTALSTORM_FULL_WORLD_BAKE_RUN=1 for full map)"
			% [int(bake_result.get("chunks", 0)), int(bake_result.get("bake_ms", 0))]
		)

	var saved: Dictionary = bake.save_bake()
	if not bool(saved.get("ok", false)):
		_fail("save_bake failed")
		_finish()
		return
	col_bytes = int(saved.get("bytes", 0))
	plan_bytes = int(saved.get("mesh_plan_bytes", 0))
	_ok("save package col_bytes=%d plan_bytes=%d meta=%d" % [
		col_bytes, plan_bytes, int(saved.get("static_meta_bytes", 0))
	])

	# Reload prefer path
	_WorldBakeService.clear_active()
	_MeshPlanCache.clear_active()
	var bake2: _WorldBakeService = _WorldBakeService.ensure_active()
	if do_full:
		OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "1")
		OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "")
		if not bake2.load_bake_for_seed(SEED, true):
			_fail("load full package failed: %s" % bake2.last_error)
			_finish()
			return
		_ok("load full index chunks=%d load_ms=%d full=%s streamed=%s resident=%d" % [
			bake2.chunk_count(), bake2.last_load_time_ms, str(bake2.full_world),
			str(bake2.streamed), bake2.resident_count()
		])
	else:
		if not bake2.load_bake(SEED, 2):
			_fail("load smoke package failed: %s" % bake2.last_error)
			_finish()
			return
		_ok("load smoke index chunks=%d resident=%d streamed=%s" % [
			bake2.chunk_count(), bake2.resident_count(), str(bake2.streamed)
		])
	if bake2.streamed and bake2.resident_count() != 0:
		_fail("index load must not load all chunks into RAM")
	_WorldBakeService.set_active(bake2)
	bake2.ensure_mesh_plans(mgr, world)

	# Sample in-bounds prefer bake + mesh cache
	_WorldState.replace_active()
	var samples: Array = [Vector2i(0, 0), Vector2i(1, -1)]
	if do_full:
		samples.append(Vector2i(int(bounds.min_cx), int(bounds.min_cz)))
		samples.append(Vector2i(int(bounds.max_cx), int(bounds.max_cz)))
	var load_us_total := 0
	var n_ok := 0
	for coord in samples:
		if not bake2.has_chunk(coord):
			_fail("sample chunk missing from package %s" % str(coord))
			continue
		var d = _ChunkData.new(coord, world)
		d.capture_worker_snapshot()
		var t0 := Time.get_ticks_usec()
		var job: Dictionary = _ChunkPipeline.run_worker_job(
			mgr, d, true, [], Rect2i(0, 0, _ChunkData.SIZE, _ChunkData.SIZE), [], {}, true, true
		)
		load_us_total += Time.get_ticks_usec() - t0
		if not bool(job.get("ok", false)):
			_fail("worker job failed %s" % str(coord))
			continue
		if str(job.get("column_source", "")) != "bake":
			_fail("in-bounds column_source want bake got=%s @%s" % [str(job.get("column_source")), str(coord)])
			continue
		n_ok += 1
	if n_ok == samples.size():
		_ok("in-bounds samples prefer bake n=%d avg_load_us=%.1f" % [
			n_ok, float(load_us_total) / float(maxi(n_ok, 1))
		])

	# Dig invalidation still regenerates mesh
	_WorldState.replace_active()
	_TerrainEdits.dig(2, 2, 1)
	var d_dig = _ChunkData.new(Vector2i(0, 0), world)
	d_dig.capture_worker_snapshot()
	var job_dig: Dictionary = _ChunkPipeline.run_worker_job(
		mgr, d_dig, true, [], Rect2i(0, 0, _ChunkData.SIZE, _ChunkData.SIZE), [], {}, true, true
	)
	if str(job_dig.get("mesh_source", "")) != "generate":
		_fail("dig must invalidate mesh plan got=%s" % str(job_dig.get("mesh_source")))
	else:
		_ok("dig invalidates mesh plan → generate")

	# Outside bounds: stream skip API + no infinite generate requirement
	if _WorldBakeService.is_chunk_outside_finite_world(outside):
		_ok("outside bounds refused as finite-world edge %s" % str(outside))

	# When full_world package active, missing in-bounds should block generate
	if do_full and bake2.full_world:
		var fake := Vector2i(int(bounds.min_cx), int(bounds.min_cz))
		# Temporarily erase one chunk from memory to test block path
		if bake2._chunks.has(fake):
			var kept = bake2._chunks[fake]
			bake2._chunks.erase(fake)
			var d_b = _ChunkData.new(fake, world)
			d_b.capture_worker_snapshot()
			var colb: Dictionary = _ChunkPipeline.run_column_stage(mgr, d_b, true, [])
			if str(colb.get("column_source", "")) != "blocked":
				_fail("full-world miss must block generate got=%s" % str(colb.get("column_source")))
			else:
				_ok("full-world in-bounds miss blocks procedural generate")
			bake2._chunks[fake] = kept

	# Corrupt / version (smoke path)
	if not do_full:
		if bake2.corrupt_bake_file(SEED, 2):
			var bad := _WorldBakeService.new()
			if bad.load_bake(SEED, 2):
				_fail("corrupt must fail load")
			else:
				_ok("corrupt rejected: %s" % bad.last_error)
		var stub := bake2.write_version_mismatch_stub(SEED, 2)
		if not stub.is_empty():
			var badv := _WorldBakeService.new()
			if badv.load_bake(SEED, 2):
				_fail("version mismatch must fail")
			else:
				_ok("version mismatch rejected: %s" % badv.last_error)
		# Safe regenerate
		var reb: Dictionary = bake2.bake_world(world, 2, mgr)
		var res: Dictionary = bake2.save_bake()
		if bool(reb.get("ok", false)) and bool(res.get("ok", false)):
			_ok("safe regenerate after corrupt/version tests")

	var mem1 := OS.get_static_memory_usage()
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-3c89103bbbb9/implementer"
	var perf := {
		"seed": SEED,
		"full_world_run": do_full,
		"expected_full_chunks": exp_chunks,
		"baked_chunks": int(bake_result.get("chunks", 0)),
		"bake_ms": int(bake_result.get("bake_ms", 0)),
		"column_bytes": col_bytes,
		"mesh_plan_bytes": plan_bytes,
		"total_bake_bytes": col_bytes + plan_bytes,
		"load_ms": bake2.last_load_time_ms,
		"avg_sample_chunk_load_us": float(load_us_total) / float(maxi(n_ok, 1)),
		"mem_delta_bytes": mem1 - mem0,
		"bounds": bounds,
	}
	var pf := FileAccess.open(scratch.path_join("full_world_bake_perf.json"), FileAccess.WRITE)
	if pf:
		pf.store_string(JSON.stringify(perf, "\t"))
		pf.close()
		_ok("wrote full_world_bake_perf.json")
	print(
		"PERF_SUMMARY full_run=%s chunks=%s bake_ms=%s bytes=%s avg_chunk_us=%.1f"
		% [
			str(do_full),
			str(perf.baked_chunks),
			str(perf.bake_ms),
			str(perf.total_bake_bytes),
			float(perf.avg_sample_chunk_load_us),
		]
	)

	_finish()


func _finish() -> void:
	_WorldBakeService.clear_active()
	_MeshPlanCache.clear_active()
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "All full world bake tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "Full world bake FAILED (%d)" % _failed)
