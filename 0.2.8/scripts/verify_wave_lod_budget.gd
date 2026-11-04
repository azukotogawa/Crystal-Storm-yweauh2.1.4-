extends SceneTree
## Wave-LOD ring changes must not rebuild every changed chunk in one frame:
## rebuilds go through the rebuild queue at a per-frame cap, chunks about to
## unload are skipped, and every changed chunk still ends with the right mesh.

const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _U = preload("res://scripts/stream_test_util.gd")
const DEFAULT_CAP := 2

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


func _tokens(cm: Node) -> Dictionary:
	var out := {}
	for k in cm.chunks.keys():
		out[k] = int(cm._chunk_gen_tokens.get(k, 0))
	return out


func _bumped(cm: Node, before: Dictionary) -> Array:
	var out: Array = []
	for k in before.keys():
		if int(cm._chunk_gen_tokens.get(k, 0)) != int(before[k]):
			out.append(k)
	return out


func _changed_ring(cm: Node, a: Vector2i, b: Vector2i) -> Array:
	var r: int = ChunkSurfaceMeshBuilder.WAVE_LOD_R
	var out: Array = []
	for k: Vector2i in cm.chunks.keys():
		var na: bool = maxi(absi(k.x - a.x), absi(k.y - a.y)) <= r
		var nb: bool = maxi(absi(k.x - b.x), absi(k.y - b.y)) <= r
		if na != nb:
			out.append(k)
	return out


func _run() -> void:
	var cm = await _U.boot(self)
	if cm == null:
		_fail("chunk_manager missing")
		_ProbeExit.finish_tree(self, 1, "wave LOD budget FAILED")
		return
	if await _U.settle(self, cm) < 0:
		_fail("world did not settle after boot")
	cm.set_stream_paused(true)
	var cap_v = cm.get("max_wave_lod_rebuilds_per_frame")
	var cap: int = int(cap_v) if cap_v != null else DEFAULT_CAP
	if cap_v == null:
		_fail("manager has no max_wave_lod_rebuilds_per_frame")
	var c: Vector2i = ChunkSurfaceMeshBuilder.wave_lod_center
	if not ChunkSurfaceMeshBuilder.wave_lod_on:
		cm._wave_lod_recheck(c)
		await _U.settle(self, cm)
	var ref := _U.snapshot_sigs(cm)
	var c2 := c + Vector2i(1, 0)
	var changed := _changed_ring(cm, c, c2)
	print("WAVE_LOD c=%s changed=%d cap=%d" % [str(c), changed.size(), cap])
	if changed.size() <= cap:
		_fail("test needs more changed chunks than the cap (%d)" % changed.size())

	# Pick one changed chunk and mark it as about to unload.
	var doomed: Vector2i = changed[changed.size() - 1]
	cm._stream_unload_pending.append(doomed)
	var t0 := _tokens(cm)
	var tm := Time.get_ticks_usec()
	cm._wave_lod_recheck(c2)
	var recheck_ms := float(Time.get_ticks_usec() - tm) / 1000.0
	var now: Array = _bumped(cm, t0)
	print("WAVE_LOD recheck_ms=%.2f immediate=%d" % [recheck_ms, now.size()])
	if now.size() > cap:
		_fail("recheck rebuilt %d chunks at once (cap %d)" % [now.size(), cap])
	else:
		_ok("recheck rebuilt %d now (cap %d)" % [now.size(), cap])

	var seen := {}
	for k in now:
		seen[k] = true
	var frames := 0
	var over := 0
	while frames < 600:
		var before := _tokens(cm)
		await process_frame
		frames += 1
		var b := _bumped(cm, before)
		if b.size() > cap:
			over += 1
		for k in b:
			seen[k] = true
		var rp: Dictionary = cm.get("_rebuild_pending") if cm.get("_rebuild_pending") is Dictionary else {}
		if rp.size() <= 1 and seen.size() >= changed.size() - 1:
			break
	if over > 0:
		_fail("%d frames rebuilt more than the cap" % over)
	else:
		_ok("no frame rebuilt more than %d" % cap)
	if seen.has(doomed):
		_fail("chunk %s pending unload was rebuilt" % str(doomed))
	else:
		_ok("chunk pending unload was skipped")
	var missed := 0
	for k in changed:
		if k != doomed and not seen.has(k):
			missed += 1
	if missed > 0:
		_fail("%d changed chunks never rebuilt" % missed)
	else:
		_ok("all %d changed chunks rebuilt" % (changed.size() - 1))

	# Let the doomed chunk unload, then return to c: meshes match the start.
	cm._stream_unload_pending.erase(doomed)
	cm._unload_chunk_view(doomed)
	var rp2 = cm.get("_rebuild_pending")
	if rp2 is Dictionary and (rp2 as Dictionary).has(doomed):
		_fail("unloaded chunk left in rebuild queue")
	await _U.settle(self, cm)
	cm._wave_lod_recheck(c)
	# Loads drain only while streaming runs; resume it at c for the return.
	cm.set_stream_paused(false)
	cm.request_chunk(doomed, true)
	if await _U.settle(self, cm) < 0:
		_fail("did not settle after return")
	var diff := 0
	for k in ref.keys():
		if _U.chunk_sig(cm, k) != ref[k]:
			diff += 1
			if diff <= 5:
				_fail("chunk %s differs after LOD round trip [%s]" % [str(k), _U.sig_diff(ref[k], _U.chunk_sig(cm, k))])
	if diff == 0:
		_ok("all %d chunks match after LOD round trip" % ref.size())
	for b in _U.view_problems(cm):
		_fail(b)

	cm.set_stream_paused(false)
	await _U.shutdown(self, cm)
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "All wave LOD budget tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "Wave LOD budget FAILED (%d)" % _failed)
