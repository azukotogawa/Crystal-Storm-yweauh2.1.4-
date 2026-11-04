extends SceneTree
## Unloading a chunk whose mesh task is still queued must not block the main
## thread, must not leak the task id, and must drop the stale result.

const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _U = preload("res://scripts/stream_test_util.gd")
const SLEEP_MS := 400
const MAX_UNLOAD_MS := 20.0

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


func _check_clean(cm: Node, tag: String) -> void:
	if not cm._chunk_tasks.is_empty():
		_fail("%s: chunk tasks left %d" % [tag, cm._chunk_tasks.size()])
	if _U.orphan_count(cm) != 0:
		_fail("%s: orphan task ids left %d" % [tag, _U.orphan_count(cm)])
	var added = cm.get("orphan_tasks_added")
	var reaped = cm.get("orphan_tasks_reaped")
	if added == null or reaped == null:
		_fail("%s: manager has no orphan task counters" % tag)
	elif int(added) != int(reaped):
		_fail("%s: orphan ids added %d reaped %d (leak)" % [tag, int(added), int(reaped)])
	else:
		_ok("%s: orphan ids added=%d reaped=%d" % [tag, int(added), int(reaped)])
	var bad := _U.view_problems(cm)
	for b in bad:
		_fail("%s: %s" % [tag, b])
	if bad.is_empty():
		_ok("%s: views consistent (%d chunks)" % [tag, cm.chunks.size()])


## Unload key while its rebuild task is queued behind busy workers.
func _unload_with_queued_task(cm: Node, key: Vector2i, tag: String) -> float:
	var sleepers := _U.saturate_pool(Callable(self, "_sleep").bind(SLEEP_MS))
	cm.rebuild_chunk(key)
	if not cm._chunk_tasks.has(key):
		_fail("%s: rebuild did not queue a task for %s" % [tag, str(key)])
	var t0 := Time.get_ticks_usec()
	cm._unload_chunk_view(key)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("UNLOAD_MS %s %.2f" % [tag, ms])
	if ms > MAX_UNLOAD_MS:
		_fail("%s: unload blocked %.1f ms on a queued task (max %.0f)" % [tag, ms, MAX_UNLOAD_MS])
	else:
		_ok("%s: unload took %.2f ms with task queued" % [tag, ms])
	if cm.chunks.has(key):
		_fail("%s: chunk still resident after unload" % tag)
	_U.wait_all(sleepers)
	return ms


func _run() -> void:
	var cm = await _U.boot(self)
	if cm == null:
		_fail("chunk_manager missing")
		_ProbeExit.finish_tree(self, 1, "unload no-block FAILED")
		return
	if await _U.settle(self, cm) < 0:
		_fail("world did not settle after boot")
	var keys: Array = cm.chunks.keys()
	if keys.size() < 4:
		_fail("too few chunks streamed: %d" % keys.size())
		_ProbeExit.finish_tree(self, 1, "unload no-block FAILED")
		return
	var sig0 := _U.snapshot_sigs(cm)
	_ok("streamed chunks=%d" % keys.size())

	# Case 1: unload with a queued task; result must be dropped, chunk stays gone.
	var k1: Vector2i = keys[keys.size() - 1]
	_unload_with_queued_task(cm, k1, "case1")
	await _U.settle(self, cm)
	if cm.chunks.has(k1):
		_fail("case1: stale task result brought %s back" % str(k1))
	else:
		_ok("case1: stale result dropped, %s stays unloaded" % str(k1))
	_check_clean(cm, "case1")
	cm.request_chunk(k1, true)
	await _U.settle(self, cm)
	if _U.chunk_sig(cm, k1) != sig0.get(k1, ""):
		_fail("case1: reloaded %s mesh/data differs from before [%s] wave_lod=%s" % [str(k1), _U.sig_diff(sig0.get(k1, ""), _U.chunk_sig(cm, k1)), "-"])
	else:
		_ok("case1: reloaded %s matches original mesh and data" % str(k1))

	# Case 2: unload with a queued task, then request it again at once (reversal).
	var k2: Vector2i = keys[keys.size() - 2]
	_unload_with_queued_task(cm, k2, "case2")
	cm.request_chunk(k2, true)
	await _U.settle(self, cm)
	if not cm.chunks.has(k2):
		_fail("case2: %s not reloaded after reversal" % str(k2))
	elif _U.chunk_sig(cm, k2) != sig0.get(k2, ""):
		_fail("case2: %s mesh/data differs after unload+reload [%s]" % [str(k2), _U.sig_diff(sig0.get(k2, ""), _U.chunk_sig(cm, k2))])
	else:
		_ok("case2: %s reloaded with original mesh and data" % str(k2))
	_check_clean(cm, "case2")

	# Every chunk still matches the boot state.
	var diff := 0
	for k in sig0.keys():
		if cm.chunks.has(k) and _U.chunk_sig(cm, k) != sig0[k]:
			diff += 1
			print("CHANGED %s [%s]" % [str(k), _U.sig_diff(sig0[k], _U.chunk_sig(cm, k))])
	if diff > 0:
		_fail("%d chunks changed mesh/data during the test" % diff)
	else:
		_ok("all resident chunks match boot signatures")

	await _U.shutdown(self, cm)
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "All unload no-block tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "Unload no-block FAILED (%d)" % _failed)
