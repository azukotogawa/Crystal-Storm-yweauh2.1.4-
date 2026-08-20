extends SceneTree
## Headless: ChunkView pool reuses the same instance across put/get (shipped ChunkManager path).
## Does not free+recreate when pool is non-empty.

const _ProbeExit = preload("res://scripts/probe_exit.gd")
const CHUNK_VIEW_SCENE = preload("res://scenes/ChunkView.tscn")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var cm_script: GDScript = load("res://chunks/chunk_manager.gd") as GDScript
	if cm_script == null:
		push_error("missing chunk_manager.gd")
		_ProbeExit.finish_tree(self, 1, "chunk view pool FAILED")
		return
	var cm: Node = cm_script.new()
	if cm == null:
		push_error("failed to construct ChunkManager")
		_ProbeExit.finish_tree(self, 1, "chunk view pool FAILED")
		return
	root.add_child(cm)

	# Acquire fresh view (empty pool → instantiate path).
	if not cm.has_method("_acquire_chunk_view") or not cm.has_method("_try_pool_chunk_view"):
		push_error("ChunkManager missing pool methods")
		_ProbeExit.finish_tree(self, 1, "chunk view pool FAILED")
		return

	var v1: Node = cm.call("_acquire_chunk_view")
	if v1 == null or not is_instance_valid(v1):
		push_error("acquire returned null")
		_ProbeExit.finish_tree(self, 1, "chunk view pool FAILED")
		return
	var id1: int = v1.get_instance_id()

	# Detach-style put (view not in tree).
	var put_ok: bool = bool(cm.call("_try_pool_chunk_view", v1))
	if not put_ok:
		push_error("pool put failed")
		_ProbeExit.finish_tree(self, 1, "chunk view pool FAILED")
		return
	var pool_size: int = int(cm.get("_view_pool").size()) if "_view_pool" in cm else -1
	if pool_size != 1:
		push_error("expected pool size 1 after put, got %d" % pool_size)
		_ProbeExit.finish_tree(self, 1, "chunk view pool FAILED")
		return

	# Acquire again must return same instance (reuse).
	var v2: Node = cm.call("_acquire_chunk_view")
	if v2 == null or not is_instance_valid(v2):
		push_error("second acquire null")
		_ProbeExit.finish_tree(self, 1, "chunk view pool FAILED")
		return
	var id2: int = v2.get_instance_id()
	if id1 != id2:
		push_error("pool did not reuse view: %d vs %d" % [id1, id2])
		_ProbeExit.finish_tree(self, 1, "chunk view pool FAILED")
		return
	pool_size = int(cm.get("_view_pool").size()) if "_view_pool" in cm else -1
	if pool_size != 0:
		push_error("expected empty pool after get, got %d" % pool_size)
		_ProbeExit.finish_tree(self, 1, "chunk view pool FAILED")
		return

	# Put back and clear on teardown path.
	cm.call("_try_pool_chunk_view", v2)
	if cm.has_method("_clear_view_pool"):
		cm.call("_clear_view_pool")
	pool_size = int(cm.get("_view_pool").size()) if "_view_pool" in cm else -1
	if pool_size != 0:
		push_error("clear left pool size %d" % pool_size)
		_ProbeExit.finish_tree(self, 1, "chunk view pool FAILED")
		return

	print("OK chunk_view_pool reuse id=%d put_get_clear" % id1)
	cm.queue_free()
	_ProbeExit.finish_tree(self, 0, "chunk view pool OK")
