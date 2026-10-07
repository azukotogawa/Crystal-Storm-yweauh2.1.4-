extends SceneTree
## Per-world save file + Leave/Play resume contract (overlays + player blob).
## Usage: godot --headless -s scripts/verify_world_save_resume.gd

const _WorldState = preload("res://world/world_state.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _SaveGameService = preload("res://systems/save_game_service.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _WorldManager = preload("res://systems/world_manager.gd")

const WORLD_ID := "verify_resume_tmp"


var _failed: int = 0


class StubPlayer extends Node:
	var voxel_position := Vector3(12.0, 4.0, 8.0)
	var health := 80.0

	func _enter_tree() -> void:
		add_to_group("player")

	func export_save_state() -> Dictionary:
		return {
			"voxel_position": [voxel_position.x, voxel_position.y, voxel_position.z],
			"health": health,
		}

	func apply_save_state(data: Dictionary) -> void:
		var pos: Array = data.get("voxel_position", [0.0, 0.0, 0.0])
		voxel_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		health = float(data.get("health", health))


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


func _cleanup(svc: Node, player: Node, path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if is_instance_valid(player):
		player.queue_free()
	if is_instance_valid(svc):
		svc.queue_free()
	_WorldManager.active_world_id = ""
	_WorldManager.pending_resume = false
	_WorldManager.return_to_select = false
