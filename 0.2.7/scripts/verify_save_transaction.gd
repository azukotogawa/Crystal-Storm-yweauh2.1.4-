extends SceneTree
## Transactional load under main scene: pause stream, apply WorldState, single rebuild.
## Usage: godot --headless -s scripts/verify_save_transaction.gd

const MAIN_SCENE := "res://scenes/main.tscn"
const _WorldState = preload("res://world/world_state.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _SaveSchema = preload("res://systems/save_schema.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const TEST_SLOT := 13


var _failed: int = 0
var _stages: Array = []


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		push_error("no main")
		quit(1)
		return
	var game: Node = packed.instantiate()
	root.add_child(game)

	var save_svc = null
	var terrain = null
	var chunk_manager = null
	var world = null
	for _i in 600:
		save_svc = get_first_node_in_group("save_game_service")
		terrain = get_first_node_in_group("terrain_editor")
		chunk_manager = get_first_node_in_group("chunk_manager")
		world = get_first_node_in_group("world")
		if save_svc and terrain and chunk_manager and world and terrain.chunk_manager != null:
			break
		await process_frame

	if save_svc == null or chunk_manager == null:
		push_error("boot timeout")
		quit(1)
		return

	if save_svc.config:
		save_svc.config.auto_save_enabled = false

	if save_svc.has_signal("load_transaction_stage"):
		save_svc.load_transaction_stage.connect(func(s: String): _stages.append(s))

	# Mutate world + overlay domains that must survive disk JSON load
	var col := Vector2i(4, 6)
	if not terrain.try_dig(Vector3(float(col.x) + 0.5, 0.0, float(col.y) + 0.5)):
		_fail("try_dig failed")
	_FeatureRegistry.register_feature(14, 15, _WorldFeatureTypes.FeatureKind.RUIN, {
		"center": Vector2i(14, 15),
	})
	_FeatureRegistry.register_entity_spawn(16, 17, int(_WorldFeatureTypes.FeatureKind.ANIMAL_SPAWN), 3)
	if chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle()

	var crystal = get_first_node_in_group("crystal_manager")
	var spawns_before := 0
	if crystal and crystal.has_method("export_state"):
		spawns_before = (crystal.export_state().get("spawns", []) as Array).size()
	if spawns_before <= 0:
		# Crystal may still be initializing; wait briefly
		for _w in 180:
			crystal = get_first_node_in_group("crystal_manager")
			if crystal and crystal.has_method("export_state"):
				spawns_before = (crystal.export_state().get("spawns", []) as Array).size()
			if spawns_before > 0:
				break
			await process_frame
	if spawns_before <= 0:
		_fail("expected crystal spawns before save (got %d)" % spawns_before)

	if save_svc.save_slot(TEST_SLOT) != OK:
		_fail("save_slot failed")
		quit(1)
		return

	# Further mutate so load must restore
	terrain.try_dig(Vector3(float(col.x) + 0.5, 0.0, float(col.y) + 0.5))
	if chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle()

	# Stream pause API present
	if not chunk_manager.has_method("set_stream_paused"):
		_fail("chunk_manager missing set_stream_paused")
	else:
		chunk_manager.set_stream_paused(true)
		if not chunk_manager.is_stream_paused():
			_fail("stream_paused not sticky")
		chunk_manager.set_stream_paused(false)

	_stages.clear()
	var loaded: bool = await save_svc.load_slot(TEST_SLOT)
	if not loaded:
		_fail("transactional load_slot failed")
	else:
		print("OK transactional load_slot")

	if "pause" not in _stages and "rebuild" not in _stages:
		print("WARN stages captured: %s" % str(_stages))
	else:
		print("OK transaction stages observed: %s" % str(_stages))

	var layers: int = int(_WorldState.get_active().height_delta.get(col, 0))
	if layers >= 0:
		_fail("expected dig layers restored at %s got %d" % [col, layers])
	else:
		print("OK world_state dig restored layers=%d" % layers)

	# Feature geometry types after real disk save/load
	var feat: Dictionary = _FeatureRegistry.get_feature(14, 15)
	if feat.is_empty():
		_fail("feature cell missing after load_slot")
	elif not (feat.get("center") is Vector2i):
		_fail("feature center not Vector2i after load_slot (got %s)" % [feat.get("center")])
	else:
		print("OK feature center Vector2i after load_slot")

	var spawns: Array = _FeatureRegistry.get_entity_spawns()
	var spawn_ok := false
	for s in spawns:
		if s is Dictionary and s.get("world_pos") is Vector2i:
			var p: Vector2i = s.world_pos
			if p == Vector2i(16, 17):
				spawn_ok = true
	if not spawn_ok:
		_fail("entity_spawns.world_pos Vector2i missing after load_slot")
	else:
		print("OK entity_spawns.world_pos Vector2i after load_slot")
	# Must not SCRIPT ERROR
	var _chunk_spawns: Array = _FeatureRegistry.get_spawns_in_chunk(Vector2i(1, 1), 16)

	# Crystal win targets survive transactional load
	crystal = get_first_node_in_group("crystal_manager")
	var spawns_after := 0
	if crystal and crystal.has_method("export_state"):
		spawns_after = (crystal.export_state().get("spawns", []) as Array).size()
	if spawns_after <= 0:
		_fail("crystal spawns wiped after load (before=%d after=%d)" % [spawns_before, spawns_after])
	elif spawns_after < spawns_before:
		_fail("crystal spawn count dropped after load (before=%d after=%d)" % [spawns_before, spawns_after])
	else:
		print("OK crystal spawns survived load_slot count=%d" % spawns_after)

	# Corruption rejection does not clobber session
	var before_corrupt: Dictionary = _WorldState.get_active().capture_overlay_snapshot()
	var bad_ok: bool = await save_svc.apply_snapshot_transactional({"version": 1, "checksum": "nope", "terrain_edits": {}})
	# validate may fail before corrupt checksum on v1 without checksum - force checksum fail
	var sealed: Dictionary = _SaveSchema.attach_integrity({
		"schema_version": 2,
		"version": 2,
		"world_state": {"height_delta": {}, "build_tile": {}, "channels": {}},
		"terrain_edits": {"height_delta": {}, "build_tile": {}},
	})
	sealed["checksum"] = "ffffffff"
	var pre_layers: int = int(_WorldState.get_active().height_delta.get(col, 0))
	var rej: bool = await save_svc.apply_snapshot_transactional(sealed)
	if rej:
		_fail("corrupt payload must not commit")
	var post_layers: int = int(_WorldState.get_active().height_delta.get(col, 0))
	if post_layers != pre_layers:
		_fail("corrupt load must not change WorldState overlays")
	else:
		print("OK corrupt load rejected without clobber")

	if chunk_manager.has_method("shutdown_workers"):
		chunk_manager.shutdown_workers()
	game.queue_free()
	if _failed == 0:
		print("All save transaction tests OK")
		quit(0)
	else:
		quit(1)
