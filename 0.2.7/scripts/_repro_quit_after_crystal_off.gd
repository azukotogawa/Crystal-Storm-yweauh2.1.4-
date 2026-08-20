extends SceneTree
func _init():
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "safe")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	call_deferred("_go")
func _go():
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var f:=0
	while compose and not bool(compose.get("_boot_done")) and f < 3600:
		await process_frame
		f+=1
	# free crystal before quit
	var crystal = get_first_node_in_group("crystal_manager")
	if crystal:
		print("[REPRO] free crystal manager")
		if crystal.get_parent():
			crystal.get_parent().remove_child(crystal)
		crystal.free()
	await process_frame
	print("[REPRO] quit after crystal free")
	quit(0)
