extends SceneTree
func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "safe")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	call_deferred("_go")
func _dump(n: Node, ind: String="") -> void:
	print(ind, n.name, " [", n.get_class(), "] id=", n.get_instance_id())
	for c in n.get_children():
		_dump(c, ind+"  ")
func _go() -> void:
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var f:=0
	while compose and not bool(compose.get("_boot_done")) and f < 3600:
		await process_frame
		f+=1
	for _i in 30:
		await process_frame
	var cmg = get_first_node_in_group("chunk_manager")
	if cmg and cmg.has_method("release_all_chunks_for_teardown"):
		cmg.release_all_chunks_for_teardown()
	await process_frame
	print("[REPRO] TREE BEFORE STRIP:")
	_dump(game)
	# free all children of game
	while game.get_child_count() > 0:
		var c = game.get_child(0)
		print("[REPRO] free child ", c.name)
		game.remove_child(c)
		c.free()
		await process_frame
	print("[REPRO] game children left=", game.get_child_count())
	print("[REPRO] root children:")
	for c in root.get_children():
		print("  ", c.name, " ", c.get_class())
	# free game itself
	if game.get_parent():
		game.get_parent().remove_child(game)
	game.free()
	await process_frame
	print("[REPRO] quit empty root")
	quit(0)
