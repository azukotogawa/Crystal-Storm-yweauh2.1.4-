extends SceneTree
## Player reverses direction quickly across chunk borders while workers are busy.
## Afterwards exactly the needed chunks are resident, each with the right mesh
## and data, no views dangle, and no task ids remain.

const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _U = preload("res://scripts/stream_test_util.gd")
const STEP := 3
const CYCLES := 4

var _failed := 0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL: %s" % msg)


func _ok(msg: String) -> void:
	print("OK %s" % msg)


func _sleep(ms: int) -> void:
	OS.delay_msec(ms)


func _hold(cm: Node, c: Vector2i, frames: int) -> void:
	for _i in frames:
		_U.set_player_chunk(cm, c)
		await process_frame


func _check_state(cm: Node, c: Vector2i, ref: Dictionary, tag: String) -> void:
	var needed := _U.needed_set(cm, c)
	var missing := 0
	for k in needed.keys():
		if not cm.chunks.has(k):
			missing += 1
			if missing <= 5:
				_fail("%s: needed chunk %s not resident" % [tag, str(k)])
	var extra := 0
	for k in cm.chunks.keys():
		if not needed.has(k):
			extra += 1
			if extra <= 5:
				_fail("%s: unneeded chunk %s still resident" % [tag, str(k)])
	if missing == 0 and extra == 0:
		_ok("%s: resident set matches needed set (%d)" % [tag, needed.size()])
	var bad := _U.view_problems(cm)
	for b in bad:
		_fail("%s: %s" % [tag, b])
	if bad.is_empty():
		_ok("%s: no dangling or mismatched views" % tag)
	var diff := 0
	var compared := 0
	for k in ref.keys():
		if cm.chunks.has(k):
			compared += 1
			if _U.chunk_sig(cm, k) != ref[k]:
				diff += 1
				if diff <= 5:
					_fail("%s: chunk %s mesh/data differs from reference" % [tag, str(k)])
	if diff == 0:
		_ok("%s: %d chunks match reference mesh and data" % [tag, compared])
	if not cm._chunk_tasks.is_empty() or _U.orphan_count(cm) > 0:
		_fail("%s: task ids left tasks=%d orphans=%d" % [tag, cm._chunk_tasks.size(), _U.orphan_count(cm)])
	var added = cm.get("orphan_tasks_added")
	var reaped = cm.get("orphan_tasks_reaped")
	if added != null and reaped != null and int(added) != int(reaped):
		_fail("%s: orphan ids added %d reaped %d" % [tag, int(added), int(reaped)])


func _run() -> void:
	var cm = await _U.boot(self)
	if cm == null or cm.player == null:
		_fail("chunk_manager or player missing")
		_ProbeExit.finish_tree(self, 1, "fast reversal FAILED")
		return
	var c0: Vector2i = cm.get_player_chunk_coord()
	await _hold(cm, c0, 2)
	c0 = cm.get_player_chunk_coord()
	if await _U.settle(self, cm) < 0:
		_fail("world did not settle after boot")
	var ref0 := _U.snapshot_sigs(cm)
	# Step toward the world interior: a target past the world edge has fewer needed
	# chunks and the player gets held back at the edge.
	var c1 := c0 + Vector2i(STEP, 0)
	var best := -1
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: int = _U.needed_set(cm, c0 + d * STEP).size()
		if n > best:
			best = n
			c1 = c0 + d * STEP
	if best < _U.needed_set(cm, c0).size():
		_fail("no interior direction from %s (best needed %d)" % [str(c0), best])
	print("REVERSAL c0=%s c1=%s chunks=%d" % [str(c0), str(c1), cm.chunks.size()])

	# Learn the reference state at c1, then return to c0.
	await _hold(cm, c1, 1)
	await _U.settle(self, cm)
	var ref1 := _U.snapshot_sigs(cm)
	if cm.get_player_chunk_coord() != c1:
		_fail("player did not stay at %s (at %s)" % [str(c1), str(cm.get_player_chunk_coord())])
	await _hold(cm, c0, 1)
	await _U.settle(self, cm)
	_check_state(cm, c0, ref0, "warmup")

	# Fast reversals with the pool saturated so chunk tasks stay queued.
	var t0 := Time.get_ticks_msec()
	for i in CYCLES:
		var sleepers := _U.saturate_pool(Callable(self, "_sleep").bind(60))
		await _hold(cm, c1, 2 + i % 2)
		await _hold(cm, c0, 1 + i % 3)
		_U.wait_all(sleepers)
	# Zig-zag one chunk at a time with no settling.
	for i in 6:
		await _hold(cm, c0 + (c1 - c0) / STEP * (i % 2), 1)
	await _hold(cm, c0, 1)
	print("REVERSAL_MS %d" % (Time.get_ticks_msec() - t0))
	if await _U.settle(self, cm) < 0:
		_fail("did not settle after reversals")
	_check_state(cm, c0, ref0, "after_reversal_c0")

	# End on the far side too.
	var sleepers2 := _U.saturate_pool(Callable(self, "_sleep").bind(60))
	await _hold(cm, c1, 1)
	await _hold(cm, c0, 1)
	await _hold(cm, c1, 1)
	_U.wait_all(sleepers2)
	await _hold(cm, c1, 1)
	if await _U.settle(self, cm) < 0:
		_fail("did not settle at c1")
	if cm.get_player_chunk_coord() != c1:
		_fail("player did not stay at %s (at %s)" % [str(c1), str(cm.get_player_chunk_coord())])
	print("REVERSAL_DIAG player=%s last=%s resident=%d needed=%d" % [str(cm.get_player_chunk_coord()), str(cm._last_chunk_key), cm.chunks.size(), _U.needed_set(cm, c1).size()])
	_check_state(cm, c1, ref1, "after_reversal_c1")

	await _U.shutdown(self, cm)
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "All fast reversal tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "Fast reversal FAILED (%d)" % _failed)
