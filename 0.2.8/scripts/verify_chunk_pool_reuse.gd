extends SceneTree
## Headless: stream unload must return ChunkData to pool (pool_reuse > 0 after churn).


const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _ChunkDataPool = preload("res://helpers/chunk_data_pool.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	_ChunkDataPool.reset_stats()
	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		_ProbeExit.finish_tree(self, 1, "chunk pool reuse FAILED")
		return

	var game: Node = main_packed.instantiate()
	root.add_child(game)

	var player: Node = null
	var chunk_manager: ChunkManager = null
	for _attempt in 900:
		player = get_first_node_in_group("player")
		chunk_manager = get_first_node_in_group("chunk_manager")
		if (
			player != null and chunk_manager != null
			and bool(player.get("world_ready"))
			and chunk_manager.chunks.size() >= 5
		):
			break
		await process_frame

	if chunk_manager == null or player == null:
		_ProbeExit.finish_tree(self, 1, "chunk pool reuse FAILED")
		return

	for _w in 60:
		await process_frame

	var stats_before: Dictionary = _ChunkDataPool.get_stats()
	var start_chunk := chunk_manager.get_player_chunk_coord()
	_ChunkDataPool.reset_stats()

	# Walk east long enough to cross several chunk columns (unload + reload).
	Input.action_press("ui_right")
	var end_ms := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < end_ms:
		await process_frame
	Input.action_release("ui_right")

	for _idle in 120:
		await process_frame
	if chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle()

	var stats_after: Dictionary = _ChunkDataPool.get_stats()
	var end_chunk := chunk_manager.get_player_chunk_coord()
	var crossed: int = absi(end_chunk.x - start_chunk.x) + absi(end_chunk.y - start_chunk.y)
	var pool_reuse: int = int(stats_after.get("alloc_reuse", 0))
	var pool_release: int = int(stats_after.get("release_count", 0))
	var alloc_new: int = int(stats_after.get("alloc_new", 0))

	print(
		"OK pool churn crossed=%d release=%d new=%d reuse=%d pool_size=%d"
		% [crossed, pool_release, alloc_new, pool_reuse, int(stats_after.get("pool_size", 0))]
	)

	if crossed < 2:
		push_error("insufficient chunk crossing for pool test")
		_ProbeExit.finish_tree(self, 1, "chunk pool reuse FAILED")
		return
	if pool_release < 1:
		push_error("expected pool release after unload")
		_ProbeExit.finish_tree(self, 1, "chunk pool reuse FAILED")
		return
	if pool_reuse < 1:
		push_error("expected pool_reuse after reload")
		_ProbeExit.finish_tree(self, 1, "chunk pool reuse FAILED")
		return

	_ProbeExit.finish_tree(self, 0, "chunk pool reuse OK")