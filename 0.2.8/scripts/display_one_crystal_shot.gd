extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const _Coords = preload("res://helpers/world_visual_coords.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("one crystal shot needs a window")
		quit(1)
		return
	var folder := OS.get_environment("CRYSTALSTORM_ONE_CRYSTAL_DIR").strip_edges()
	if folder.is_empty():
		folder = "D:/ARCHIVE/CrystalStorm/verify-evidence/pivot-0.4/A-one-crystal-loss"
	DirAccess.make_dir_recursive_absolute(folder)
	DisplayServer.window_set_title("Crystal Storm one crystal")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		push_error("main missing")
		quit(1)
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	if not await _wait_stream(game):
		quit(1)
		return
	_dismiss_blockers(game)
	var crystal := get_first_node_in_group("crystal_manager")
	var player := get_first_node_in_group("player")
	var gm := get_first_node_in_group("game_manager")
	if crystal == null or player == null or gm == null:
		push_error("one crystal shot missing crystal, player, or game")
		quit(1)
		return
	var spawns: Array = crystal.get_active_spawns()
	if spawns.size() != 1:
		push_error("one crystal shot expected 1 spawn, got %d" % spawns.size())
		quit(1)
		return
	var spawn = spawns[0]
	var cell: Vector2i = spawn.world_pos
	_stand_near(player, cell)
	for _i in 90:
		await process_frame
	var line: float = float(spawn.max_health) * 0.25
	var above: float = spawn.health - (line + 1.0)
	if above > 0.0:
		crystal.damage_spawn_at_world(cell, above, 2.5)
	if float(spawn.health) <= line:
		push_error("setup chip crossed 25%% hp=%.1f" % float(spawn.health))
		quit(1)
		return
	crystal.damage_spawn_at_world(cell, float(spawn.health) - line, 2.5)
	for _j in 45:
		await process_frame
	var bosses := get_nodes_in_group("origin_boss")
	var ratio := float(spawn.health) / maxf(float(spawn.max_health), 1.0)
	print("ONE_CRYSTAL_WINDOW boss=%d ratio=%.3f hp=%.1f cell=%s" % [bosses.size(), ratio, float(spawn.health), cell])
	if bosses.size() != 1:
		push_error("boss missing at 25%%")
		await _save_shot(folder, "crystal-25-boss-missing")
		quit(1)
		return
	if not await _save_shot(folder, "crystal-25-boss"):
		quit(1)
		return
	crystal.damage_spawn_at_world(cell, float(spawn.health) + 5.0, 2.5)
	for _k in 60:
		await process_frame
	var won := int(gm.run_state) == int(gm.RunState.WON) and str(gm.victory_reason) == "crystal"
	print("ONE_CRYSTAL_WINDOW victory=%s phase=%s reason=%s" % [str(won), str(gm.phase), str(gm.victory_reason)])
	if not won:
		push_error("crystal destruction did not win")
		await _save_shot(folder, "crystal-destroyed-missing")
		quit(1)
		return
	if not await _save_shot(folder, "crystal-destroyed-victory"):
		quit(1)
		return
	print("ONE CRYSTAL WINDOW OK")
	quit(0)


func _wait_stream(game: Node) -> bool:
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while frames < 3600:
		if compose != null and int(compose.stage) >= int(compose.Stage.INITIAL_STREAM_READY):
			return true
		await process_frame
		frames += 1
	push_error("one crystal shot stream timeout")
	return false


func _dismiss_blockers(game: Node) -> void:
	var tutorial := load("res://ui/tutorial_overlay.gd")
	if tutorial != null and tutorial.has_method("dismiss"):
		tutorial.dismiss()
	var loading := game.get_node_or_null("LoadingLayer")
	if loading != null:
		loading.visible = false


func _stand_near(player: Node3D, cell: Vector2i) -> void:
	var inward := Vector2i(6 if cell.x < 0 else -6, 4 if cell.y < 0 else -4)
	var stand := cell + inward
	var world = player.get("world")
	var ground := 8.0
	if world != null and world.has_method("get_surface_height"):
		ground = float(world.get_surface_height(float(stand.x) + 0.5, float(stand.y) + 0.5))
	player.global_position = _Coords.column_to_world_pos(float(stand.x) + 0.5, ground + 1.2, float(stand.y) + 0.5)
	if "velocity" in player:
		player.velocity = Vector3.ZERO
	var chunk_manager = player.get("chunk_manager")
	if chunk_manager != null and chunk_manager.has_method("request_chunk"):
		var size := float(_ChunkData.SIZE)
		for col in [cell, stand, cell + Vector2i(2, 0), cell + Vector2i(-2, 0)]:
			chunk_manager.request_chunk(Vector2i(floori(float(col.x) / size), floori(float(col.y) / size)), true)


func _save_shot(folder: String, tag: String) -> bool:
	for _i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("one crystal shot empty %s" % tag)
		return false
	var path := "%s/%s.png" % [folder, tag]
	var err := img.save_png(path)
	if err != OK:
		push_error("one crystal shot save %s %s" % [tag, str(err)])
		return false
	print("ONE_CRYSTAL_SHOT=%s" % path)
	return true
