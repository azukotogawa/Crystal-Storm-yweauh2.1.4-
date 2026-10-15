extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const _Coords = preload("res://helpers/world_visual_coords.gd")
const _Edits = preload("res://world/terrain_edits.gd")
const _Progression = preload("res://systems/progression_service.gd")
const _Features = preload("res://world/feature_registry.gd")
const SLOT := 36


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("xp macro session needs a window")
		quit(1)
		return
	var folder := OS.get_environment("CRYSTALSTORM_XP_MACRO_DIR").strip_edges()
	if folder.is_empty():
		folder = "D:/ARCHIVE/CrystalStorm/verify-evidence/pivot-0.4/C-xp-macro-micro"
	DirAccess.make_dir_recursive_absolute(folder)
	DisplayServer.window_set_title("Crystal Storm XP macro session")
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
	var overlay := get_first_node_in_group("game_overlay")
	if overlay and overlay.has_method("notify_loading_finished"):
		overlay.notify_loading_finished()
	for _i in 12:
		await process_frame
	var player := get_first_node_in_group("player") as Node3D
	var editor = get_first_node_in_group("terrain_editor")
	var world = get_first_node_in_group("world")
	var save_svc = get_first_node_in_group("save_game_service")
	var svc = _Progression.get_active()
	if svc == null:
		svc = get_first_node_in_group("progression_service")
	if player == null or editor == null or world == null or save_svc == null or svc == null:
		push_error("xp macro session missing player, editor, world, save, or progression")
		quit(1)
		return
	if save_svc.config:
		save_svc.config.auto_save_enabled = false
	if not await _level_up(folder, overlay, svc):
		quit(1)
		return
	var origin := _player_column(player)
	var dig_col := await _dig_near(folder, player, editor, world, origin)
	if dig_col.x < -10000:
		quit(1)
		return
	var inventory = player.get("inventory")
	if inventory == null or not inventory.has_method("add_item"):
		push_error("xp macro session missing inventory")
		quit(1)
		return
	inventory.add_item("stone", 80)
	var build_col := await _build_near(folder, player, editor, world, inventory, origin, dig_col)
	if build_col.x < -10000:
		quit(1)
		return
	var scratch_col := dig_col + Vector2i(3, 0)
	var dig_before: float = _Edits.get_height_delta(dig_col.x, dig_col.y)
	var build_before := _feature_id(build_col)
	var level_before: int = int(svc.level)
	var xp_before: int = int(svc.xp)
	if save_svc.save_slot(SLOT) != OK:
		push_error("save slot %d failed" % SLOT)
		quit(1)
		return
	print("SAVE slot=%d level=%d xp=%d dig=%s delta=%.3f build=%s id=%s" % [
		SLOT, level_before, xp_before, dig_col, dig_before, build_col, build_before
	])
	svc.level = 9
	svc.xp = 3
	svc.skill_points = 0
	var scratch_h: float = _Edits.get_height_delta(scratch_col.x, scratch_col.y)
	_stand(player, world, scratch_col)
	for _i in 4:
		await process_frame
	if not editor.try_dig(Vector3(float(scratch_col.x) + 0.5, 0.0, float(scratch_col.y) + 0.5)):
		push_error("scratch dig failed %s" % str(editor.get("last_fail_reason")))
		quit(1)
		return
	var loaded: bool = await save_svc.load_slot(SLOT)
	for _i in 20:
		await process_frame
	var dig_after: float = _Edits.get_height_delta(dig_col.x, dig_col.y)
	var scratch_after: float = _Edits.get_height_delta(scratch_col.x, scratch_col.y)
	var build_after := _feature_id(build_col)
	print("RELOAD ok=%s level=%d xp=%d points=%d dig=%.3f scratch=%.3f->%.3f build=%s" % [
		loaded, int(svc.level), int(svc.xp), int(svc.skill_points), dig_after, scratch_h, scratch_after, build_after
	])
	if not loaded or int(svc.level) != level_before or int(svc.xp) != xp_before:
		push_error("reload missed progression")
		await _shot(folder, "reload-missing", player, world, dig_col)
		quit(1)
		return
	if dig_after > -0.01 or absf(dig_after - dig_before) > 0.05:
		push_error("reload missed dig %.3f expected %.3f" % [dig_after, dig_before])
		await _shot(folder, "reload-missing", player, world, dig_col)
		quit(1)
		return
	if absf(scratch_after - scratch_h) > 0.05:
		push_error("reload kept the scratch dig %.3f -> %.3f" % [scratch_h, scratch_after])
		await _shot(folder, "reload-missing", player, world, scratch_col)
		quit(1)
		return
	if build_after != build_before or build_after.is_empty():
		push_error("reload missed build %s -> %s" % [build_before, build_after])
		await _shot(folder, "reload-missing", player, world, build_col)
		quit(1)
		return
	if not await _shot(folder, "reload", player, world, dig_col):
		quit(1)
		return
	print("C XP MACRO WINDOW OK")
	quit(0)


