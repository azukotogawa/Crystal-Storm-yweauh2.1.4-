extends SceneTree
## Binary-search which subsystem leaves a double-free on quit.
## Usage: CRYSTALSTORM_ISOLATE=A|B|C|... godot --headless -s scripts/_repro_isolate_quit.gd

func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "safe")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	call_deferred("_go")


func _go() -> void:
	var mode := OS.get_environment("CRYSTALSTORM_ISOLATE")
	if mode.is_empty():
		mode = "FULL"
	print("[ISOLATE] mode=", mode)

	match mode:
		"EMPTY":
			print("[ISOLATE] empty quit")
			quit(0)
			return
		"AUTOLOADS_ONLY":
			# Just boot with autoloads, no main scene
			print("[ISOLATE] autoloads only (PerfProfiler etc present)")
			for _i in 30:
				await process_frame
			print("[ISOLATE] quit")
			quit(0)
			return
		"MAIN_NO_BOOT":
			var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
			# Remove CompositionRoot so boot never runs
			var cr = game.get_node_or_null("CompositionRoot")
			if cr:
				game.remove_child(cr)
				cr.free()
			root.add_child(game)
			for _i in 45:
				await process_frame
			print("[ISOLATE] main without boot quit")
			quit(0)
			return
		"MAIN_BOOT":
			await _boot_main_and_quit(false, false, false)
		"NO_PLAYER":
			await _boot_main_and_quit(true, false, false)
		"NO_CRYSTAL":
			await _boot_main_and_quit(false, true, false)
		"NO_VISUALS":
			await _boot_main_and_quit(false, false, true)
		"STRIP_CHUNKS_THEN_QUIT":
			await _boot_main_and_quit(false, false, false, true)
		"CHUNKS_ONLY":
			await _chunks_only()
		"MATERIALS_ONLY":
			await _materials_only()
		_:
			print("[ISOLATE] unknown mode ", mode)
			quit(1)


func _boot_main_and_quit(kill_player: bool, kill_crystal: bool, kill_visuals: bool, release_chunks: bool = false) -> void:
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	if kill_player:
		var p = game.get_node_or_null("Player")
		if p:
			game.remove_child(p)
			p.free()
	if kill_crystal:
		var c = game.get_node_or_null("CrystalManager")
		if c:
			game.remove_child(c)
			c.free()
	if kill_visuals:
		var v = game.get_node_or_null("WorldVisuals")
		if v:
			game.remove_child(v)
			v.free()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var f := 0
	while compose and not bool(compose.get("_boot_done")) and f < 3600:
		await process_frame
		f += 1
	for _i in 60:
		await process_frame
	if release_chunks:
		var cm = get_first_node_in_group("chunk_manager")
		if cm and cm.has_method("release_all_chunks_for_teardown"):
			print("[ISOLATE] release_all chunks=", cm.chunks.size())
			cm.release_all_chunks_for_teardown()
			await process_frame
			await process_frame
	print("[ISOLATE] quit after boot player_killed=", kill_player, " crystal_killed=", kill_crystal, " visuals_killed=", kill_visuals, " released=", release_chunks)
	quit(0)


func _chunks_only() -> void:
	## Minimal: Config + World + ChunkManager stream only, no player/crystal/visuals.
	var root3d := Node3D.new()
	root3d.name = "IsolateRoot"
	root.add_child(root3d)

	var cfg = load("res://systems/config_service.gd").new()
	cfg.name = "ConfigService"
	root3d.add_child(cfg)
	if cfg.has_method("apply_defaults"):
		cfg.apply_defaults()

	var world = load("res://world/infinite_noise_world.gd").new() if ResourceLoader.exists("res://world/infinite_noise_world.gd") else null
	if world == null:
		# try class path
		world = (load("res://world/InfiniteNoiseWorld.gd") as GDScript).new()
	world.name = "World"
	root3d.add_child(world)

	var cm = (load("res://chunks/chunk_manager.gd") as GDScript).new()
	cm.name = "ChunkManager"
	root3d.add_child(cm)
	cm.add_to_group("chunk_manager")
	if cm.has_method("configure"):
		cm.configure(world, cfg)
	elif "world" in cm:
		cm.world = world

	# force a few chunks
	for _i in 90:
		await process_frame
		if cm.has_method("update_player_position"):
			cm.update_player_position(Vector3.ZERO)
		elif cm.has_method("set_focus"):
			cm.set_focus(Vector3.ZERO)

	print("[ISOLATE] chunks_only views=", cm.chunks.size() if "chunks" in cm else -1)
	print("[ISOLATE] quit chunks_only")
	quit(0)


func _materials_only() -> void:
	## Touch ChunkView static shared materials/meshes then quit.
	var root3d := Node3D.new()
	root.add_child(root3d)
	var view_script: GDScript = load("res://chunks/chunk_view.gd")
	var view: Node3D = view_script.new()
	view.name = "ChunkViewProbe"
	# Need LayerContainer child as scene expects
	var lc := Node3D.new()
	lc.name = "LayerContainer"
	view.add_child(lc)
	root3d.add_child(view)
	if view.has_method("_ensure_chunk_material"):
		view._ensure_chunk_material()
	# Create a MultiMesh using shared material path if possible
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = 1
	mmi.multimesh = mm
	lc.add_child(mmi)
	for _i in 20:
		await process_frame
	print("[ISOLATE] materials_only quit")
	quit(0)
