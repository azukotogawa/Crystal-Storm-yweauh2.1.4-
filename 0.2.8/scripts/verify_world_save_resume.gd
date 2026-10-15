extends SceneTree

const _WorldState = preload("res://world/world_state.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _SaveGameService = preload("res://systems/save_game_service.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _WorldManager = preload("res://systems/world_manager.gd")
const _Inventory = preload("res://inventory/inventory.gd")
const _Player = preload("res://player/player.gd")

const WORLD_ID := "verify_resume_tmp"


var _failed: int = 0


class StubPlayer extends Node:
	var voxel_position := Vector3(12.0, 4.0, 8.0)
	var health := 80.0
	var world_ready := true
	var apply_count := 0
	var inventory = _Inventory.new()

	func _enter_tree() -> void:
		add_to_group("player")

	func export_save_state() -> Dictionary:
		return {
			"voxel_position": [voxel_position.x, voxel_position.y, voxel_position.z],
			"health": health,
			"inventory": inventory.to_dict(),
		}

	func apply_save_state(data: Dictionary) -> void:
		apply_count += 1
		var pos: Array = data.get("voxel_position", [0.0, 0.0, 0.0])
		voxel_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		health = float(data.get("health", health))
		if data.has("inventory"):
			inventory.load_from_dict(data.inventory)


class StubEntities extends Node:
	var imported: Array = []

	func _enter_tree() -> void:
		add_to_group("entity_manager")

	func export_entities() -> Array:
		return [{
			"brain_id": "rabbit",
			"health": 4.0,
			"world_pos": [3, 5],
			"x": 3.5,
			"y": 2.0,
			"z": 5.5,
		}]

	func import_entities(rows: Array) -> void:
		imported = rows.duplicate(true)


class StubEnemies extends Node:
	var imported: Array = []

	func _enter_tree() -> void:
		add_to_group("crystal_enemy_spawner")

	func export_enemies() -> Array:
		return [{"enemy_id": "crystal_mite", "health": 6.0, "x": 1.0, "y": 2.0, "z": 3.0}]

	func import_enemies(rows: Array) -> void:
		imported = rows.duplicate(true)


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	_WorldState.replace_active()
	_TerrainEdits.reset()
	_FeatureRegistry.reset()

	var svc: Node = _SaveGameService.new()
	root.add_child(svc)
	await process_frame
	if svc.config:
		svc.config.auto_save_enabled = false

	var player := StubPlayer.new()
	root.add_child(player)
	await process_frame

	_TerrainEdits.dig(7, 8, 2)
	_TerrainEdits.build_wall(9, 9, _VoxelTypes.STONE)
	_FeatureRegistry.register_feature(4, 4, _WorldFeatureTypes.FeatureKind.NONE, {
		"build_id": "stone_wall",
		"visual_id": "stone_wall",
		"player_built": true,
		"raises_terrain": true,
	})
	player.voxel_position = Vector3(18.0, 6.0, 3.0)
	player.health = 64.0

	var height_before: float = _TerrainEdits.get_height_delta(7, 8)
	var path := _SaveGameService.world_save_path(WORLD_ID)
	if not path.begins_with("user://saves/world_"):
		_fail("world_save_path format")
	if svc.save_world_id(WORLD_ID, true) != OK:
		_fail("save_world_id failed")
		_cleanup(svc, player, path)
		return
	if not _SaveGameService.has_world_save(WORLD_ID):
		_fail("has_world_save false after save")
	var snap: Dictionary = svc.collect_snapshot()
	if str(snap.get("world_id", "")) != WORLD_ID and not FileAccess.file_exists(path):
		_fail("world file missing")

	_WorldManager.active_world_id = WORLD_ID
	_WorldManager.pending_resume = _SaveGameService.has_world_save(WORLD_ID)
	if not _WorldManager.pending_resume:
		_fail("pending_resume should be true when world save exists")

	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	player.voxel_position = Vector3.ZERO
	player.health = 1.0
	if is_equal_approx(_TerrainEdits.get_height_delta(7, 8), height_before):
		_fail("reset should clear dig before load")

	var loaded: bool = await svc.load_world_id(WORLD_ID)
	if not loaded:
		_fail("load_world_id failed")
	else:
		if is_equal_approx(_TerrainEdits.get_height_delta(7, 8), 0.0):
			_fail("dig height not restored")
		if _TerrainEdits.get_build_tile(9, 9) != _VoxelTypes.STONE:
			_fail("build_tile not restored")
		var feat: Dictionary = _FeatureRegistry.get_feature(4, 4)
		if feat.is_empty() or str(feat.get("build_id", "")) != "stone_wall":
			_fail("player-built feature not restored")
		if not is_equal_approx(player.voxel_position.x, 18.0) or not is_equal_approx(player.health, 64.0):
			_fail("player blob not restored pos=%s hp=%.1f" % [player.voxel_position, player.health])
		else:
			print("OK world save/load overlays + player")

	_assert_quit_hooks()
	_assert_real_player_and_entity_blobs()
	var entities := StubEntities.new()
	root.add_child(entities)
	var enemies := StubEnemies.new()
	root.add_child(enemies)
	await process_frame
	player.health = 55.0
	player.voxel_position = Vector3(18.0, 6.0, 3.0)
	player.inventory.set_slot(0, "stone", 12)
	player.inventory.set_slot(10, "wood", 4)
	player.inventory.armor_id = "scout_leather"
	_FeatureRegistry.set_tile_override(2, 3, _VoxelTypes.STONE)
	svc.save_or_drop_continue()
	if not _SaveGameService.has_continue():
		_fail("save_or_drop_continue failed to write an alive session")
	else:
		var meta: Dictionary = _SaveGameService.peek_continue()
		if meta.is_empty():
			_fail("peek_continue empty after alive save")
		elif str(meta.get("world_id", "")) != WORLD_ID:
			_fail("continue world_id mismatch %s" % str(meta.get("world_id", "")))
		elif not is_equal_approx(float(meta.get("health", 0.0)), 55.0):
			_fail("continue health mismatch")
		elif not _SaveGameService.has_continue():
			_fail("has_continue false after alive save")
		else:
			print("OK continue file after alive quit")
		var raw = JSON.parse_string(FileAccess.get_file_as_string(_SaveGameService.continue_save_path()))
		if raw is Dictionary:
			var blob: Dictionary = raw
			var player_blob: Dictionary = blob.get("player", {})
			var pos: Array = player_blob.get("voxel_position", [])
			if pos.size() < 3 or not is_equal_approx(float(pos[0]), 18.0):
				_fail("continue player position missing")
			var inv: Dictionary = player_blob.get("inventory", {})
			var slots: Array = inv.get("slots", [])
			if slots.size() < 11 or str(slots[0].get("id", "")) != "stone" or int(slots[0].get("count", 0)) != 12:
				_fail("continue hotbar stack missing")
			elif slots[1] != null:
				_fail("empty inventory slots must stay empty")
			elif str(slots[10].get("id", "")) != "wood" or int(slots[10].get("count", 0)) != 4:
				_fail("continue bag stack missing")
			elif str(inv.get("armor", "")) != "scout_leather":
				_fail("continue armor missing")
			var ws_blob: Variant = blob.get("world_state", {})
			if not ws_blob is Dictionary:
				_fail("continue world_state missing")
			else:
				var ws_dict: Dictionary = ws_blob
				var heights: Dictionary = ws_dict.get("height_delta", {})
				var builds: Dictionary = ws_dict.get("build_tile", {})
				var tiles: Dictionary = ws_dict.get("tile_overrides", {})
				var feats: Dictionary = ws_dict.get("feature_cells", {})
				if heights.is_empty() or not heights.has("7,8"):
					_fail("continue world_state missing dig edits")
				if int(round(float(builds.get("9,9", -1)))) != _VoxelTypes.STONE:
					_fail("continue world_state missing placed block")
				if int(round(float(tiles.get("2,3", -1)))) != _VoxelTypes.STONE:
					_fail("continue world_state missing tile override")
				var wall: Variant = feats.get("4,4", {})
				if not wall is Dictionary or str((wall as Dictionary).get("build_id", "")) != "stone_wall":
					_fail("continue world_state missing built feature")
			var ent_rows: Variant = blob.get("entities", null)
			if not ent_rows is Array or (ent_rows as Array).is_empty():
				_fail("continue file missing entities")
			else:
				var ent: Dictionary = (ent_rows as Array)[0]
				if str(ent.get("brain_id", "")) != "rabbit" or not is_equal_approx(float(ent.get("health", 0.0)), 4.0):
					_fail("continue entity health missing")
				elif not is_equal_approx(float(ent.get("x", 0.0)), 3.5) or not is_equal_approx(float(ent.get("z", 0.0)), 5.5):
					_fail("continue entity position missing")
			var foe_rows: Variant = blob.get("crystal_enemies", null)
			if not foe_rows is Array or (foe_rows as Array).is_empty():
				_fail("continue file missing crystal enemies")
			else:
				var foe: Dictionary = (foe_rows as Array)[0]
				if str(foe.get("enemy_id", "")) != "crystal_mite" or not is_equal_approx(float(foe.get("health", 0.0)), 6.0):
					_fail("continue crystal enemy missing")
		else:
			_fail("continue file did not parse")

	await _assert_menu_continue_loads(svc, player, entities, enemies)

	player.health = 0.0
	svc.save_or_drop_continue()
	if not _SaveGameService.peek_continue().is_empty():
		_fail("dead quit must drop continue")
	else:
		print("OK dead quit drops continue")
	var closed_script: GDScript = load("res://ui/frontend_root.gd") as GDScript
	var closed: Control = closed_script.new()
	root.add_child(closed)
	await process_frame
	var closed_b := closed.find_child("Continue", true, false) as Button
	if closed_b == null or not closed_b.disabled:
		_fail("Continue must be disabled when the alive snapshot is gone")
	elif bool(closed.call("arm_continue_launch")):
		_fail("arm_continue_launch must reject a missing snapshot")
	else:
		print("OK Continue disabled without a snapshot")
	closed.queue_free()

	_WorldManager.request_return_to_select()
	if _WorldManager.active_world_id != "" or _WorldManager.pending_resume:
		_fail("request_return_to_select must clear active_world_id/pending_resume")
	else:
		print("OK return_to_select clears resume flags")
	_WorldManager.return_to_select = false

	_cleanup(svc, player, path)
	if _failed == 0:
		print("All world save resume tests OK")
		quit(0)
	else:
		push_error("verify_world_save_resume: %d failure(s)" % _failed)
		quit(1)


func _slot_is(slot: Variant, item_id: String, count: int) -> bool:
	if not slot is Dictionary:
		return false
	var row: Dictionary = slot
	return str(row.get("id", "")) == item_id and int(row.get("count", 0)) == count


func _assert_menu_continue_loads(svc: Node, player, entities, enemies) -> void:
	var frontend_script: GDScript = load("res://ui/frontend_root.gd") as GDScript
	if frontend_script == null:
		_fail("frontend_root missing")
		return
	var menu: Control = frontend_script.new()
	root.add_child(menu)
	await process_frame
	var continue_b := menu.find_child("Continue", true, false) as Button
	var play_b := menu.find_child("Play", true, false) as Button
	if continue_b == null or play_b == null:
		_fail("main menu missing Continue or Play")
	elif continue_b.disabled:
		_fail("Continue must be enabled when an alive snapshot exists")
	elif continue_b.get_index() > play_b.get_index():
		_fail("Continue must sit above Play")
	elif not bool(menu.call("arm_continue_launch")):
		_fail("arm_continue_launch rejected a valid snapshot")
	elif not _SaveGameService.pending_continue or _WorldManager.pending_resume:
		_fail("Continue must arm the snapshot and skip the world file")
	else:
		var launch: Dictionary = _WorldManager.pending_launch
		var meta: Dictionary = _SaveGameService.peek_continue()
		if int(launch.get("seed", -1)) != int(meta.get("world_seed", -2)):
			_fail("Continue launch seed mismatch")
		elif str(launch.get("id", "")) != WORLD_ID:
			_fail("Continue launch world mismatch")
		else:
			var saved: Variant = _SaveGameService.pending_continue_position()
			if not saved is Vector3 or not is_equal_approx((saved as Vector3).x, 18.0):
				_fail("pending continue position missing")
			else:
				print("OK menu Continue arms the alive snapshot")
	menu.queue_free()
	_WorldManager.pending_launch = {}
	_SaveGameService.pending_continue = true

	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	player.voxel_position = Vector3.ZERO
	player.health = 1.0
	player.world_ready = false
	player.apply_count = 0
	player.inventory = _Inventory.new()
	entities.imported = []
	enemies.imported = []
	svc.call_deferred("_post_boot")
	for _i in 4:
		await process_frame
	if player.apply_count != 0:
		_fail("continue applied before spawn finished")
	player.world_ready = true
	var frames := 0
	while player.apply_count == 0 and frames < 90:
		await process_frame
		frames += 1
	if player.apply_count == 0:
		_fail("continue load did not apply after spawn")
		_SaveGameService.pending_continue = false
		return
	if not is_equal_approx(player.voxel_position.x, 18.0) or not is_equal_approx(player.voxel_position.z, 3.0):
		_fail("continue load lost player position %s" % player.voxel_position)
	elif not is_equal_approx(player.health, 55.0):
		_fail("continue load lost health %.1f" % player.health)
	elif not _slot_is(player.inventory.get_slot(0), "stone", 12):
		_fail("continue load lost hotbar stack")
	elif not _slot_is(player.inventory.get_slot(10), "wood", 4):
		_fail("continue load lost bag stack")
	elif str(player.inventory.armor_id) != "scout_leather":
		_fail("continue load lost armor")
	elif is_equal_approx(_TerrainEdits.get_height_delta(7, 8), 0.0):
		_fail("continue load lost the dig")
	elif _TerrainEdits.get_build_tile(9, 9) != _VoxelTypes.STONE:
		_fail("continue load lost the placed block")
	elif int(_FeatureRegistry.get_tile_override(2, 3)) != _VoxelTypes.STONE:
		_fail("continue load lost the tile override")
	else:
		var feat: Dictionary = _FeatureRegistry.get_feature(4, 4)
		if str(feat.get("build_id", "")) != "stone_wall":
			_fail("continue load lost the built feature")
		elif entities.imported.is_empty() or str(entities.imported[0].get("brain_id", "")) != "rabbit":
			_fail("continue load lost wildlife")
		elif enemies.imported.is_empty() or str(enemies.imported[0].get("enemy_id", "")) != "crystal_mite":
			_fail("continue load lost crystal enemies")
		else:
			print("OK continue load restores the alive snapshot")
	_SaveGameService.pending_continue = false


func _assert_quit_hooks() -> void:
	var main_src := FileAccess.get_file_as_string("res://main.gd")
	if main_src.find("close_requested") < 0 or main_src.find("func _save_quit_while_alive") < 0:
		_fail("window close must save before quitting")
	elif main_src.find("save_or_drop_continue") < 0:
		_fail("window close must call save_or_drop_continue")
	var pause_src := FileAccess.get_file_as_string("res://ui/pause_menu.gd")
	var quit_at := pause_src.find("func _quit")
	if quit_at < 0 or pause_src.find("save_or_drop_continue", quit_at) < 0:
		_fail("pause quit must save the alive session")
	var save_src := FileAccess.get_file_as_string("res://systems/save_game_service.gd")
	if save_src.find("export_entities") < 0 or save_src.find("snapshot[\"entities\"]") < 0:
		_fail("alive snapshot must store entities")
	elif save_src.find("export_enemies") < 0:
		_fail("alive snapshot must store crystal enemies")
	var ent_src := FileAccess.get_file_as_string("res://entities/entity_manager.gd")
	if ent_src.find("export_save_state") < 0:
		_fail("entity manager must export each live entity")
	var row_src := FileAccess.get_file_as_string("res://entities/world_entity.gd")
	var row_at := row_src.find("func export_save_state")
	var row_body := row_src.substr(row_at, 500) if row_at >= 0 else ""
	if row_body.find("health") < 0 or row_body.find("global_position") < 0:
		_fail("entity save must include health and position")


func _assert_real_player_and_entity_blobs() -> void:
	var scout := _Player.new()
	scout.inventory = _Inventory.new()
	scout.inventory.set_slot(0, "stone", 2)
	scout.voxel_position = Vector3(4.0, 5.0, 6.0)
	scout.health = 40.0
	var blob: Dictionary = scout.export_save_state()
	var pos: Array = blob.get("voxel_position", [])
	if pos.size() < 3 or not is_equal_approx(float(pos[0]), 4.0) or not is_equal_approx(float(pos[2]), 6.0):
		_fail("player export missing position")
	elif not is_equal_approx(float(blob.get("health", 0.0)), 40.0):
		_fail("player export missing health")
	else:
		var inv: Dictionary = blob.get("inventory", {})
		var slots: Array = inv.get("slots", [])
		if slots.is_empty() or str(slots[0].get("id", "")) != "stone":
			_fail("player export missing inventory")
	scout.free()


func _cleanup(svc: Node, player: Node, path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var continue_path := _SaveGameService.continue_save_path()
	if FileAccess.file_exists(continue_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(continue_path))
	_SaveGameService.pending_continue = false
	if is_instance_valid(player):
		player.queue_free()
	var entities = get_first_node_in_group("entity_manager")
	if entities and is_instance_valid(entities):
		entities.queue_free()
	var enemies = get_first_node_in_group("crystal_enemy_spawner")
	if enemies and is_instance_valid(enemies):
		enemies.queue_free()
	if is_instance_valid(svc):
		svc.queue_free()
	_WorldManager.active_world_id = ""
	_WorldManager.pending_resume = false
	_WorldManager.return_to_select = false
