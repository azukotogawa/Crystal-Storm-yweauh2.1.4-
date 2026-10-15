extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const _Coords = preload("res://helpers/world_visual_coords.gd")
const _Items = preload("res://helpers/item_types.gd")
const _Edits = preload("res://world/terrain_edits.gd")
const _Blueprints = preload("res://helpers/structure_blueprints.gd")
const _Craft = preload("res://helpers/structure_crafting.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("break structures window needs a window")
		quit(1)
		return
	var folder := OS.get_environment("CRYSTALSTORM_BREAK_STRUCTURES_DIR").strip_edges()
	if folder.is_empty():
		folder = "D:/ARCHIVE/CrystalStorm/verify-evidence/pivot-0.4/B-break-structures"
	DirAccess.make_dir_recursive_absolute(folder)
	DisplayServer.window_set_title("Crystal Storm break and structures")
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
	var player := get_first_node_in_group("player") as Node3D
	var editor = get_first_node_in_group("terrain_editor")
	var world = get_first_node_in_group("world")
	if player == null or editor == null or world == null:
		push_error("break structures window missing player, editor, or world")
		quit(1)
		return
	var inventory = player.get("inventory")
	if inventory == null or not inventory.has_method("add_item"):
		push_error("break structures window missing inventory")
		quit(1)
		return
	inventory.add_item("stone", 200)
	inventory.add_item("wood", 80)
	var origin := _player_column(player)
	if not await _break_face(folder, player, editor, world, origin):
		quit(1)
		return
	if not await _place_each(folder, player, editor, world, inventory, origin):
		quit(1)
		return
	print("BREAK STRUCTURES WINDOW OK")
	quit(0)


func _break_face(folder: String, player: Node3D, editor, world, origin: Vector2i) -> bool:
	_Items.ensure_builtins()
	var shape := _Items.break_shape_for("stone_pick", 3)
	var anchor_col := origin + Vector2i(-8, 6)
	var anchor := Vector3i(anchor_col.x, _Edits.surface_block_y(world, anchor_col.x, anchor_col.y), anchor_col.y)
	var aim := Vector3(1, 0, 0)
	var cells: Array = _Items.break_cells(shape, anchor, aim)
	var batch: Dictionary = _Edits.dig_cells(cells, editor)
	var dug := int(batch.get("dug_count", 0))
	print("BREAK_3X3 shape=%s requested=%d dug=%d anchor=%s" % [_Items.break_shape_name(shape), cells.size(), dug, anchor])
	if shape != _Items.BreakShape.FACE_3X3 or cells.size() != 9 or dug < 3:
		push_error("3x3 face break dug %d of %d" % [dug, cells.size()])
		await _shot(folder, "break-3x3-face-missing", player, world, anchor_col + Vector2i(2, 2))
		return false
	await _shot(folder, "break-3x3-face", player, world, anchor_col + Vector2i(2, 2))
	return true


func _place_each(folder: String, player: Node3D, editor, world, inventory, origin: Vector2i) -> bool:
	var spots: Array[Vector2i] = []
	for row in 5:
		for col in 6:
			spots.append(origin + Vector2i(-6 - col * 6, 8 + row * 5))
	var used := 0
	var placed: Array[Vector2i] = []
	for id in _Blueprints.ids():
		_Craft.craft(inventory, id)
		var spot := Vector2i(-99999, -99999)
		var reason := ""
		while used < spots.size():
			var try_at: Vector2i = spots[used]
			used += 1
			var pos := Vector3(float(try_at.x) + 0.5, 0.0, float(try_at.y) + 0.5)
			if editor.try_place_blueprint(pos, inventory, id, 0):
				spot = try_at
				break
			reason = str(editor.get("last_fail_reason"))
		var count := int(editor.get("last_place_batch").get("placed_count", 0)) if spot.x > -10000 else 0
		print("PLACE id=%s at=%s count=%d reason=%s" % [String(id), spot, count, reason])
		if spot.x < -10000 or count < 1:
			push_error("place failed %s %s" % [String(id), reason])
			await _shot(folder, "place-%s-missing" % String(id), player, world, origin)
			return false
		placed.append(spot)
		await _shot(folder, "place-%s" % String(id), player, world, spot + Vector2i(2, 2))
	if placed.is_empty():
		return false
	var mid: Vector2i = placed[placed.size() / 2]
	await _shot(folder, "place-all", player, world, mid + Vector2i(3, 3))
	return true


func _player_column(player: Node3D) -> Vector2i:
	if player.has_method("get_voxel_position"):
		var pv: Vector3 = player.get_voxel_position()
		return Vector2i(int(floor(pv.x)), int(floor(pv.z)))
	var vs := _Coords.voxel_scale()
	return Vector2i(int(floor(player.global_position.x / vs)), int(floor(player.global_position.z / vs)))


func _wait_stream(game: Node) -> bool:
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while frames < 3600:
		if compose != null and int(compose.stage) >= int(compose.Stage.INITIAL_STREAM_READY):
			return true
		await process_frame
		frames += 1
	push_error("break structures window stream timeout")
	return false


func _dismiss_blockers(game: Node) -> void:
	var tutorial := load("res://ui/tutorial_overlay.gd")
	if tutorial != null and tutorial.has_method("dismiss"):
		tutorial.dismiss()
	var loading := game.get_node_or_null("LoadingLayer")
	if loading != null:
		loading.visible = false


func _shot(folder: String, tag: String, player: Node3D, world, stand: Vector2i) -> bool:
	var ground := 8.0
	if world != null and world.has_method("get_surface_height"):
		ground = float(world.get_surface_height(float(stand.x) + 0.5, float(stand.y) + 0.5))
	if "voxel_position" in player:
		player.voxel_position = Vector3(float(stand.x) + 0.5, ground + 1.2, float(stand.y) + 0.5)
	if player.has_method("_sync_global_from_voxel"):
		player._sync_global_from_voxel()
	else:
		player.global_position = _Coords.column_to_world_pos(float(stand.x) + 0.5, ground + 1.2, float(stand.y) + 0.5)
	if player.has_method("_snap_to_ground"):
		player._snap_to_ground()
		if player.has_method("_sync_global_from_voxel"):
			player._sync_global_from_voxel()
	if "velocity" in player:
		player.velocity = Vector3.ZERO
	var cam = player.get("camera")
	if cam != null:
		cam.set("use_smoothing", false)
		cam.set("_scroll_lead", Vector3.ZERO)
		if cam.has_method("get_offset_from_rotation"):
			cam.set("follow_target", player.global_position)
			cam.global_position = player.global_position + cam.get_offset_from_rotation()
	for _i in 12:
		await process_frame
		if cam != null and cam.has_method("get_offset_from_rotation"):
			cam.global_position = player.global_position + cam.get_offset_from_rotation()
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("break structures shot empty %s" % tag)
		return false
	var path := "%s/%s.png" % [folder, tag]
	var err := img.save_png(path)
	if err != OK:
		push_error("break structures shot save %s %s" % [tag, str(err)])
		return false
	print("SHOT %s col=%s" % [path, _player_column(player)])
	return true