func _level_up(folder: String, overlay, svc) -> bool:
	if not svc.has_method("add_xp"):
		push_error("progression has no add_xp")
		return false
	svc.add_xp(70)
	for _i in 8:
		await process_frame
	var toast: Label = null
	var level_label: Label = null
	var value_label: Label = null
	if overlay != null:
		toast = overlay.get_node_or_null("ToastLabel") as Label
		level_label = overlay.get_node_or_null("XpBar/Row/XpLevel") as Label
		value_label = overlay.get_node_or_null("XpBar/Row/XpValue") as Label
	if int(svc.level) != 2 or int(svc.xp) != 20:
		push_error("level-up landed at %d / %d" % [int(svc.level), int(svc.xp)])
		return false
	if toast == null or toast.text != "Level up — 2" or level_label == null or level_label.text != "Lv 2":
		push_error("level-up toast missed (%s)" % (toast.text if toast else "missing"))
		return false
	if value_label == null or value_label.text != "20 / %d" % _Progression.xp_to_advance(2):
		push_error("xp bar value is %s" % (value_label.text if value_label else "missing"))
		return false
	print("LEVEL level=%d xp=%d toast=%s" % [int(svc.level), int(svc.xp), toast.text])
	var player := get_first_node_in_group("player") as Node3D
	var world = get_first_node_in_group("world")
	return await _shot(folder, "level-up", player, world, _player_column(player))


func _dig_near(folder: String, player: Node3D, editor, world, origin: Vector2i) -> Vector2i:
	var offsets: Array[Vector2i] = [
		Vector2i(4, 2), Vector2i(5, 2), Vector2i(4, 4), Vector2i(6, -2), Vector2i(-6, 4),
	]
	for offset in offsets:
		var col: Vector2i = origin + offset
		if await _dig(folder, player, editor, world, col):
			return col
	return Vector2i(-99999, -99999)


func _build_near(folder: String, player: Node3D, editor, world, inventory, origin: Vector2i, dig_col: Vector2i) -> Vector2i:
	var offsets: Array[Vector2i] = [
		Vector2i(-4, 2), Vector2i(-5, 3), Vector2i(-6, 1), Vector2i(2, -5), Vector2i(-3, -4),
	]
	for offset in offsets:
		var col: Vector2i = origin + offset
		if col == dig_col:
			continue
		if await _build(folder, player, editor, world, inventory, col):
			return col
	return Vector2i(-99999, -99999)


func _dig(folder: String, player: Node3D, editor, world, col: Vector2i) -> bool:
	var before: float = _Edits.get_height_delta(col.x, col.y)
	_stand(player, world, col)
	for _i in 4:
		await process_frame
	var pos := Vector3(float(col.x) + 0.5, 0.0, float(col.y) + 0.5)
	if not editor.try_dig(pos):
		push_error("dig failed %s at %s" % [str(editor.get("last_fail_reason")), col])
		await _shot(folder, "dig-missing", player, world, col)
		return false
	var after: float = _Edits.get_height_delta(col.x, col.y)
	print("DIG col=%s delta %.3f -> %.3f" % [col, before, after])
	if after >= before - 0.01:
		push_error("dig did not lower %s" % col)
		await _shot(folder, "dig-missing", player, world, col)
		return false
	return await _shot(folder, "dig", player, world, col)


func _build(folder: String, player: Node3D, editor, world, inventory, col: Vector2i) -> bool:
	_stand(player, world, col)
	for _i in 4:
		await process_frame
	var pos := Vector3(float(col.x) + 0.5, 0.0, float(col.y) + 0.5)
	if not editor.try_build_wall(pos, inventory, true):
		push_error("build failed %s at %s" % [str(editor.get("last_fail_reason")), col])
		await _shot(folder, "build-missing", player, world, col)
		return false
	var built := _feature_id(col)
	print("BUILD col=%s id=%s" % [col, built])
	if built.is_empty():
		push_error("build left no feature at %s" % col)
		await _shot(folder, "build-missing", player, world, col)
		return false
	return await _shot(folder, "build", player, world, col)


func _feature_id(col: Vector2i) -> String:
	var feat: Dictionary = _Features.get_feature(col.x, col.y)
	return str(feat.get("build_id", "")).strip_edges()


func _player_column(player: Node3D) -> Vector2i:
	if player != null and player.has_method("get_voxel_position"):
		var pv: Vector3 = player.get_voxel_position()
		return Vector2i(int(floor(pv.x)), int(floor(pv.z)))
	if player == null:
		return Vector2i.ZERO
	var vs := _Coords.voxel_scale()
	return Vector2i(int(floor(player.global_position.x / vs)), int(floor(player.global_position.z / vs)))


func _stand(player: Node3D, world, stand: Vector2i) -> void:
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


func _wait_stream(game: Node) -> bool:
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while frames < 3600:
		if compose != null and int(compose.stage) >= int(compose.Stage.INITIAL_STREAM_READY):
			return true
		await process_frame
		frames += 1
	push_error("xp macro session stream timeout")
	return false


func _dismiss_blockers(game: Node) -> void:
	var tutorial := load("res://ui/tutorial_overlay.gd")
	if tutorial != null and tutorial.has_method("dismiss"):
		tutorial.dismiss()
	var loading := game.get_node_or_null("LoadingLayer")
	if loading != null:
		loading.visible = false


func _shot(folder: String, tag: String, player: Node3D, world, stand: Vector2i) -> bool:
	if player != null:
		_stand(player, world, stand)
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
	else:
		for _i in 4:
			await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("xp macro shot empty %s" % tag)
		return false
	var path := "%s/%s.png" % [folder, tag]
	var err := img.save_png(path)
	if err != OK:
		push_error("xp macro shot save %s %s" % [tag, str(err)])
		return false
	print("SHOT %s" % path)
	return true
