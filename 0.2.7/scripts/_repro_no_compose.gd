extends SceneTree
func _init():
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "safe")
	call_deferred("_go")
func _go():
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var cr = game.get_node_or_null("CompositionRoot")
	if cr: cr.queue_free()
	root.add_child(game)
	await process_frame
	await process_frame
	print("[REPRO] quit with main scene no composition boot")
	quit(0)
