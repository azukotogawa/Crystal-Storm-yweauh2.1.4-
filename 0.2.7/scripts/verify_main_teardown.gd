extends SceneTree
## Regression: production main scene teardown must not abort with double-free.


const MAIN := "res://scenes/main.tscn"


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load(MAIN) as PackedScene
	if packed == null:
		push_error("could not load main scene")
		quit(1)
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	for _i in 180:
		await process_frame
	var cm: ChunkManager = get_first_node_in_group("chunk_manager")
	if cm and cm.has_method("release_all_chunks_for_teardown"):
		cm.release_all_chunks_for_teardown()
	for _i in 60:
		await process_frame
	if game.get_parent() == root:
		root.remove_child(game)
	game.queue_free()
	for _i in 120:
		await process_frame
	print("OK main teardown clean")
	quit(0)