class_name SaveGameService
extends Node
## Transactional persistence layer. WorldState is the sole overlay authority.
## Load stages: validate → checkpoint → pause → apply world_state → runtime →
## single rebuild → resume. Failure rolls back to checkpoint (no partial commit).

const _SaveCodec = preload("res://systems/save_codec.gd")
const _SaveSchema = preload("res://systems/save_schema.gd")
const _SaveGameConfig = preload("res://config/save_game_config.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldState = preload("res://world/world_state.gd")
const _ConfigJsonIO = preload("res://systems/config_json_io.gd")

signal save_completed(slot: int, path: String)
signal load_completed(slot: int)
signal save_failed(slot: int, reason: String)
signal load_transaction_stage(stage: String)

## Alias kept for external readers; schema version is authoritative.
const SAVE_VERSION := 2

const STAGE_IDLE := "idle"
const STAGE_VALIDATE := "validate"
const STAGE_CHECKPOINT := "checkpoint"
const STAGE_PAUSE := "pause"
const STAGE_APPLY_WORLD_STATE := "apply_world_state"
const STAGE_APPLY_RUNTIME := "apply_runtime"
const STAGE_REBUILD := "rebuild"
const STAGE_RESUME := "resume"
const STAGE_COMMIT := "commit"
const STAGE_ROLLBACK := "rollback"

static var pending_load_slot: int = -1

@export var config: Resource

var _auto_timer: float = 0.0
var _last_save_label: String = ""
var _transaction_active: bool = false
var _transaction_stage: String = STAGE_IDLE
var _checkpoint: Dictionary = {}
var _paused_nodes: Array = []
var _stream_was_paused: bool = false


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
	if _transaction_active:
		return
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


func is_transaction_active() -> bool:
	return _transaction_active


func get_transaction_stage() -> String:
	return _transaction_stage


func save_slot(slot: int = -1, silent: bool = false) -> Error:
	if slot < 0:
		slot = _cfg().default_slot
	if _transaction_active:
		save_failed.emit(slot, "transaction_busy")
		return ERR_BUSY
	var snapshot := collect_snapshot()
	# Seal after all fields present; re-seal after validate so on-disk checksum matches load.
	var check: Dictionary = _SaveSchema.validate_and_migrate(_SaveSchema.attach_integrity(snapshot))
	if not bool(check.get("ok", false)):
		save_failed.emit(slot, "validate_failed_%s" % str(check.get("reason", "?")))
		return ERR_INVALID_DATA
	var sealed: Dictionary = _SaveSchema.attach_integrity(check.get("data", {}))
	var json := JSON.stringify(sealed, "\t")
	var path := slot_path(slot)
	var err := _write_text_atomic(path, json)
	if err == OK:
		_last_save_label = path
		save_completed.emit(slot, path)
		if not silent:
			print("[SaveGame] Saved slot %d -> %s (schema v%d)" % [
				slot, path, _SaveSchema.CURRENT_VERSION
			])
	else:
		save_failed.emit(slot, "write_error_%d" % err)
	return err


func load_slot(slot: int = -1) -> bool:
	if slot < 0:
		slot = _cfg().default_slot
	if _transaction_active:
		save_failed.emit(slot, "transaction_busy")
		return false
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		save_failed.emit(slot, "missing_file")
		return false
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges().is_empty():
		save_failed.emit(slot, "empty_file")
		return false
	var parsed = JSON.parse_string(text)
	var ok: bool = await apply_snapshot_transactional(parsed)
	if ok:
		load_completed.emit(slot)
		print("[SaveGame] Loaded slot %d (transactional)" % slot)
	return ok


## In-process apply for tests/headless without a file.
func apply_snapshot(data: Dictionary) -> void:
	await apply_snapshot_transactional(data)


func apply_snapshot_transactional(raw) -> bool:
	_transaction_active = true
	_set_stage(STAGE_VALIDATE)
	var check: Dictionary = _SaveSchema.validate_and_migrate(raw)
	if not bool(check.get("ok", false)):
		_set_stage(STAGE_IDLE)
		_transaction_active = false
		save_failed.emit(-1, "validate_%s" % str(check.get("reason", "fail")))
		return false
	var data: Dictionary = check.get("data", {})

	await _wait_for_bootstrap()

	_set_stage(STAGE_CHECKPOINT)
	_checkpoint = _capture_session_checkpoint()

	_set_stage(STAGE_PAUSE)
	_pause_world_for_load()

	var success := false
	# Apply under pause; any failure rolls back to checkpoint.
	success = await _transaction_apply_body(data)

	if not success:
		_set_stage(STAGE_ROLLBACK)
		await _restore_session_checkpoint(_checkpoint)
		await _coordinated_chunk_rebuild()
		_resume_world_after_load()
		_checkpoint.clear()
		_set_stage(STAGE_IDLE)
		_transaction_active = false
		save_failed.emit(-1, "apply_failed_rolled_back")
		return false

	_set_stage(STAGE_RESUME)
	_resume_world_after_load()
	_set_stage(STAGE_COMMIT)
	_checkpoint.clear()
	_set_stage(STAGE_IDLE)
	_transaction_active = false
	return true


func _transaction_apply_body(data: Dictionary) -> bool:
	var world = get_tree().get_first_node_in_group("world")
	if world and data.has("world_seed") and int(data.world_seed) != int(world.world_seed):
		push_warning("SaveGame: world_seed mismatch (saved %s, current %s)." % [
			data.world_seed, world.world_seed
		])

	_set_stage(STAGE_APPLY_WORLD_STATE)
	if not _apply_world_state_from_payload(data):
		return false

	if world and world.has_method("invalidate_column_cache"):
		var ws = _WorldState.get_active()
		for key_variant in ws.height_delta.keys():
			var cell: Vector2i = key_variant
			world.invalidate_column_cache(cell.x, cell.y)
		for key_variant in ws.build_tile.keys():
			var cell2: Vector2i = key_variant
			world.invalidate_column_cache(cell2.x, cell2.y)

	_set_stage(STAGE_APPLY_RUNTIME)
	await _apply_runtime_state(data)

	_set_stage(STAGE_REBUILD)
	await _coordinated_chunk_rebuild()

	var visual_registry = get_tree().get_first_node_in_group("game_visual_registry")
	if visual_registry and visual_registry.has_method("refresh_all"):
		visual_registry.refresh_all()
	return true


func _apply_world_state_from_payload(data: Dictionary) -> bool:
	var ws = _WorldState.get_active()
	if data.has("world_state") and data.world_state is Dictionary:
		ws.import_persistence_bundle(data.world_state)
		return true
	# Migrated/legacy flat path
	ws.apply_save_overlay_dicts(
		data.get("terrain_edits", {}),
		data.get("features", {}),
		data.get("channels", {})
	)
	return true


func _coordinated_chunk_rebuild() -> void:
	var chunk_mgr = get_tree().get_first_node_in_group("chunk_manager")
	if chunk_mgr and chunk_mgr.has_method("rebuild_chunks"):
		chunk_mgr.rebuild_chunks()
		if chunk_mgr.has_method("await_rebuild_idle"):
			await chunk_mgr.await_rebuild_idle()


func _apply_runtime_state(data: Dictionary) -> void:
	var crystal = get_tree().get_first_node_in_group("crystal_manager")
	if crystal:
		if crystal.has_method("ensure_ready"):
			await crystal.ensure_ready()
		# Never import empty missing crystal blob — that used to wipe spawn points.
		if crystal.has_method("import_state") and data.has("crystal") and data.crystal is Dictionary:
			var cdata: Dictionary = data.crystal
			if not cdata.is_empty():
				crystal.import_state(cdata)

	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager and data.has("game"):
		var g: Dictionary = data.game
		game_manager.phase = int(g.get("phase", game_manager.phase))
		game_manager.run_state = int(g.get("run_state", game_manager.run_state))

	var town_def = get_tree().get_first_node_in_group("town_defense_manager")
	if town_def and town_def.has_method("import_state") and data.has("town_defense"):
		town_def.import_state(data.town_defense)

	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("apply_save_state") and data.has("player"):
		player.apply_save_state(data.player)

	var entity_mgr = get_tree().get_first_node_in_group("entity_manager")
	if entity_mgr and entity_mgr.has_method("import_entities") and data.has("entities"):
		entity_mgr.import_entities(data.entities)

	var enemy_spawner = get_tree().get_first_node_in_group("crystal_enemy_spawner")
	if enemy_spawner and enemy_spawner.has_method("import_enemies") and data.has("crystal_enemies"):
		enemy_spawner.import_enemies(data.crystal_enemies)

	# Spatial index rebuild after entities/spawns restored (discovery only).
	var spatial = get_tree().get_first_node_in_group("spatial_query_service")
	if spatial and spatial.has_method("rebuild_from_runtime"):
		spatial.rebuild_from_runtime()


func _pause_world_for_load() -> void:
	_paused_nodes.clear()
	var chunk_mgr = get_tree().get_first_node_in_group("chunk_manager")
	if chunk_mgr:
		_stream_was_paused = bool(chunk_mgr.stream_paused) if "stream_paused" in chunk_mgr else false
		if chunk_mgr.has_method("set_stream_paused"):
			chunk_mgr.set_stream_paused(true)
	for group_name in [
		"crystal_manager",
		"terrain_editor",
		"entity_manager",
		"crystal_enemy_spawner",
		"vegetation_growth_manager",
		"town_defense_manager",
		"game_manager",
	]:
		var node = get_tree().get_first_node_in_group(group_name)
		if node == null:
			continue
		_paused_nodes.append({
			"node": node,
			"process": node.is_processing(),
			"physics": node.is_physics_processing(),
		})
		node.set_process(false)
		node.set_physics_process(false)


func _resume_world_after_load() -> void:
	var chunk_mgr = get_tree().get_first_node_in_group("chunk_manager")
	if chunk_mgr and chunk_mgr.has_method("set_stream_paused"):
		chunk_mgr.set_stream_paused(_stream_was_paused)
	for entry_variant in _paused_nodes:
		var entry: Dictionary = entry_variant
		var node = entry.get("node", null)
		if node == null or not is_instance_valid(node):
			continue
		node.set_process(bool(entry.get("process", true)))
		node.set_physics_process(bool(entry.get("physics", true)))
	_paused_nodes.clear()


func _capture_session_checkpoint() -> Dictionary:
	var ws = _WorldState.get_active()
	var runtime := collect_snapshot()
	return {
		"world_state": ws.capture_overlay_snapshot(),
		"runtime": runtime,
	}


func _restore_session_checkpoint(cp: Dictionary) -> void:
	if cp.is_empty():
		return
	var ws = _WorldState.get_active()
	if cp.has("world_state") and cp.world_state is Dictionary:
		ws.restore_overlay_snapshot(cp.world_state)
	var runtime: Dictionary = cp.get("runtime", {})
	if not runtime.is_empty():
		await _apply_runtime_state(runtime)


func _set_stage(stage: String) -> void:
	_transaction_stage = stage
	load_transaction_stage.emit(stage)


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

	var ws = _WorldState.get_active()
	var world_state_bundle: Dictionary = ws.export_persistence_bundle()
	var overlay_export: Dictionary = ws.export_save_overlays()

	var seed_val: int = world.world_seed if world and "world_seed" in world else 0
	var snapshot := {
		"schema_version": _SaveSchema.CURRENT_VERSION,
		"version": _SaveSchema.CURRENT_VERSION,
		"format": _SaveSchema.FORMAT_ID,
		"timestamp": Time.get_unix_time_from_system(),
		"world_seed": seed_val,
		"world": {
			"seed": seed_val,
			"metadata": {},
		},
		"world_state": world_state_bundle,
		# Flat aliases for v1 compatibility / tooling.
		"terrain_edits": overlay_export.get("terrain_edits", {}),
		"channels": overlay_export.get("channels", {}),
		"features": overlay_export.get("features", {}),
		"world_state_revision": int(world_state_bundle.get("revision", 0)),
		"extensions": _SaveSchema.future_extension_stubs(),
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
	# Authored config snapshot is optional; performance quality is runtime and not sim authority.
	if cfg_svc and cfg_svc.game_config:
		snapshot["config"] = _ConfigJsonIO._serialize_game_config(cfg_svc.game_config)

	return snapshot


func _wait_for_bootstrap() -> void:
	var features = get_tree().get_first_node_in_group("world_features")
	if features and features.has_method("ensure_ready"):
		await features.ensure_ready()
	var crystal = get_tree().get_first_node_in_group("crystal_manager")
	if crystal and crystal.has_method("ensure_ready"):
		await crystal.ensure_ready()


func _write_text_atomic(path: String, text: String) -> Error:
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	# Replace destination.
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var err := DirAccess.rename_absolute(tmp_path, path)
	if err != OK:
		# Fallback: rewrite directly.
		return _write_text(path, text)
	return OK


func _write_text(path: String, text: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	return OK
