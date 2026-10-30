class_name SaveGameService
extends Node

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

const SAVE_VERSION := 3

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
static var pending_continue: bool = false

const CONTINUE_FILE_NAME := "continue.json"

const MSG_SAVE_FAILED := "Couldn't save. Try again; your last save is untouched."
const MSG_LOAD_FAILED := "Couldn't load that save. Your current game wasn't changed."
const MSG_LOAD_MISSING := "No save to load yet."
const MSG_BUSY := "Still saving or loading. Try again in a moment."

@export var config: Resource

var _auto_timer: float = 0.0
var _last_save_label: String = ""
var _transaction_active: bool = false
var _transaction_stage: String = STAGE_IDLE
var _checkpoint: Dictionary = {}
var _paused_nodes: Array = []
var _stream_was_paused: bool = false
var last_player_message: String = ""


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
	if not save_failed.is_connected(_on_save_failed_message):
		save_failed.connect(_on_save_failed_message)


static func player_message_for(reason: String) -> String:
	if reason.begins_with("write_error") or reason.begins_with("validate_failed"):
		return MSG_SAVE_FAILED
	if reason == "transaction_busy":
		return MSG_BUSY
	if reason == "missing_file" or reason == "missing_world_save":
		return MSG_LOAD_MISSING
	return MSG_LOAD_FAILED


func _on_save_failed_message(_slot: int, reason: String) -> void:
	last_player_message = player_message_for(reason)
	print("[SaveGame] player message: %s (%s)" % [last_player_message, reason])
	var tree := get_tree()
	if tree == null:
		return
	var overlay = tree.get_first_node_in_group("game_overlay")
	if overlay and overlay.has_method("_show_toast"):
		overlay.call("_show_toast", last_player_message)


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
		_autosave_now()


func _post_boot() -> void:
	var WM = load("res://systems/world_manager.gd")
	if pending_continue and FileAccess.file_exists(continue_save_path()):
		await _wait_for_continue_boot()
		pending_continue = false
		if WM:
			WM.pending_resume = false
		await load_path(continue_save_path())
		return
	pending_continue = false
	var compose = get_tree().get_first_node_in_group("composition_root") if is_inside_tree() else null
	var frames := 0
	while compose != null and int(compose.stage) < 5 and frames < 3600:
		await get_tree().process_frame
		frames += 1
		compose = get_tree().get_first_node_in_group("composition_root") if is_inside_tree() else null
	if WM and bool(WM.pending_resume) and str(WM.active_world_id) != "":
		WM.pending_resume = false
		await load_world_id(str(WM.active_world_id))
		return
	if pending_load_slot >= 0:
		var slot := pending_load_slot
		pending_load_slot = -1
		await load_slot(slot)


func _wait_for_continue_boot() -> void:
	var frames := 0
	while frames < 3600 and is_inside_tree():
		var compose = get_tree().get_first_node_in_group("composition_root")
		var boot_ready := compose == null or int(compose.stage) >= 5
		var player = get_tree().get_first_node_in_group("player")
		var spawn_done := true
		if player != null:
			var ready_v: Variant = player.get("world_ready")
			if ready_v != null:
				spawn_done = bool(ready_v)
		elif compose != null:
			spawn_done = false
		if boot_ready and spawn_done:
			return
		await get_tree().process_frame
		frames += 1


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
		_autosave_now()


func _on_town_state_changed(_name: String, state: int, _center: Vector2i) -> void:
	if _cfg().auto_save_on_town_besieged and state == 2:
		_autosave_now()


func _autosave_now() -> void:
	var WM = load("res://systems/world_manager.gd")
	if WM and str(WM.active_world_id) != "":
		save_world_id(str(WM.active_world_id), true)
	else:
		save_slot(_cfg().default_slot, true)


static func continue_save_path() -> String:
	return "user://saves/".path_join(CONTINUE_FILE_NAME)


static func peek_continue() -> Dictionary:
	var path := continue_save_path()
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges().is_empty():
		return {}
	var parsed = JSON.parse_string(text)
	var check: Dictionary = _SaveSchema.validate_and_migrate(parsed)
	if not bool(check.get("ok", false)):
		return {}
	var data: Dictionary = check.get("data", {})
	if not bool(data.get("continue_alive", false)):
		return {}
	var game_v: Variant = data.get("game", {})
	if game_v is Dictionary and int((game_v as Dictionary).get("run_state", 0)) != 0:
		return {}
	var player_v: Variant = data.get("player", {})
	if not player_v is Dictionary:
		return {}
	var player: Dictionary = player_v
	if not player.has("voxel_position"):
		return {}
	if not player.has("health") or float(player.get("health", 0.0)) <= 0.0:
		return {}
	return {
		"world_id": str(data.get("world_id", "")),
		"world_seed": int(data.get("world_seed", 0)),
		"health": float(player.get("health", 0.0)),
		"voxel_position": player.get("voxel_position", []),
	}


