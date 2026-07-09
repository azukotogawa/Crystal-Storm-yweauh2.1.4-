class_name SaveGameService
extends Node

const _SaveCodec = preload("res://systems/save_codec.gd")
const _SaveGameConfig = preload("res://config/save_game_config.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _ConfigJsonIO = preload("res://systems/config_json_io.gd")

signal save_completed(slot: int, path: String)
signal load_completed(slot: int)
signal save_failed(slot: int, reason: String)

const SAVE_VERSION := 1

static var pending_load_slot: int = -1

@export var config: Resource

var _auto_timer: float = 0.0
var _last_save_label: String = ""


func _enter_tree() -> void:
	add_to_group("save_game_service")


func _cfg():
	if config == null or not config is _SaveGameConfig:
		config = _SaveGameConfig.create_default()
	return config


func _ready() -> void:
	var cfg = _cfg()
	DirAccess.make_dir_recursive_absolute(cfg.save_directory)
	call_deferred("_post_boot")
	_connect_autosave_hooks()


const _GameplayInput = preload("res://helpers/gameplay_input.gd")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if _GameplayInput.blocks_actions():
		return
	if event.is_action_pressed("quick_save"):
		quick_save()
	elif event.is_action_pressed("quick_load"):
		quick_load()


func _process(delta: float) -> void:
	var cfg = _cfg()
	if not cfg.auto_save_enabled:
		return
	_auto_timer += delta
	if _auto_timer >= cfg.auto_save_interval_sec:
		_auto_timer = 0.0
		save_slot(cfg.default_slot, true)


func _post_boot() -> void:
	if pending_load_slot >= 0:
		var slot := pending_load_slot
		pending_load_slot = -1
		await load_slot(slot)


func _connect_autosave_hooks() -> void:
	var crystal := get_tree().get_first_node_in_group("crystal_manager")
	if crystal and crystal.has_method("get_evolution"):
		var evo = crystal.get_evolution()
		if evo and not evo.enemy_unlocked.is_connected(_on_enemy_unlocked):
			evo.enemy_unlocked.connect(_on_enemy_unlocked)
	var town_def := get_tree().get_first_node_in_group("town_defense_manager")
	if town_def and not town_def.town_state_changed.is_connected(_on_town_state_changed):
		town_def.town_state_changed.connect(_on_town_state_changed)


func _on_enemy_unlocked(_enemy_id: StringName) -> void:
	if _cfg().auto_save_on_enemy_unlock:
		save_slot(_cfg().default_slot, true)


func _on_town_state_changed(_name: String, state: int, _center: Vector2i) -> void:
	if _cfg().auto_save_on_town_besieged and state == 2:
		save_slot(_cfg().default_slot, true)


func slot_path(slot: int) -> String:
	return _cfg().save_directory.path_join("slot_%d.json" % slot)


func save_slot(slot: int = -1, silent: bool = false) -> Error:
	if slot < 0:
		slot = _cfg().default_slot
	var snapshot := collect_snapshot()
	var json := JSON.stringify(snapshot, "\t")
	var path := slot_path(slot)
	var err := _write_text(path, json)
	if err == OK:
		_last_save_label = path
		save_completed.emit(slot, path)
		if not silent:
			print("[SaveGame] Saved slot %d -> %s" % [slot, path])
	else:
		save_failed.emit(slot, "write_error_%d" % err)
	return err


func load_slot(slot: int = -1) -> bool:
	if slot < 0:
		slot = _cfg().default_slot
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		save_failed.emit(slot, "missing_file")
		return false
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		save_failed.emit(slot, "parse_error")
		return false
	await apply_snapshot(parsed)
	load_completed.emit(slot)
	print("[SaveGame] Loaded slot %d" % slot)
	return true


func quick_save() -> Error:
	return save_slot(_cfg().default_slot)


func quick_load() -> void:
	pending_load_slot = -1
	load_slot(_cfg().default_slot)


func has_save(slot: int = -1) -> bool:
	if slot < 0:
		slot = _cfg().default_slot
	return FileAccess.file_exists(slot_path(slot))


func get_last_save_path() -> String:
	return _last_save_label


func collect_snapshot() -> Dictionary:
	var world = get_tree().get_first_node_in_group("world")
	var player = get_tree().get_first_node_in_group("player")
	var crystal = get_tree().get_first_node_in_group("crystal_manager")
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	var town_def = get_tree().get_first_node_in_group("town_defense_manager")
	var entity_mgr = get_tree().get_first_node_in_group("entity_manager")
	var enemy_spawner = get_tree().get_first_node_in_group("crystal_enemy_spawner")
	var cfg_svc = get_tree().get_first_node_in_group("config_service")

	var snapshot := {
		"version": SAVE_VERSION,
		"timestamp": Time.get_unix_time_from_system(),
		"world_seed": world.world_seed if world and "world_seed" in world else 0,
		"terrain_edits": _TerrainEdits.to_dict(),
		"channels": _ChannelRegistry.to_dict(),
		"features": _FeatureRegistry.to_dict(),
	}

	if player and player.has_method("export_save_state"):
		snapshot["player"] = player.export_save_state()
	if crystal and crystal.has_method("export_state"):
		snapshot["crystal"] = crystal.export_state()
	if game_manager:
		snapshot["game"] = {
			"phase": int(game_manager.phase),
			"run_state": int(game_manager.run_state),
		}
	if town_def and town_def.has_method("export_state"):
		snapshot["town_defense"] = town_def.export_state()
	if entity_mgr and entity_mgr.has_method("export_entities"):
		snapshot["entities"] = entity_mgr.export_entities()
	if enemy_spawner and enemy_spawner.has_method("export_enemies"):
		snapshot["crystal_enemies"] = enemy_spawner.export_enemies()
	if cfg_svc and cfg_svc.game_config:
		snapshot["config"] = _ConfigJsonIO._serialize_game_config(cfg_svc.game_config)

	return snapshot


func apply_snapshot(data: Dictionary) -> void:
	if int(data.get("version", 0)) != SAVE_VERSION:
		push_warning("SaveGame: version mismatch — attempting best-effort load.")

	await _wait_for_bootstrap()

	var world = get_tree().get_first_node_in_group("world")
	if world and data.has("world_seed") and int(data.world_seed) != int(world.world_seed):
		push_warning("SaveGame: world_seed mismatch (saved %s, current %s)." % [data.world_seed, world.world_seed])

	_TerrainEdits.load_from_dict(data.get("terrain_edits", {}))
	_ChannelRegistry.load_from_dict(data.get("channels", {}))
	_FeatureRegistry.apply_save_overlay(data.get("features", {}))

	var chunk_mgr = get_tree().get_first_node_in_group("chunk_manager")
	if chunk_mgr and chunk_mgr.has_method("rebuild_chunks"):
		chunk_mgr.rebuild_chunks()
		if chunk_mgr.has_method("await_rebuild_idle"):
			await chunk_mgr.await_rebuild_idle()
	elif chunk_mgr and chunk_mgr.has_method("rebuild_chunk_at_world"):
		if world and world.has_method("invalidate_column_cache"):
			for key in _TerrainEdits.to_dict().get("height_delta", {}).keys():
				var cell := _SaveCodec.vec2i_from_key(str(key))
				world.invalidate_column_cache(cell.x, cell.y)

	var crystal = get_tree().get_first_node_in_group("crystal_manager")
	if crystal:
		if crystal.has_method("ensure_ready"):
			await crystal.ensure_ready()
		if crystal.has_method("import_state"):
			crystal.import_state(data.get("crystal", {}))

	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager and data.has("game"):
		var g: Dictionary = data.game
		game_manager.phase = int(g.get("phase", game_manager.phase))
		game_manager.run_state = int(g.get("run_state", game_manager.run_state))

	var town_def = get_tree().get_first_node_in_group("town_defense_manager")
	if town_def and town_def.has_method("import_state"):
		town_def.import_state(data.get("town_defense", {}))

	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("apply_save_state") and data.has("player"):
		player.apply_save_state(data.player)

	var entity_mgr = get_tree().get_first_node_in_group("entity_manager")
	if entity_mgr and entity_mgr.has_method("import_entities"):
		entity_mgr.import_entities(data.get("entities", []))

	var enemy_spawner = get_tree().get_first_node_in_group("crystal_enemy_spawner")
	if enemy_spawner and enemy_spawner.has_method("import_enemies"):
		enemy_spawner.import_enemies(data.get("crystal_enemies", []))

	var visual_registry = get_tree().get_first_node_in_group("game_visual_registry")
	if visual_registry and visual_registry.has_method("refresh_all"):
		visual_registry.refresh_all()


func _wait_for_bootstrap() -> void:
	var features = get_tree().get_first_node_in_group("world_features")
	if features and features.has_method("ensure_ready"):
		await features.ensure_ready()
	var crystal = get_tree().get_first_node_in_group("crystal_manager")
	if crystal and crystal.has_method("ensure_ready"):
		await crystal.ensure_ready()


func _write_text(path: String, text: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	return OK