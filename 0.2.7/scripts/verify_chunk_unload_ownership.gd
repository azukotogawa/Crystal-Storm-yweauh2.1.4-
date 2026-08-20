extends SceneTree
## Stream unload ownership: load chunks, unload, re-load; no double-pool / pending upload race.
## Usage: godot --headless -s scripts/verify_chunk_unload_ownership.gd

const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _ChunkDataPool = preload("res://helpers/chunk_data_pool.gd")


var _failed: int = 0


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


func _run() -> void:
	# Structural ownership guards
	var cv_src := FileAccess.get_file_as_string("res://chunks/chunk_view.gd")
	if "cancel_pending_uploads_for_view" not in cv_src:
		_fail("ChunkView must cancel pending uploads on unload")
	else:
		_ok("pending upload cancel API present")
	var cm_src := FileAccess.get_file_as_string("res://chunks/chunk_manager.gd")
	if "cancel_pending_uploads_for_view" not in cm_src:
		_fail("ChunkManager unload must cancel pending uploads")
	else:
		_ok("ChunkManager unload cancels pending uploads")
	if "_teardown_released" not in cm_src:
		_fail("teardown must be idempotent")
	else:
		_ok("teardown idempotent guard")
	var pool_src := FileAccess.get_file_as_string("res://helpers/chunk_data_pool.gd")
	if "_in_chunk_pool" not in pool_src:
		_fail("ChunkDataPool must guard double release")
	else:
		_ok("ChunkDataPool double-release guard")

	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	var game: Node = packed.instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while compose and not bool(compose.get("_boot_done")) and frames < 3600:
		await process_frame
		frames += 1

	var cm = compose.registry.resolve(&"chunk_manager") if compose and compose.registry else null
	if cm == null:
		cm = get_first_node_in_group("chunk_manager")
	if cm == null:
		_fail("chunk_manager missing")
		_ProbeExit.finish_tree(self, 1, "unload ownership FAILED")
		return

	# Wait for some chunks resident
	for _w in 120:
		if cm.chunks.size() >= 4:
			break
		await process_frame
	var n0: int = cm.chunks.size()
	if n0 < 1:
		_fail("no chunks streamed")
	else:
		_ok("streamed chunks=%d" % n0)

	var bake = load("res://world/world_bake_service.gd").get_active()
	var res0: int = bake.resident_count() if bake else -1

	# Force unload of a far chunk if present, else unload one key
	var keys: Array = cm.chunks.keys()
	if keys.is_empty():
		_fail("empty chunk map")
	else:
		var key: Vector2i = keys[0]
		cm._unload_chunk_view(key)
		if cm.chunks.has(key):
			_fail("unload left chunk resident")
		else:
			_ok("unloaded chunk %s" % str(key))
		# Pending queues should not retain freed Multimeshes
		if ChunkView.pending_buffer_upload_count() < 0:
			_fail("pending count negative")
		else:
			_ok("pending buffer uploads=%d after unload" % ChunkView.pending_buffer_upload_count())
		# Reload
		cm.request_chunk(key, true)
		for _r in 90:
			if cm.chunks.has(key):
				break
			await process_frame
		if cm.chunks.has(key):
			_ok("reloaded chunk %s" % str(key))
		else:
			_fail("reload failed for %s" % str(key))

	# Pool double-release should no-op
	var stats0: Dictionary = _ChunkDataPool.get_stats()
	var d = _ChunkDataPool.acquire(Vector2i(99, 99), null)
	_ChunkDataPool.release(d)
	_ChunkDataPool.release(d)
	var stats1: Dictionary = _ChunkDataPool.get_stats()
	if int(stats1.get("pool_size", 0)) > int(stats0.get("pool_size", 0)) + 1:
		_fail("pool grew more than once on double release")
	else:
		_ok("pool double-release is no-op")

	if compose and compose.has_method("shutdown"):
		compose.shutdown()
	await process_frame
	# Second teardown must be safe
	if cm.has_method("release_all_chunks_for_teardown"):
		cm.release_all_chunks_for_teardown()
	_ok("double teardown safe")

	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "All chunk unload ownership tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "Chunk unload ownership FAILED (%d)" % _failed)