static func pending_continue_position() -> Variant:
	if not pending_continue:
		return null
	var pos: Variant = peek_continue().get("voxel_position", [])
	if not pos is Array or (pos as Array).size() < 3:
		return null
	var arr: Array = pos
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


static func has_continue() -> bool:
	return not peek_continue().is_empty()


static func clear_continue() -> void:
	var path := continue_save_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func wipe_world_saves() -> int:
	clear_continue()
	var dir := DirAccess.open("user://saves")
	if dir == null:
		return 0
	var removed := 0
	for file in dir.get_files():
		if file.begins_with("world_") and DirAccess.remove_absolute("user://saves".path_join(file)) == OK:
			removed += 1
	return removed


static func world_save_path(world_id: String) -> String:
	if world_id.strip_edges().is_empty():
		return ""
	return "user://saves/world_%s.json" % world_id.strip_edges()


static func has_world_save(world_id: String) -> bool:
	var path := world_save_path(world_id)
	return path != "" and FileAccess.file_exists(path)


func slot_path(slot: int) -> String:
	return _cfg().save_directory.path_join("slot_%d.json" % slot)


func is_transaction_active() -> bool:
	return _transaction_active


func get_transaction_stage() -> String:
	return _transaction_stage


func is_session_alive() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var player = tree.get_first_node_in_group("player")
	if player == null:
		return false
	if "health" in player and float(player.health) <= 0.0:
		return false
	var gm = tree.get_first_node_in_group("game_manager")
	if gm != null and gm.has_method("is_run_playing") and not bool(gm.is_run_playing()):
		return false
	return true


func save_or_drop_continue() -> void:
	if is_session_alive():
		save_alive_session(true)
		return
	if get_tree() == null or get_tree().get_first_node_in_group("player") == null:
		return
	clear_continue()
	var WM = load("res://systems/world_manager.gd")
	var world_id := str(WM.active_world_id) if WM else ""
	if world_id != "":
		save_world_id(world_id, true)


func save_alive_session(silent: bool = true) -> Error:
	if _transaction_active:
		return ERR_BUSY
	if not is_session_alive():
		return ERR_UNAVAILABLE
	var WM = load("res://systems/world_manager.gd")
	var world_id := str(WM.active_world_id) if WM else ""
	var snapshot := collect_snapshot()
	snapshot["world_id"] = world_id
	snapshot["continue_alive"] = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://saves"))
	var err := _write_sealed_snapshot(continue_save_path(), snapshot, silent, "continue")
	if err != OK:
		return err
	if world_id != "":
		return _write_sealed_snapshot(world_save_path(world_id), snapshot, true, world_id)
	return OK


func _write_sealed_snapshot(path: String, snapshot: Dictionary, silent: bool, label: String) -> Error:
	var check: Dictionary = _SaveSchema.validate_and_migrate(_SaveSchema.attach_integrity(snapshot))
	if not bool(check.get("ok", false)):
		save_failed.emit(-1, "validate_failed_%s" % str(check.get("reason", "?")))
		return ERR_INVALID_DATA
	var sealed: Dictionary = _SaveSchema.attach_integrity(check.get("data", {}))
	var err := _write_text_atomic(path, JSON.stringify(sealed, "\t"))
	if err == OK:
		_last_save_label = path
		save_completed.emit(-1, path)
		if not silent:
			print("[SaveGame] Saved %s -> %s" % [label, path])
	else:
		save_failed.emit(-1, "write_error_%d" % err)
	return err


func save_world_id(world_id: String, silent: bool = false) -> Error:
	if world_id.strip_edges().is_empty() or _transaction_active:
		return ERR_BUSY if _transaction_active else ERR_INVALID_PARAMETER
	var snapshot := collect_snapshot()
	snapshot["world_id"] = world_id
	var check: Dictionary = _SaveSchema.validate_and_migrate(_SaveSchema.attach_integrity(snapshot))
	if not bool(check.get("ok", false)):
		save_failed.emit(-1, "validate_failed_%s" % str(check.get("reason", "?")))
		return ERR_INVALID_DATA
	var sealed: Dictionary = _SaveSchema.attach_integrity(check.get("data", {}))
	var path := world_save_path(world_id)
	var err := _write_text_atomic(path, JSON.stringify(sealed, "\t"))
	if err == OK:
		_last_save_label = path
		save_completed.emit(-1, path)
		if not silent:
			print("[SaveGame] Saved world %s -> %s" % [world_id, path])
	else:
		save_failed.emit(-1, "write_error_%d" % err)
	return err


