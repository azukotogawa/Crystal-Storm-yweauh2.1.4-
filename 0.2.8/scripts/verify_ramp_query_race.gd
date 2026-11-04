extends SceneTree
## Main-thread ramp queries (player floor probe, targeting) read a chunk's
## ramp_map while a worker rebuild of the same chunk clears and replaces it.
## Hammers get_ramp_entry_at_world on ramp columns during rebuilds; answers
## must match the settled answers and nothing may crash.

const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _U = preload("res://scripts/stream_test_util.gd")
const ITER := 80
const HAMMER := 300

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


func _cols(cm: Node) -> Dictionary:
	var out := {}
	for k in cm.chunks.keys():
		var v = cm.chunks[k]
		if v == null or v.chunk_data == null:
			continue
		var list: Array = []
		for key in v.chunk_data.ramp_map.keys():
			list.append(Vector2(k.x * ChunkData.SIZE + key.x + 0.5, k.y * ChunkData.SIZE + key.y + 0.5))
		if not list.is_empty():
			out[k] = list
	return out


func _answers(cm: Node, cols: Dictionary) -> Dictionary:
	var out := {}
	for k in cols.keys():
		for p in cols[k]:
			out[p] = str(cm.get_ramp_entry_at_world(p.x, p.y))
	return out


func _run() -> void:
	var cm = await _U.boot(self)
	if cm == null:
		_fail("chunk_manager missing")
		_ProbeExit.finish_tree(self, 1, "ramp query race FAILED")
		return
	if await _U.settle(self, cm) < 0:
		_fail("world did not settle after boot")
	var cols := _cols(cm)
	var keys: Array = cols.keys()
	keys.sort()
	var ref := _answers(cm, cols)
	print("RAMP_COLS chunks=%d cols=%d" % [keys.size(), ref.size()])
	if keys.is_empty():
		_fail("no resident chunk has ramps")
		_ProbeExit.finish_tree(self, 1, "ramp query race FAILED")
		return
	var queries := 0
	var during := 0
	var wrong := 0
	for it in ITER:
		var k: Vector2i = keys[it % keys.size()]
		cm.rebuild_chunk(k)
		for _h in HAMMER:
			if not cm._chunk_tasks.has(k):
				break
			during += 1
			for p in cols[k]:
				var e := str(cm.get_ramp_entry_at_world(p.x, p.y))
				queries += 1
				if e != ref[p]:
					wrong += 1
		await process_frame
	print("RAMP_RACE iters=%d hammer_rounds=%d queries=%d answers_differing=%d" % [ITER, during, queries, wrong])
	if during == 0:
		_fail("no queries ran while a rebuild job was running")
	if wrong > 0:
		_fail("%d ramp answers differed from the settled answer during rebuilds" % wrong)
	else:
		_ok("ramp answers during rebuilds match settled answers")
	if await _U.settle(self, cm) < 0:
		_fail("did not settle after stress")
	var after := _answers(cm, cols)
	var diff := 0
	for p in ref.keys():
		if after[p] != ref[p]:
			diff += 1
	if diff > 0:
		_fail("%d ramp answers differ after stress" % diff)
	else:
		_ok("ramp answers identical after stress (%d cols)" % ref.size())
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "All ramp query race tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "ramp query race FAILED (%d)" % _failed)
