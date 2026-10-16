extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const _Coords = preload("res://helpers/world_visual_coords.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _Edits = preload("res://world/terrain_edits.gd")
const _Features = preload("res://world/feature_registry.gd")
const _Poi = preload("res://world/poi_scatter.gd")
const _Progression = preload("res://systems/progression_service.gd")
const _Skills = preload("res://systems/skill_service.gd")
const _Pulse = preload("res://player/crystal_pulse_skill.gd")
const _Wall = preload("res://player/quick_wall_skill.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")

const ACTIVES: Array[StringName] = [&"dash", &"ground_slam", &"crystal_pulse", &"quick_wall"]
const PASSIVES: Array[StringName] = [&"fighter_passive", &"miner_passive", &"builder_passive"]


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("density skills session needs a window")
		quit(1)
		return
	var folder := OS.get_environment("CRYSTALSTORM_DENSITY_SKILLS_DIR").strip_edges()
	if folder.is_empty():
		folder = "D:/ARCHIVE/CrystalStorm/verify-evidence/pivot-0.4/D-density-skills"
	DirAccess.make_dir_recursive_absolute(folder)
	DisplayServer.window_set_title("Crystal Storm density and skills")
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
	_GameplayInput.set_world_loading(false)
	for _i in 12:
		await process_frame
	var player := get_first_node_in_group("player") as Node3D
	var world = get_first_node_in_group("world")
	var spawn := Vector2i.ZERO
	var skills = _Skills.get_active()
	var progress = _Progression.get_active()
	var crystal = get_first_node_in_group("crystal_manager")
	var gm = get_first_node_in_group("game_manager")
	if player == null or world == null or skills == null or progress == null or crystal == null or gm == null:
		push_error("density skills session missing player, world, skills, progression, crystal, or game")
		quit(1)
		return
	spawn = _player_column(player)
	if not await _level(folder, overlay, progress, player, world):
		quit(1)
		return
	if not _unlock_all(skills, progress):
		quit(1)
		return
	var tree := game.get_node_or_null("SkillTree")
	if tree != null and tree.has_method("open"):
		tree.open()
		for _i in 6:
			await process_frame
		if not await _shot(folder, "skill-tree", player, world, _player_column(player)):
			quit(1)
			return
		if tree.has_method("close"):
			tree.close()
		for _i in 4:
			await process_frame
	if not await _visit_pois(folder, player, world):
		quit(1)
		return
	if not await _visit_treasure(folder, player, world):
		quit(1)
		return
	if not await _use_skills(folder, player, world, skills, spawn):
		quit(1)
		return
	if not await _destroy_crystal(folder, player, world, crystal, gm):
		quit(1)
		return
	print("DENSITY SKILLS WINDOW OK")
	quit(0)


func _level(folder: String, overlay, progress, player: Node3D, world) -> bool:
	progress.add_xp(70)
	for _i in 8:
		await process_frame
	var toast: Label = null
	if overlay != null:
		toast = overlay.get_node_or_null("ToastLabel") as Label
	if int(progress.level) != 2 or int(progress.xp) != 20:
		push_error("level-up landed at %d / %d" % [int(progress.level), int(progress.xp)])
		return false
	if toast == null or toast.text != "Level up — 2":
		push_error("level-up toast missed (%s)" % (toast.text if toast else "missing"))
		return false
	print("LEVEL level=%d xp=%d toast=%s" % [int(progress.level), int(progress.xp), toast.text])
	if not await _shot(folder, "level-up", player, world, _player_column(player)):
		return false
	progress.add_xp(3100)
	for _i in 4:
		await process_frame
	print("LEVEL after grant level=%d xp=%d points=%d" % [int(progress.level), int(progress.xp), int(progress.skill_points)])
	if int(progress.skill_points) < ACTIVES.size() + PASSIVES.size():
		push_error("not enough skill points %d" % int(progress.skill_points))
		return false
	return true


func _unlock_all(skills, progress) -> bool:
	for id in ACTIVES:
		if not skills.unlock(id):
			push_error("unlock failed %s points=%d" % [id, int(progress.skill_points)])
			return false
	for id in PASSIVES:
		if not skills.unlock(id):
			push_error("unlock failed %s" % id)
			return false
	if not skills.equip(0, &"dash") or not skills.equip(1, &"ground_slam") or not skills.equip(2, &"crystal_pulse"):
		push_error("equip failed")
		return false
	print("SKILLS unlocked actives=%s passives=%s" % [ACTIVES, PASSIVES])
	return true


func _visit_pois(folder: String, player: Node3D, world) -> bool:
	var origin := _player_column(player)
	var seen := {}
	var spots: Array = _Poi.scatter(int(world.world_seed))
	spots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca: Vector2i = a.get("center", Vector2i.ZERO)
		var cb: Vector2i = b.get("center", Vector2i.ZERO)
		return Vector2(ca).distance_squared_to(Vector2(origin)) < Vector2(cb).distance_squared_to(Vector2(origin))
	)
	for spot_v in spots:
		var spot: Dictionary = spot_v
		var kind := str(spot.get("poi_kind", ""))
		if seen.has(kind):
			continue
		var center: Vector2i = spot.get("center", Vector2i.ZERO)
		if _Features.get_feature(center.x, center.y).is_empty():
			_Poi.install([spot])
		var feat: Dictionary = _Features.get_feature(center.x, center.y)
		if str(feat.get("poi_kind", "")) != kind:
			continue
		var visuals = get_first_node_in_group("feature_visual_layer")
		if visuals != null and visuals.has_method("refresh_cell"):
			visuals.refresh_cell(center.x, center.y)
		await _stand_and_stream(player, world, center)
		print("POI kind=%s center=%s name=%s" % [kind, center, str(feat.get("name", ""))])
		if not await _shot(folder, "poi-%s" % kind.replace("_", "-"), player, world, center):
			return false
		seen[kind] = center
		if seen.size() >= _Poi.KINDS.size():
			break
	if seen.size() < _Poi.KINDS.size():
		push_error("visited %d poi kinds" % seen.size())
		return false
	return true


