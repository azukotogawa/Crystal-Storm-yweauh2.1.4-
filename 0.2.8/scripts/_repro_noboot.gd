extends SceneTree
func _init():
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "safe")
	call_deferred("_go")
func _go():
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	print("[REPRO] free unbooted scene")
	game.free()
	await process_frame
	print("[REPRO] quit")
	quit(0)