func load_world_id(world_id: String) -> bool:
	var path := world_save_path(world_id)
	if path.is_empty() or not FileAccess.file_exists(path):
		save_failed.emit(-1, "missing_world_save")
		return false
	return await load_path(path)


func load_path(path: String) -> bool:
	if _transaction_active:
		save_failed.emit(-1, "transaction_busy")
		return false
	if not FileAccess.file_exists(path):
		save_failed.emit(-1, "missing_file")
		return false
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges().is_empty():
		save_failed.emit(-1, "empty_file")
		return false
	var parsed = JSON.parse_string(text)
	var ok: bool = await apply_snapshot_transactional(parsed)
	if ok:
		load_completed.emit(-1)
		print("[SaveGame] Loaded %s" % path)
	return ok


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


func apply_snapshot(data: Dictionary) -> void:
	await apply_snapshot_transactional(data)


func apply_snapshot_transactional(raw) -> bool:
	_transaction_active = true
	_set_stage(STAGE_VALIDATE)
	var check: Dictionary = _SaveSchema.validate_and_migrate(raw)
	if not bool(check.get("ok", false)):
		_set_stage(STAGE_IDLE)
		_transaction_active = false
		save_failed.emit(-1, str(check.get("message", "validate_%s" % str(check.get("reason", "fail")))))
		return false
	var data: Dictionary = check.get("data", {})

	await _wait_for_bootstrap()

	_set_stage(STAGE_CHECKPOINT)
	_checkpoint = _capture_session_checkpoint()

	_set_stage(STAGE_PAUSE)
	_pause_world_for_load()

	var success := false
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
		visual_registry.refresh_all("SaveGameService")
	return true


func _apply_world_state_from_payload(data: Dictionary) -> bool:
	var ws = _WorldState.get_active()
	var applied := false
	if data.has("world_state") and data.world_state is Dictionary:
		ws.import_persistence_bundle(data.world_state)
		applied = true
	else:
		# Migrated/legacy flat path
		ws.apply_save_overlay_dicts(
			data.get("terrain_edits", {}),
			data.get("features", {}),
			data.get("channels", {})
		)
		applied = true
	var living = load("res://world/living_force.gd")
	if living:
		living.rearm_push_watch()
	return applied


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

	var progression = get_tree().get_first_node_in_group("progression_service")
	if progression and progression.has_method("import_state") and data.has("progression") and data.progression is Dictionary:
		var pdata: Dictionary = data.progression
		if not pdata.is_empty():
			progression.import_state(pdata)

	var skills = get_tree().get_first_node_in_group("skill_service")
	if skills and skills.has_method("import_state") and data.has("skills") and data.skills is Dictionary:
		var sdata: Dictionary = data.skills
		if not sdata.is_empty():
			skills.import_state(sdata)

	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("apply_save_state") and data.has("player"):
		player.apply_save_state(data.player)

	var entity_mgr = get_tree().get_first_node_in_group("entity_manager")
	if entity_mgr and entity_mgr.has_method("import_entities") and data.has("entities"):
		entity_mgr.import_entities(data.entities)

	var enemy_spawner = get_tree().get_first_node_in_group("crystal_enemy_spawner")
	if enemy_spawner and enemy_spawner.has_method("import_enemies") and data.has("crystal_enemies"):
		enemy_spawner.import_enemies(data.crystal_enemies)

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
		"terrain_edits": overlay_export.get("terrain_edits", {}),
		"channels": overlay_export.get("channels", {}),
		"features": overlay_export.get("features", {}),
		"world_state_revision": int(world_state_bundle.get("revision", 0)),
		"extensions": _SaveSchema.future_extension_stubs(),
	}

	var progression = get_tree().get_first_node_in_group("progression_service")
	if progression and progression.has_method("export_state"):
		snapshot["progression"] = progression.export_state()
	var skills = get_tree().get_first_node_in_group("skill_service")
	if skills and skills.has_method("export_state"):
		snapshot["skills"] = skills.export_state()
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
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var err := DirAccess.rename_absolute(tmp_path, path)
	if err != OK:
		return _write_text(path, text)
	return OK


func _write_text(path: String, text: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	return OK
