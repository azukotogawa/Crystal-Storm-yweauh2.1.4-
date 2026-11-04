extends SceneTree
## Near props must not read a chunk's data while a worker mesh job on that chunk
## is running. Builds of near props are hammered against concurrent rebuilds of
## the same chunks. Prop placement must be the same before and after.

const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _U = preload("res://scripts/stream_test_util.gd")
const ITER := 60
const PER_ITER := 4
const HAMMER := 400

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


func _prop_sig(np: Node, data) -> int:
	var mi = np._build(data)
	var h := 0
	if mi != null:
		var mm: MultiMesh = mi.multimesh
		var pos := PackedVector3Array()
		var col := PackedColorArray()
		for i in mm.instance_count:
			pos.append(mm.get_instance_transform(i).origin)
			col.append(mm.get_instance_color(i))
		h = hash([mm.instance_count, var_to_bytes(pos), var_to_bytes(col)])
		mi.get_parent().remove_child(mi)
		mi.free()
	return h


func _prop_sigs(cm: Node, np: Node) -> Dictionary:
	var out := {}
	for k in cm.chunks.keys():
		var v = cm.chunks[k]
		if v != null and v.chunk_data != null and not cm._chunk_tasks.has(k):
			out[k] = _prop_sig(np, v.chunk_data)
	return out


func _total(sigs: Dictionary) -> int:
	var keys: Array = sigs.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append([k, sigs[k]])
	return hash(parts)


func _near_keys(cm: Node, np: Node) -> Array:
	var out: Array = []
	for k in cm.chunks.keys():
		if not np._far(k):
			out.append(k)
	out.sort()
	return out


func _run() -> void:
	var cm = await _U.boot(self)
	if cm == null or cm.player == null:
		_fail("chunk_manager or player missing")
		_ProbeExit.finish_tree(self, 1, "near props race FAILED")
		return
	if await _U.settle(self, cm) < 0:
		_fail("world did not settle after boot")
	var c0: Vector2i = cm.get_player_chunk_coord()
	if cm._near_props == null:
		cm._update_near_props(c0)
	var np = cm._near_props
	for _i in 30:
		await process_frame
	var ref_chunks := _U.snapshot_sigs(cm)
	var ref_props := _prop_sigs(cm, np)
	var near: Array = _near_keys(cm, np)
	var placed := 0
	for k in ref_props.keys():
		if ref_props[k] != 0:
			placed += 1
	print("PROP_SIG total=%d chunks=%d with_props=%d near=%d" % [_total(ref_props), ref_props.size(), placed, near.size()])
	if near.is_empty():
		_fail("no near chunks resident")
		_ProbeExit.finish_tree(self, 1, "near props race FAILED")
		return

	# 1. Contract: a chunk with a mesh job running is not built, then is built
	#    once the job ends, with the same placement.
	var k0: Vector2i = near[0]
	var sleepers := _U.saturate_pool(Callable(self, "_sleep").bind(200))
	cm.rebuild_chunk(k0)
	if not cm._chunk_tasks.has(k0):
		_fail("rebuild of %s did not start a mesh task" % str(k0))
	np.drop_chunk(k0)
	np._queue.erase(k0)
	np._queue.push_front(k0)
	np._process(0.0)
	if np._built.has(k0):
		_fail("near props built %s while its mesh job was running" % str(k0))
	else:
		_ok("near props deferred %s while its mesh job was running" % str(k0))
	_U.wait_all(sleepers)
	if await _U.settle(self, cm) < 0:
		_fail("did not settle after contract rebuild")
	for _i in 60:
		if np._built.has(k0):
			break
		await process_frame
	if not np._built.has(k0):
		_fail("near props never built %s after its job ended" % str(k0))
	else:
		_ok("near props built %s after its job ended" % str(k0))

	# 2. Stress: rebuild near chunks and hammer near prop builds while jobs run.
	var during := 0
	var t0 := Time.get_ticks_msec()
	for it in ITER:
		var batch: Array = []
		for j in PER_ITER:
			batch.append(near[(it * PER_ITER + j) % near.size()])
		for k in batch:
			cm.rebuild_chunk(k)
		for _h in HAMMER:
			var running := false
			for k in batch:
				if cm._chunk_tasks.has(k):
					running = true
					np.drop_chunk(k)
					np._queue.erase(k)
					np._queue.push_front(k)
					np._process(0.0)
					if np._built.has(k):
						during += 1
			if not running:
				break
		await process_frame
	print("RACE iters=%d builds_during_job=%d ms=%d" % [ITER, during, Time.get_ticks_msec() - t0])
	if during > 0:
		_fail("near props built %d times while a mesh job was running" % during)
	else:
		_ok("no near prop builds while a mesh job was running")

	# 3. Fast reversal flight with near props active.
	var c1 := c0
	var best := -1
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: int = _U.needed_set(cm, c0 + d * 2).size()
		if n > best:
			best = n
			c1 = c0 + d * 2
	for i in 8:
		var s2 := _U.saturate_pool(Callable(self, "_sleep").bind(40))
		for _f in 2:
			_U.set_player_chunk(cm, c1 if i % 2 == 0 else c0)
			await process_frame
		_U.wait_all(s2)
	for _f in 2:
		_U.set_player_chunk(cm, c0)
		await process_frame
	if await _U.settle(self, cm) < 0:
		_fail("did not settle after flight")
	for _i in 60:
		await process_frame

	# 4. Same chunk meshes and same prop placement as before.
	var diff := 0
	for k in ref_chunks.keys():
		if cm.chunks.has(k) and _U.chunk_sig(cm, k) != ref_chunks[k]:
			diff += 1
			if diff <= 5:
				_fail("chunk %s mesh/data differs after stress" % str(k))
	if diff == 0:
		_ok("chunk meshes match after stress")
	var after := _prop_sigs(cm, np)
	var pdiff := 0
	for k in ref_props.keys():
		if after.has(k) and after[k] != ref_props[k]:
			pdiff += 1
			if pdiff <= 5:
				_fail("prop placement differs for %s" % str(k))
	print("PROP_SIG_AFTER total=%d" % _total(after))
	if pdiff == 0:
		_ok("prop placement identical for %d chunks" % ref_props.size())
	var bad := _U.view_problems(cm)
	for b in bad:
		_fail(b)
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "All near props race tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "near props race FAILED (%d)" % _failed)
