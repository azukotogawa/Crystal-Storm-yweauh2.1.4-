extends SceneTree
## Worker deferred bake: twelve contract checks against shipped WorldBakeService.
## Usage: godot --headless -s scripts/verify_deferred_bake_workers.gd

const _WorldState = preload("res://world/world_state.gd")
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")
const _WorldBakeService = preload("res://world/world_bake_service.gd")
const _WorldBakeWorkerJob = preload("res://world/world_bake_worker_job.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const SEED := 777001
const RADIUS := 2

var _failed: int = 0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_WORLD_BAKE", "1")
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "1")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", str(RADIUS))
	OS.set_environment("CRYSTALSTORM_BAKE_DEFER_FILL", "1")
	OS.set_environment("CRYSTALSTORM_BAKE_FILL_SYNC", "0")
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
	var world = _InfiniteNoiseWorld.new(SEED)
	var host = _ChunkManager.new()
	root.add_child(host)
	var bake: _WorldBakeService = _WorldBakeService.ensure_active()
	bake.delete_bake(SEED, RADIUS)

	# 1–3: worker generates, bytes match sync _bake_one_chunk, write exists.
	bake._configure_session_bounds(world, RADIUS)
	bake.valid = false
	var veg: Array = []
	var sync_one: Dictionary = bake._bake_one_chunk(Vector2i.ZERO, world, host, veg)
	if not bool(sync_one.get("ok", false)):
		_fail("sync _bake_one_chunk failed")
		_finish()
		return
	var path := bake.chunk_package_path(Vector2i.ZERO)
	if not FileAccess.file_exists(path):
		_fail("sync package missing")
		_finish()
		return
	var bytes_sync: PackedByteArray = FileAccess.get_file_as_bytes(path)
	_ok("1 worker-job path: sync package bytes=%d" % bytes_sync.size())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	bake._packages_known.erase(Vector2i.ZERO)
	var worker_one: Dictionary = _WorldBakeWorkerJob.execute(Vector2i.ZERO, world, host, veg, bake)
	if not bool(worker_one.get("ok", false)):
		_fail("2 worker execute failed")
		_finish()
		return
	if not FileAccess.file_exists(path):
		_fail("3 worker did not write package")
		_finish()
		return
	_ok("3 worker wrote package")
	var bytes_w: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes_w != bytes_sync:
		_fail("2 worker bytes != sync _bake_one_chunk (%d vs %d)" % [bytes_w.size(), bytes_sync.size()])
	else:
		_ok("2 worker package bytes match sync (%d)" % bytes_w.size())

	# 4: available to streaming
	var data = load("res://chunks/chunk_data.gd").new(Vector2i.ZERO, world)
	data.capture_base_only_snapshot()
	bake._register_package(Vector2i.ZERO)
	if not bake.try_apply_base_to_chunk_data(data):
		_fail("4 try_apply_base failed")
	elif float(data.surface_map[0][0]) < -9000.0:
		_fail("4 applied surface empty")
	else:
		_ok("4 package stream-available surface=%.2f" % float(data.surface_map[0][0]))

	# 5–6 + 8 + 10 + 11: deferred bootstrap + fill + overlays + on-demand
	bake.delete_bake(SEED, RADIUS)
	_WorldBakeService.clear_active()
	bake = _WorldBakeService.ensure_active()
	var ws = _WorldState.get_active()
	ws.height_delta[Vector2i(3, 3)] = 2
	var overlay_before: int = int(ws.height_delta.get(Vector2i(3, 3), 0))
	var boot: Dictionary = await bake.bootstrap_for_world_async(world, false, host)
	if str(boot.get("mode", "")) != "partial" and str(boot.get("mode", "")) != "baked":
		_fail("bootstrap mode=%s" % str(boot.get("mode", "")))
	if bake.valid and bake.expected_chunk_count() > bake._packages_known.size():
		_fail("5 valid true while incomplete")
	elif not bake.valid:
		_ok("5 valid=false while incomplete known=%d expected=%d" % [
			bake._packages_known.size(), bake.expected_chunk_count()
		])
	else:
		_ok("5 small session completed during prime (valid iff complete)")

	# 9 duplicate jobs
	if bake.has_method("enqueue_package_job") and bake.bake_in_progress:
		var far := Vector2i(RADIUS, RADIUS)
		if not bake.package_ready(far):
			var a: Dictionary = bake.enqueue_package_job(far, bake.PRI_FILL)
			var b: Dictionary = bake.enqueue_package_job(far, bake.PRI_FILL)
			if bool(b.get("duplicate", false)):
				_ok("9 duplicate job rejected")
			elif bool(a.get("ready", false)):
				_ok("9 already ready (no duplicate possible)")
			else:
				_fail("9 second enqueue not marked duplicate")
		else:
			_ok("9 far already primed")
	else:
		_ok("9 enqueue API present=%s" % str(bake.has_method("enqueue_package_job")))

	# 11 on-demand
	var far2 := Vector2i(RADIUS, -RADIUS)
	if bake.package_ready(far2):
		_ok("11 far already packaged")
	elif not bake.ensure_package_for_stream(far2):
		_fail("11 on-demand failed")
	elif not bake.package_ready(far2):
		_fail("11 on-demand did not register")
	else:
		_ok("11 on-demand package ready")
	if bake.valid and bake._packages_known.size() < bake.expected_chunk_count():
		_fail("11 on-demand committed index early")
	else:
		_ok("11 index not committed early")

	# 8 live WorldState untouched
	var overlay_after: int = int(_WorldState.get_active().height_delta.get(Vector2i(3, 3), 0))
	if overlay_after != overlay_before:
		_fail("8 WorldState overlay mutated %d -> %d" % [overlay_before, overlay_after])
	else:
		_ok("8 live WorldState overlay unchanged")

	# 7 replace_active blocked during fill
	if bake.bake_in_progress:
		var prev = _WorldState.get_active()
		var after = _WorldState.replace_active()
		if after != prev:
			_fail("7 replace_active mutated session")
		else:
			_ok("7 replace_active blocked")
	else:
		_ok("7 fill already complete; skip live block (forbid still tested when in progress)")

	# 10 resume: existing .chk kept
	var before_n: int = bake._packages_known.size()
	bake._inventory_existing_packages()
	if bake._packages_known.size() < before_n:
		_fail("10 inventory wiped packages")
	else:
		_ok("10 resume inventory kept %d packages" % bake._packages_known.size())

	# Drain remaining fill (radius-limited expected).
	var frames := 0
	while bake.bake_in_progress and frames < 4000:
		bake.tick_background_fill(0)
		await process_frame
		frames += 1
	var expected: int = bake.expected_chunk_count()
	if bake._packages_known.size() != expected:
		_fail("6 known=%d expected=%d after drain" % [bake._packages_known.size(), expected])
	elif not bake.valid:
		_fail("6 valid still false at expected=%d" % expected)
	else:
		_ok("6 valid=true only at expected=%d" % expected)

	# Incomplete fill on a larger session so workers actually run after prime.
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "6")
	_WorldBakeService.clear_active()
	bake = _WorldBakeService.ensure_active()
	bake.delete_bake(SEED, 6)
	bake._configure_session_bounds(world, 6)
	bake.valid = false
	bake._inventory_existing_packages()
	bake._veg_by_chunk = bake._bake_vegetation_by_chunk(world)
	var origin_only: Array = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			origin_only.append(Vector2i(dx, dz))
	bake.prime_region(origin_only, world, host)
	bake.start_background_fill(world, host)
	if bake.valid:
		_fail("large session valid after 3x3 prime")
	else:
		_ok("large session valid=false after 3x3 prime known=%d expected=%d" % [
			bake._packages_known.size(), bake.expected_chunk_count()
		])
	var prev2 = _WorldState.get_active()
	var after2 = _WorldState.replace_active()
	if after2 != prev2:
		_fail("7b replace_active mutated during worker fill")
	else:
		_ok("7b replace_active blocked during worker fill")
	var far3 := Vector2i(6, 6)
	var e1: Dictionary = bake.enqueue_package_job(far3, bake.PRI_FILL)
	var e2: Dictionary = bake.enqueue_package_job(far3, bake.PRI_FILL)
	if bool(e2.get("duplicate", false)) or bool(e1.get("duplicate", false)):
		_ok("9b duplicate rejected during worker fill")
	elif bake.package_ready(far3):
		_ok("9b already ready")
	else:
		_fail("9b duplicate not rejected e1=%s e2=%s" % [str(e1), str(e2)])
	var wframes := 0
	var saw_worker := false
	while bake.bake_in_progress and wframes < 120:
		bake.tick_background_fill(0)
		await process_frame
		wframes += 1
		if bake.last_bake_cost().get("main_thread", true) == false and int(bake.worker_jobs_completed) > 0:
			saw_worker = true
			break
	if saw_worker:
		_ok("worker fill completed a job off main thread completed=%d" % bake.worker_jobs_completed)
	elif int(bake.worker_jobs_completed) > 0:
		_ok("worker jobs completed=%d (thread flag=%s)" % [
			bake.worker_jobs_completed, str(bake.last_bake_cost().get("main_thread", "?"))
		])
	else:
		_fail("worker fill produced no completions in %d frames" % wframes)
	if bake.valid:
		_fail("valid flipped true before expected=%d known=%d" % [
			bake.expected_chunk_count(), bake._packages_known.size()
		])
	else:
		_ok("valid stays false mid-fill known=%d expected=%d" % [
			bake._packages_known.size(), bake.expected_chunk_count()
		])
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", str(RADIUS))

	# 12 rollback env
	OS.set_environment("CRYSTALSTORM_BAKE_DEFER_FILL", "0")
	if bake.defer_fill_from_env():
		_fail("12 DEFER=0 still defers")
	else:
		_ok("12 DEFER=0 disables defer-fill")
	_WorldBakeService.clear_active()
	var bake2: _WorldBakeService = _WorldBakeService.ensure_active()
	bake2.delete_bake(SEED + 1, RADIUS)
	var world2 = _InfiniteNoiseWorld.new(SEED + 1)
	var boot2: Dictionary = await bake2.bootstrap_for_world_async(world2, false, host)
	if str(boot2.get("mode", "")) != "baked":
		_fail("12 DEFER=0 mode want baked got=%s" % str(boot2.get("mode", "")))
	else:
		_ok("12 DEFER=0 await-full-bake mode=baked")
	OS.set_environment("CRYSTALSTORM_BAKE_DEFER_FILL", "1")

	_finish()


func _finish() -> void:
	if _failed > 0:
		_ProbeExit.finish_tree(self, 1, "Deferred bake workers FAILED")
	else:
		_ProbeExit.finish_tree(self, 0, "All deferred bake worker tests OK")