func _visit_treasure(folder: String, player: Node3D, world) -> bool:
	var origin := _player_column(player)
	var centers: Array = _Features.get_ruin_centers()
	if centers.is_empty():
		push_error("no treasure sites")
		return false
	var best: Vector2i = centers[0]
	var best_d := Vector2(best).distance_squared_to(Vector2(origin))
	for center_v in centers:
		var center: Vector2i = center_v
		var dist := Vector2(center).distance_squared_to(Vector2(origin))
		if dist < best_d:
			best = center
			best_d = dist
	await _stand_and_stream(player, world, best)
	var director = get_first_node_in_group("living_world_director")
	var found: Dictionary = {}
	if director != null and director.has_method("discover_ruin_at"):
		found = director.discover_ruin_at(best)
	var feat: Dictionary = _Features.get_feature(best.x, best.y)
	var site_name := str(found.get("name", feat.get("name", "")))
	print("TREASURE center=%s name=%s lore=%s loot=%s already=%s" % [
		best,
		site_name,
		str(found.get("lore", feat.get("lore", ""))),
		found.get("loot", {}),
		str(found.is_empty()),
	])
	if not bool(feat.get("treasure_site", false)):
		push_error("ruin at %s is not a treasure site" % best)
		return false
	if site_name.is_empty():
		push_error("treasure discover returned empty at %s" % best)
		return false
	return await _shot(folder, "treasure-site", player, world, best)


func _use_skills(folder: String, player: Node3D, world, skills, home: Vector2i) -> bool:
	var stand := home + Vector2i(8, 2)
	await _stand_and_stream(player, world, stand)
	for _i in 8:
		await process_frame
	var before := _player_column(player)
	if not skills.try_activate(0):
		push_error("dash did not activate")
		return false
	for _i in 45:
		await process_frame
	var after := _player_column(player)
	var moved := Vector2(after).distance_to(Vector2(before))
	print("SKILL dash from=%s to=%s moved=%.2f cd=%.2f" % [before, after, moved, skills.cooldown_left(0)])
	if moved < 1.0:
		push_error("dash did not move")
		await _shot(folder, "skill-dash-missing", player, world, after)
		return false
	if not await _shot(folder, "skill-dash", player, world, after):
		return false
	stand = after + Vector2i(3, 0)
	await _stand_and_stream(player, world, stand)
	for _i in 6:
		await process_frame
	stand = _player_column(player)
	var dig_before: float = _Edits.get_height_delta(stand.x, stand.y)
	if not skills.try_activate(1):
		push_error("ground slam did not activate")
		return false
	for _i in 36:
		await process_frame
	var dig_after: float = _Edits.get_height_delta(stand.x, stand.y)
	print("SKILL ground_slam col=%s delta %.3f -> %.3f" % [stand, dig_before, dig_after])
	if dig_after >= dig_before - 0.01:
		push_error("ground slam did not dig")
		await _shot(folder, "skill-slam-missing", player, world, stand)
		return false
	if not await _shot(folder, "skill-ground-slam", player, world, stand):
		return false
	if not skills.try_activate(2):
		push_error("crystal pulse did not activate")
		return false
	for _i in 30:
		await process_frame
	var zones: int = _Pulse._zones.size()
	print("SKILL crystal_pulse zones=%d cd=%.2f" % [zones, skills.cooldown_left(2)])
	if zones < 1:
		push_error("crystal pulse armed no zone")
		return false
	if not await _shot(folder, "skill-crystal-pulse", player, world, _player_column(player)):
		return false
	skills.clear_slot(2)
	if not skills.equip(2, &"quick_wall"):
		push_error("could not equip quick wall")
		return false
	var inventory = player.get("inventory")
	if inventory == null or not inventory.has_method("add_item"):
		push_error("inventory missing")
		return false
	inventory.add_item(_Wall.material_id(), 80)
	inventory.add_item("wood", 80)
	var wall_stand := home + Vector2i(-8, 4)
	await _stand_and_stream(player, world, wall_stand)
	for _i in 6:
		await process_frame
	var feet := _player_column(player)
	if not skills.try_activate(2):
		push_error("quick wall did not activate")
		return false
	for _i in 30:
		await process_frame
	var placed := _wall_near(feet)
	var editor = get_first_node_in_group("terrain_editor")
	var why := ""
	if editor != null:
		why = str(editor.get("last_fail_reason"))
	print("SKILL quick_wall feet=%s placed=%s cd=%.2f fail=%s" % [feet, placed, skills.cooldown_left(2), why])
	if placed == Vector2i(-99999, -99999):
		push_error("quick wall left no structure")
		await _shot(folder, "skill-wall-missing", player, world, feet)
		return false
	return await _shot(folder, "skill-quick-wall", player, world, placed)


