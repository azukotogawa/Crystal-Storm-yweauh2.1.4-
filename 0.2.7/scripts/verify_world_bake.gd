extends SceneTree
## World Bake Pipeline: immutable base bake + prefer path + overlays + safe regenerate.
## Usage: godot --headless -s scripts/verify_world_bake.gd
## Env: CRYSTALSTORM_PROBE_ABRUPT_EXIT=1 for harness OK marker kill.

const _WorldState = preload("res://world/world_state.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkPipeline = preload("res://chunks/chunk_pipeline.gd")
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")
const _WorldBakeService = preload("res://world/world_bake_service.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const SEED := 424242
const RADIUS := 2  # 5x5 chunks — fast verify + measurable

var _failed: int = 0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	# Prefer bake when present; smoke radius (not multi-minute full map) for this suite.
	OS.set_environment("CRYSTALSTORM_WORLD_BAKE", "1")
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
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

	# --- Structural API ---
	var bake: _WorldBakeService = _WorldBakeService.new()
	_WorldBakeService.set_active(bake)
	if bake.BAKE_VERSION < 1:
		_fail("BAKE_VERSION must be >= 1")
	else:
		_ok("bake version=%d" % bake.BAKE_VERSION)
	if not bake.has_method("bake_world") or not bake.has_method("save_bake") \
			or not bake.has_method("load_bake") or not bake.has_method("try_apply_base_to_chunk_data"):
		_fail("WorldBakeService missing core APIs")
	else:
		_ok("WorldBakeService core APIs present")

	# Prefer path wired in pipeline
	var pipe_src := FileAccess.get_file_as_string("res://chunks/chunk_pipeline.gd")
	if "try_apply_base_to_chunk_data" not in pipe_src and "world_bake" not in pipe_src.to_lower():
		_fail("ChunkPipeline must prefer bake in column stage")
	else:
		_ok("ChunkPipeline column prefer-bake wiring")
	var cm_src := FileAccess.get_file_as_string("res://chunks/chunk_manager.gd")
	if "_bootstrap_world_bake" not in cm_src:
		_fail("ChunkManager must bootstrap WorldBakeService")
	else:
		_ok("ChunkManager bake bootstrap")

	var world = _InfiniteNoiseWorld.new(SEED)
	bake.delete_bake(SEED, RADIUS)

	# --- Bake once ---
	var b1: Dictionary = bake.bake_world(world, RADIUS)
	if not bool(b1.get("ok", false)):
		_fail("bake_world failed: %s" % str(b1.get("error", "")))
		_finish()
		return
	var expected_chunks: int = (RADIUS * 2 + 1) * (RADIUS * 2 + 1)
	if int(b1.get("chunks", 0)) != expected_chunks:
		_fail("bake chunk count %s want %d" % [str(b1.get("chunks")), expected_chunks])
	else:
		_ok("bake_world chunks=%d bake_ms=%d" % [expected_chunks, int(b1.get("bake_ms", 0))])

	var s1: Dictionary = bake.save_bake()
	if not bool(s1.get("ok", false)):
		_fail("save_bake failed: %s" % str(s1.get("error", "")))
		_finish()
		return
	var bake_bytes: int = int(s1.get("bytes", 0))
	if bake_bytes <= 0:
		_fail("bake size must be > 0")
	else:
		_ok("save_bake bytes=%d path=%s" % [bake_bytes, str(s1.get("path", ""))])

	# Snapshot reference columns from bake memory
	var ref_samples: Array = []
	for coord in [Vector2i(0, 0), Vector2i(1, -1), Vector2i(-RADIUS, RADIUS)]:
		var sample: Dictionary = bake.sample_base(coord, 3, 5)
		if sample.is_empty():
			_fail("sample_base empty for %s" % str(coord))
		else:
			ref_samples.append({"coord": coord, "surface": sample.surface, "tile": sample.tile})
	_ok("reference samples n=%d" % ref_samples.size())

	# --- Deterministic re-bake matches ---
	var bake2: _WorldBakeService = _WorldBakeService.new()
	var world2 = _InfiniteNoiseWorld.new(SEED)
	var b2: Dictionary = bake2.bake_world(world2, RADIUS)
	if not bool(b2.get("ok", false)):
		_fail("second bake failed")
	else:
		var mismatch := 0
		for s in ref_samples:
			var again: Dictionary = bake2.sample_base(s.coord, 3, 5)
			if not is_equal_approx(float(again.get("surface", -1.0)), float(s.surface)):
				mismatch += 1
			if int(again.get("tile", -999)) != int(s.tile):
				mismatch += 1
		if mismatch > 0:
			_fail("deterministic bake mismatch count=%d" % mismatch)
		else:
			_ok("deterministic bake match across two bake_world calls")

	# --- Load from disk matches generate path ---
	var bake_load: _WorldBakeService = _WorldBakeService.new()
	if not bake_load.load_bake(SEED, RADIUS):
		_fail("load_bake failed: %s" % bake_load.last_error)
		_finish()
		return
	_ok("load_bake seed=%d chunks=%d load_ms=%d" % [
		SEED, bake_load.chunk_count(), bake_load.last_load_time_ms
	])
	_WorldBakeService.set_active(bake_load)

	var mgr = _ChunkManager.new()
	var gen_world = _InfiniteNoiseWorld.new(SEED)
	var match_fail := 0
	for s in ref_samples:
		var coord: Vector2i = s.coord
		# Live generate reference (no overlays)
		_WorldState.replace_active()
		var data_gen = _ChunkData.new(coord, gen_world)
		data_gen.capture_worker_snapshot()
		mgr._generate_chunk(data_gen)
		var gen_h: float = float(data_gen.surface_map[3][5])
		var gen_t: int = int(data_gen.tile_map[3][5])
		# Baked apply reference
		var data_bake = _ChunkData.new(coord, gen_world)
		data_bake.capture_worker_snapshot()
		if not bake_load.try_apply_base_to_chunk_data(data_bake):
			_fail("try_apply_base failed for %s" % str(coord))
			continue
		var bh: float = float(data_bake.surface_map[3][5])
		var bt: int = int(data_bake.tile_map[3][5])
		if not is_equal_approx(gen_h, bh) or gen_t != bt:
			match_fail += 1
			print("  mismatch %s gen=(%s,%s) bake=(%s,%s)" % [str(coord), gen_h, gen_t, bh, bt])
	if match_fail > 0:
		_fail("baked base must match generate base mismatches=%d" % match_fail)
	else:
		_ok("baked base matches generate for sampled chunks")

	# --- Prefer path: column_source=bake when bake present ---
	bake_load.reset_stats()
	_WorldState.replace_active()
	var data_pref = _ChunkData.new(Vector2i(0, 0), gen_world)
	data_pref.capture_worker_snapshot()
	var col_pref: Dictionary = _ChunkPipeline.run_column_stage(mgr, data_pref, true, [])
	if str(col_pref.get("column_source", "")) != "bake":
		_fail("prefer path expected column_source=bake got=%s" % str(col_pref.get("column_source")))
	else:
		_ok("prefer path column_source=bake column_us=%d" % int(col_pref.get("column_us", 0)))
	if bake_load.stats_bake_hits < 1:
		_fail("bake hit counter not incremented")
	else:
		_ok("bake hit stats=%d" % bake_load.stats_bake_hits)

	# --- Generate fallback when bake disabled ---
	OS.set_environment("CRYSTALSTORM_WORLD_BAKE", "0")
	bake_load.reset_stats()
	var data_gen_only = _ChunkData.new(Vector2i(0, 0), gen_world)
	data_gen_only.capture_worker_snapshot()
	var col_gen: Dictionary = _ChunkPipeline.run_column_stage(mgr, data_gen_only, true, [])
	if str(col_gen.get("column_source", "")) != "generate":
		_fail("disabled bake must use generate got=%s" % str(col_gen.get("column_source")))
	else:
		_ok("generate fallback when bake disabled column_us=%d" % int(col_gen.get("column_us", 0)))
	OS.set_environment("CRYSTALSTORM_WORLD_BAKE", "1")

	# --- WorldState overlay on baked base (dig) ---
	_WorldState.replace_active()
	_TerrainEdits.dig(3, 5, 2)
	var data_over = _ChunkData.new(Vector2i(0, 0), gen_world)
	data_over.capture_worker_snapshot()
	var base_before_h: float = float(bake_load.sample_base(Vector2i(0, 0), 3, 5).get("surface", 0.0))
	if not bake_load.try_apply_base_to_chunk_data(data_over):
		_fail("overlay apply: bake apply failed")
	else:
		var after_h: float = float(data_over.surface_map[3][5])
		if is_equal_approx(after_h, base_before_h):
			_fail("dig overlay must change surface height base=%s after=%s" % [base_before_h, after_h])
		else:
			_ok("WorldState dig overlay applied on bake base %s→%s" % [base_before_h, after_h])
		# Bake package itself not mutated
		var still: float = float(bake_load.sample_base(Vector2i(0, 0), 3, 5).get("surface", -1.0))
		if not is_equal_approx(still, base_before_h):
			_fail("bake store must stay immutable after overlay apply")
		else:
			_ok("bake store immutable under overlay")

	# Overlay parity: baked+dig vs generate+dig
	_WorldState.replace_active()
	_TerrainEdits.dig(4, 4, 1)
	_TerrainEdits.build_wall(6, 6, _VoxelTypes.STONE)
	var d_bake = _ChunkData.new(Vector2i(0, 0), gen_world)
	d_bake.capture_worker_snapshot()
	bake_load.try_apply_base_to_chunk_data(d_bake)
	var d_gen = _ChunkData.new(Vector2i(0, 0), gen_world)
	d_gen.capture_worker_snapshot()
	mgr._generate_chunk(d_gen)
	var o_fail := 0
	for lx in [4, 6, 3]:
		for lz in [4, 6, 5]:
			if not is_equal_approx(float(d_bake.surface_map[lx][lz]), float(d_gen.surface_map[lx][lz])):
				o_fail += 1
			if int(d_bake.tile_map[lx][lz]) != int(d_gen.tile_map[lx][lz]):
				o_fail += 1
	if o_fail > 0:
		_fail("overlay parity bake vs generate mismatches=%d" % o_fail)
	else:
		_ok("overlay parity dig+build bake vs generate")

	# --- Full worker job mesh still works on bake path ---
	_WorldState.replace_active()
	var d_job = _ChunkData.new(Vector2i(0, 0), gen_world)
	d_job.capture_worker_snapshot()
	var job: Dictionary = _ChunkPipeline.run_worker_job(
		mgr, d_job, true, [], Rect2i(0, 0, _ChunkData.SIZE, _ChunkData.SIZE), [], {}, false, true
	)
	if not bool(job.get("ok", false)):
		_fail("run_worker_job on bake path failed")
	elif str(job.get("column_source", "")) != "bake":
		_fail("worker job column_source want bake got=%s" % str(job.get("column_source")))
	elif int(job.get("merged_quads", []).size()) <= 0:
		_fail("mesh produced no quads on bake path")
	else:
		_ok(
			"worker job bake path quads=%d column_us=%d mesh_us=%d"
			% [job.get("merged_quads", []).size(), int(job.get("column_us", 0)), int(job.get("build_mesh_us", 0))]
		)

	# --- Corrupted bake regenerates safely ---
	if not bake_load.corrupt_bake_file(SEED, RADIUS):
		_fail("corrupt_bake_file failed")
	else:
		var bad: _WorldBakeService = _WorldBakeService.new()
		if bad.load_bake(SEED, RADIUS):
			_fail("corrupt bake must fail load")
		else:
			_ok("corrupt bake rejected: %s" % bad.last_error)
			# Safe regenerate
			var rebake: Dictionary = bad.bake_world(gen_world, RADIUS)
			if not bool(rebake.get("ok", false)):
				_fail("regenerate after corrupt failed")
			else:
				var resave: Dictionary = bad.save_bake()
				if not bool(resave.get("ok", false)):
					_fail("resave after corrupt failed")
				else:
					_ok("corrupt bake safe regenerate+save")

	# --- Version mismatch regenerates safely ---
	var stub_path: String = bake_load.write_version_mismatch_stub(SEED, RADIUS)
	if stub_path.is_empty():
		_fail("version mismatch stub write failed")
	else:
		var badv: _WorldBakeService = _WorldBakeService.new()
		if badv.load_bake(SEED, RADIUS):
			_fail("version mismatch must fail load")
		else:
			_ok("version mismatch rejected: %s" % badv.last_error)
			var reb: Dictionary = badv.bake_world(gen_world, RADIUS)
			var res: Dictionary = badv.save_bake()
			if not bool(reb.get("ok", false)) or not bool(res.get("ok", false)):
				_fail("regenerate after version mismatch failed")
			else:
				_ok("version mismatch safe regenerate")

	# --- Measured perf: generate vs bake column stage (same chunks) ---
	_WorldState.replace_active()
	bake_load.reset_stats()
	# Ensure valid bake loaded
	if not bake_load.load_bake(SEED, RADIUS):
		# rebaked above
		bake_load.bake_world(gen_world, RADIUS)
		bake_load.save_bake()
		bake_load.load_bake(SEED, RADIUS)
	_WorldBakeService.set_active(bake_load)

	var coords: Array = []
	for cz in range(-RADIUS, RADIUS + 1):
		for cx in range(-RADIUS, RADIUS + 1):
			coords.append(Vector2i(cx, cz))

	# Before: force generate
	OS.set_environment("CRYSTALSTORM_WORLD_BAKE", "0")
	var gen_us_total := 0
	var gen_n := 0
	var mesh_us_total := 0
	var mesh_n := 0
	for coord in coords:
		var d = _ChunkData.new(coord, gen_world)
		d.capture_worker_snapshot()
		var j: Dictionary = _ChunkPipeline.run_worker_job(
			mgr, d, true, [], Rect2i(0, 0, _ChunkData.SIZE, _ChunkData.SIZE), [], {}, false, true
		)
		if bool(j.get("ok", false)):
			gen_us_total += int(j.get("column_us", 0))
			mesh_us_total += int(j.get("build_mesh_us", 0))
			gen_n += 1
			mesh_n += 1
	var avg_gen_col := float(gen_us_total) / float(maxi(gen_n, 1))
	var avg_mesh := float(mesh_us_total) / float(maxi(mesh_n, 1))

	# After: bake prefer
	OS.set_environment("CRYSTALSTORM_WORLD_BAKE", "1")
	_WorldBakeService.set_active(bake_load)
	bake_load.reset_stats()
	var bake_us_total := 0
	var bake_n := 0
	var mem_before := OS.get_static_memory_usage()
	for coord in coords:
		var d = _ChunkData.new(coord, gen_world)
		d.capture_worker_snapshot()
		var j: Dictionary = _ChunkPipeline.run_worker_job(
			mgr, d, true, [], Rect2i(0, 0, _ChunkData.SIZE, _ChunkData.SIZE), [], {}, false, true
		)
		if bool(j.get("ok", false)):
			bake_us_total += int(j.get("column_us", 0))
			bake_n += 1
			if str(j.get("column_source", "")) != "bake":
				_fail("expected bake source for covered coord %s got %s" % [
					str(coord), str(j.get("column_source"))
				])
	var avg_bake_col := float(bake_us_total) / float(maxi(bake_n, 1))
	var mem_after := OS.get_static_memory_usage()
	_ok(
		"perf avg_column_us generate=%.1f bake=%.1f mesh=%.1f samples=%d bake_bytes=%d mem_delta=%d"
		% [avg_gen_col, avg_bake_col, avg_mesh, bake_n, bake_load.last_bake_bytes, mem_after - mem_before]
	)

	# Streaming unchanged structural: pipeline stages list still intact
	if _ChunkPipeline.STAGES.size() < 6:
		_fail("streaming stages altered")
	else:
		_ok("streaming stages unchanged count=%d" % _ChunkPipeline.STAGES.size())

	# Crystal / towns / ruins structural: bake service does not own them
	var wb_src := FileAccess.get_file_as_string("res://world/world_bake_service.gd")
	if "CrystalSimulation" in wb_src or "class_name CrystalManager" in wb_src:
		_fail("bake must not absorb crystal sim")
	if "WorldState.replace_active" in wb_src and "bake_world" in wb_src:
		# OK if comments only — ensure bake_world doesn't write height_delta
		pass
	if "height_delta[" in wb_src or "build_tile[" in wb_src:
		_fail("bake service must not mutate WorldState storage")
	else:
		_ok("bake does not mutate WorldState / crystal ownership")

	# Write perf JSON for report
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-05cc82161a8f/implementer"
	var perf := {
		"seed": SEED,
		"radius": RADIUS,
		"chunks": expected_chunks,
		"bake_time_ms": int(b1.get("bake_ms", bake_load.last_bake_time_ms)),
		"load_time_ms": bake_load.last_load_time_ms,
		"bake_bytes": bake_load.last_bake_bytes,
		"avg_column_us_generate": avg_gen_col,
		"avg_column_us_bake": avg_bake_col,
		"avg_mesh_us": avg_mesh,
		"column_speedup": (avg_gen_col / avg_bake_col) if avg_bake_col > 0.0 else 0.0,
		"mem_static_delta_bytes": mem_after - mem_before,
		"samples": bake_n,
	}
	var pf := FileAccess.open(scratch.path_join("bake_perf.json"), FileAccess.WRITE)
	if pf:
		pf.store_string(JSON.stringify(perf, "\t"))
		pf.close()
		_ok("wrote bake_perf.json")
	else:
		print("NOTE could not write bake_perf.json to %s" % scratch)

	print(
		"PERF_SUMMARY bake_ms=%s bytes=%s avg_col_gen_us=%.1f avg_col_bake_us=%.1f avg_mesh_us=%.1f speedup=%.2fx"
		% [
			str(perf.bake_time_ms),
			str(perf.bake_bytes),
			avg_gen_col,
			avg_bake_col,
			avg_mesh,
			float(perf.column_speedup),
		]
	)

	_finish()


func _finish() -> void:
	_WorldBakeService.clear_active()
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "All world bake tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "World bake FAILED (%d)" % _failed)
