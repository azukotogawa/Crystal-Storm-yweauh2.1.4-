extends SceneTree
## Repro window-close teardown: boot main, then free scene like WM close.
func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_SHUTDOWN_TRACE", "1")
	call_deferred("_run")

func _run() -> void:
	var packed = load("res://scenes/main.tscn") as PackedScene
	var game = packed.instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var f := 0
	while compose and not bool(compose.get("_boot_done")) and f < 3600:
		await process_frame
		f += 1
	for _i in 60:
		await process_frame
	print("[REPRO] boot done, simulating window close")
	# Mimic editor/game close: request quit via SceneTree
	if compose and compose.has_method("shutdown"):
		print("[REPRO] composition shutdown")
		compose.shutdown()
	await process_frame
	print("[REPRO] queue_free game")
	game.queue_free()
	await process_frame
	await process_frame
	print("[REPRO] SceneTree.quit")
	quit(0)
