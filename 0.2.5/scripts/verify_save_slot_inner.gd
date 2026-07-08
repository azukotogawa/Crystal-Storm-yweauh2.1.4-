extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const TEST_SLOT := 7


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	call_deferred("_run")


func _run() -> void:
	var ok := await _exercise_slot_roundtrip()
	if ok:
		print("SAVE SLOT OK in-game roundtrip")
	quit(0 if ok else 1)


func _exercise_slot_roundtrip() -> bool:
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		push_error("failed to load main scene")
		return false

	var game: Node = packed.instantiate()
	root.add_child(game)

	var terrain: TerrainEditor = null
	var chunk_manager: ChunkManager = null
	var world: InfiniteNoiseWorld = null
	var save_svc: SaveGameService = null
	for _attempt in 600:
		terrain = get_first_node_in_group("terrain_editor")
		chunk_manager = get_first_node_in_group("chunk_manager")
		world = get_first_node_in_group("world")
		save_svc = get_first_node_in_group("save_game_service") as SaveGameService
		if terrain != null and chunk_manager != null and world != null and save_svc != null and terrain.chunk_manager != null:
			break
		await process_frame

	if terrain == null or chunk_manager == null or world == null or save_svc == null:
		push_error("boot timeout for save slot test")
		game.queue_free()
		return false

	if save_svc.config:
		save_svc.config.auto_save_enabled = false

	var col := Vector2i(3, 5)
	var before_h: float = world.get_surface_height(float(col.x), float(col.y))
	if not terrain.try_dig(Vector3(float(col.x) + 0.5, 0.0, float(col.y) + 0.5)):
		push_error("try_dig failed at %s" % col)
		game.queue_free()
		return false
	if chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle()
	for _w in 60:
		await process_frame

	var after_h: float = world.get_surface_height(float(col.x), float(col.y))
	if after_h >= before_h - 0.01:
		push_error("dig did not lower surface before=%.2f after=%.2f" % [before_h, after_h])
		game.queue_free()
		return false

	if save_svc.save_slot(TEST_SLOT) != OK:
		push_error("save_slot failed")
		game.queue_free()
		return false

	game.queue_free()
	for _w in 30:
		await process_frame

	game = packed.instantiate()
	root.add_child(game)
	save_svc = null
	chunk_manager = null
	world = null
	for _attempt in 600:
		save_svc = get_first_node_in_group("save_game_service") as SaveGameService
		chunk_manager = get_first_node_in_group("chunk_manager")
		world = get_first_node_in_group("world")
		if save_svc != null and chunk_manager != null and world != null:
			break
		await process_frame

	if save_svc == null or chunk_manager == null or world == null:
		push_error("reload boot timeout")
		game.queue_free()
		return false

	if save_svc.config:
		save_svc.config.auto_save_enabled = false

	var loaded: bool = await save_svc.load_slot(TEST_SLOT)
	if not loaded:
		push_error("load_slot failed")
		game.queue_free()
		return false
	if chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle()
	for _w in 90:
		await process_frame

	var y_loaded: float = world.get_surface_height(float(col.x), float(col.y))
	var delta: float = y_loaded - after_h
	if absf(delta) > 0.51:
		push_error("surface mismatch after load y=%.2f expected=%.2f delta=%.2f" % [y_loaded, after_h, delta])
		game.queue_free()
		return false

	print("SAVE SLOT OK in-game roundtrip delta=%.2f" % delta)
	var cm_end: ChunkManager = get_first_node_in_group("chunk_manager")
	if cm_end and cm_end.has_method("shutdown_workers"):
		cm_end.shutdown_workers()
	if game:
		game.free()
	for _w in 180:
		await process_frame
	return true