func _wall_near(feet: Vector2i) -> Vector2i:
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var col := feet + Vector2i(dx, dz)
			var feat: Dictionary = _Features.get_feature(col.x, col.y)
			var built := str(feat.get("build_id", ""))
			if built == "wall_segment" or built == "stone_wall":
				return col
	return Vector2i(-99999, -99999)


func _destroy_crystal(folder: String, player: Node3D, world, crystal, gm) -> bool:
	var spawns: Array = crystal.get_active_spawns()
	if spawns.size() != 1:
		push_error("expected 1 crystal, got %d" % spawns.size())
		return false
	var spawn = spawns[0]
	var cell: Vector2i = spawn.world_pos
	await _stand_and_stream(player, world, cell + Vector2i(6, 4))
	for _i in 20:
		await process_frame
	var line: float = float(spawn.max_health) * 0.25
	var above: float = float(spawn.health) - (line + 1.0)
	if above > 0.0:
		crystal.damage_spawn_at_world(cell, above, 2.5)
	if float(spawn.health) <= line:
		push_error("setup chip crossed 25%% hp=%.1f" % float(spawn.health))
		return false
	crystal.damage_spawn_at_world(cell, float(spawn.health) - line, 2.5)
	for _j in 45:
		await process_frame
	var bosses := get_nodes_in_group("origin_boss")
	print("CRYSTAL boss=%d hp=%.1f cell=%s" % [bosses.size(), float(spawn.health), cell])
	if bosses.size() != 1:
		push_error("boss missing at 25%%")
		await _shot(folder, "crystal-boss-missing", player, world, cell)
		return false
	if not await _shot(folder, "crystal-boss", player, world, cell):
		return false
	crystal.damage_spawn_at_world(cell, float(spawn.health) + 5.0, 2.5)
	for _k in 40:
		await process_frame
	var won := int(gm.run_state) == int(gm.RunState.WON) and str(gm.victory_reason) == "crystal"
	print("CRYSTAL victory=%s reason=%s" % [str(won), str(gm.victory_reason)])
	if not won:
		push_error("crystal destruction did not win")
		await _shot(folder, "crystal-destroyed-missing", player, world, cell)
		return false
	return await _shot(folder, "crystal-destroyed", player, world, cell)


func _player_column(player: Node3D) -> Vector2i:
	if player != null and "voxel_position" in player:
		var pv: Vector3 = player.voxel_position
		return Vector2i(int(floor(pv.x)), int(floor(pv.z)))
	return Vector2i.ZERO


func _stand_and_stream(player: Node3D, world, stand: Vector2i) -> void:
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
	var chunk_manager = player.get("chunk_manager")
	if chunk_manager != null and chunk_manager.has_method("request_chunk"):
		var size := float(_ChunkData.SIZE)
		for col in [stand, stand + Vector2i(8, 0), stand + Vector2i(-8, 0), stand + Vector2i(0, 8), stand + Vector2i(0, -8)]:
			chunk_manager.request_chunk(Vector2i(floori(float(col.x) / size), floori(float(col.y) / size)), true)
	for _i in 12:
		await process_frame


func _wait_stream(game: Node) -> bool:
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while frames < 3600:
		if compose != null and int(compose.stage) >= int(compose.Stage.INITIAL_STREAM_READY):
			return true
		await process_frame
		frames += 1
	push_error("density skills session stream timeout")
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
		await _stand_and_stream(player, world, stand)
		var cam = player.get("camera")
		if cam != null:
			cam.set("use_smoothing", false)
			cam.set("_scroll_lead", Vector3.ZERO)
			if cam.has_method("get_offset_from_rotation"):
				cam.set("follow_target", player.global_position)
				cam.global_position = player.global_position + cam.get_offset_from_rotation()
		for _i in 8:
			await process_frame
			if cam != null and cam.has_method("get_offset_from_rotation"):
				cam.global_position = player.global_position + cam.get_offset_from_rotation()
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("density skills shot empty %s" % tag)
		return false
	var path := "%s/%s.png" % [folder, tag]
	var err := img.save_png(path)
	if err != OK:
		push_error("density skills shot save %s %s" % [tag, str(err)])
		return false
	print("SHOT %s" % path)
	return true
