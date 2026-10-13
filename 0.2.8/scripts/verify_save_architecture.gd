extends SceneTree
## Save architecture: schema, migration, corruption, round-trip, rollback, determinism.
## Usage: godot --headless -s scripts/verify_save_architecture.gd

const _WorldState = preload("res://world/world_state.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _SaveSchema = preload("res://systems/save_schema.gd")
const _SaveCodec = preload("res://systems/save_codec.gd")
const _SaveGameService = preload("res://systems/save_game_service.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")


var _failed: int = 0


func _init() -> void:
	_run()
	if _failed == 0:
		print("OK save architecture unit contracts")
		quit(0)
	else:
		push_error("verify_save_architecture: %d failure(s)" % _failed)
		quit(1)


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	_test_schema_migration_and_corruption()
	_test_world_state_persistence_roundtrip()
	_test_json_disk_vector2i_roundtrip()
	_test_deterministic_restore()
	_test_checkpoint_rollback()
	_test_integrity_attach()


func _test_schema_migration_and_corruption() -> void:
	# v1 payload migrates to v2 with world_state
	var v1 := {
		"version": 1,
		"world_seed": 42,
		"terrain_edits": {
			"height_delta": {"3,4": -1},
			"build_tile": {},
		},
		"features": {
			"tile_overrides": {"1,1": 5},
			"feature_cells": {},
		},
		"channels": {
			"channels": {
				"0,0": {"water_level": 0.5, "flow_dir": [1, 0]},
			},
		},
	}
	var mig: Dictionary = _SaveSchema.validate_and_migrate(v1)
	if not bool(mig.get("ok", false)):
		_fail("v1 migration failed: %s" % str(mig.get("reason")))
		return
	var data: Dictionary = mig.get("data", {})
	if int(data.get("schema_version", 0)) != _SaveSchema.CURRENT_VERSION:
		_fail("migrated schema_version wrong")
	if not data.has("world_state"):
		_fail("migration must produce world_state block")
	var ws_block: Dictionary = data.world_state
	if not ws_block.has("height_delta"):
		_fail("world_state missing height_delta after migrate")

	# Corruption: bad checksum
	var good: Dictionary = _SaveSchema.attach_integrity({
		"schema_version": 2,
		"version": 2,
		"world_state": {"height_delta": {}, "build_tile": {}, "channels": {}},
		"terrain_edits": {"height_delta": {}, "build_tile": {}},
	})
	good["checksum"] = "deadbeef"
	var bad: Dictionary = _SaveSchema.validate_and_migrate(good)
	if bool(bad.get("ok", true)):
		_fail("checksum mismatch must fail validation")
	elif str(bad.get("reason", "")) != "checksum_mismatch":
		_fail("expected checksum_mismatch got %s" % str(bad.get("reason")))

	# Truncated / null
	var null_r: Dictionary = _SaveSchema.validate_and_migrate(null)
	if bool(null_r.get("ok", true)):
		_fail("null payload must fail")

	# Too new
	var future := {"schema_version": 99, "world_state": {}}
	var fut: Dictionary = _SaveSchema.validate_and_migrate(future)
	if bool(fut.get("ok", true)):
		_fail("future schema must fail")

	print("OK schema migration + corruption rejection")


func _test_world_state_persistence_roundtrip() -> void:
	_WorldState.replace_active()
	var ws = _WorldState.get_active()
	_TerrainEdits.dig(7, 8, 2)
	_TerrainEdits.build_wall(9, 9, _VoxelTypes.STONE)
	_FeatureRegistry.set_tile_override(2, 2, _VoxelTypes.GRASS_TUFT)
	_FeatureRegistry.register_feature(4, 4, _WorldFeatureTypes.FeatureKind.RUIN, {
		"center": Vector2i(4, 4),
	})
	_FeatureRegistry.register_entity_spawn(6, 6, int(_WorldFeatureTypes.FeatureKind.ANIMAL_SPAWN), 1)
	_ChannelRegistry.register_channel(0, 1, Vector2i(0, 1), 0.7)
	var rev: int = int(ws.revision)
	var bundle: Dictionary = ws.export_persistence_bundle()
	if int(bundle.get("revision", -1)) != rev:
		_fail("export must include live revision")

	# Mutate live then reimport
	_TerrainEdits.dig(7, 8, 1)
	_WorldState.replace_active()
	_WorldState.get_active().import_persistence_bundle(bundle)
	var ws2 = _WorldState.get_active()
	if int(ws2.revision) != rev:
		_fail("import must restore revision (got %d want %d)" % [ws2.revision, rev])
	if not is_equal_approx(_TerrainEdits.get_height_delta(7, 8), float(-2) * 2.0) \
			and not is_equal_approx(_TerrainEdits.get_height_delta(7, 8), -4.0):
		# layer height may be 2.0 default → 2 digs * -2 layers = -4 if scale 2? dig stores layers
		# get_height_delta returns layers * layer_height
		pass
	var layers_at: int = int(ws2.height_delta.get(Vector2i(7, 8), 0))
	if layers_at != -2:
		_fail("height_delta layers not restored (got %d want -2)" % layers_at)
	if is_equal_approx(_TerrainEdits.get_height_delta(7, 8), 0.0):
		_fail("get_height_delta should be non-zero after restore")
	if _TerrainEdits.get_build_tile(9, 9) != _VoxelTypes.STONE:
		_fail("build tile not restored")
	if _FeatureRegistry.get_tile_override(2, 2) != _VoxelTypes.GRASS_TUFT:
		_fail("feature tile not restored")
	if _FeatureRegistry.get_feature(4, 4).is_empty():
		_fail("feature cell not restored")
	if not _ChannelRegistry.is_channel(0, 1):
		_fail("channel not restored")
	if absf(_ChannelRegistry.get_water_level(0, 1) - 0.7) > 0.01:
		_fail("channel water not restored")
	if _FeatureRegistry.get_entity_spawns().is_empty():
		_fail("entity spawns not restored")
	var feat: Dictionary = _FeatureRegistry.get_feature(4, 4)
	if not (feat.get("center") is Vector2i):
		_fail("feature center must be Vector2i after restore (got %s)" % typeof(feat.get("center")))
	print("OK world_state persistence roundtrip")


## Real disk path: JSON.stringify/parse turns ints into floats; Vector2i must survive.
func _test_json_disk_vector2i_roundtrip() -> void:
	_WorldState.replace_active()
	_FeatureRegistry.register_feature(10, 11, _WorldFeatureTypes.FeatureKind.RUIN, {
		"center": Vector2i(10, 11),
	})
	_FeatureRegistry.register_entity_spawn(12, 13, int(_WorldFeatureTypes.FeatureKind.ANIMAL_SPAWN), 2)
	_FeatureRegistry.register_town(Vector2i(20, 20), 2, "TestTown")
	var bundle: Dictionary = _WorldState.get_active().export_persistence_bundle()
	var sealed: Dictionary = _SaveSchema.attach_integrity({
		"schema_version": 2,
		"version": 2,
		"format": _SaveSchema.FORMAT_ID,
		"world_state": bundle,
		"terrain_edits": {
			"height_delta": bundle.get("height_delta", {}),
			"build_tile": bundle.get("build_tile", {}),
		},
		"features": {
			"tile_overrides": bundle.get("tile_overrides", {}),
			"feature_cells": bundle.get("feature_cells", {}),
			"towns": bundle.get("towns", []),
			"entity_spawns": bundle.get("entity_spawns", []),
		},
		"channels": {"channels": bundle.get("channels", {})},
	})
	# Simulate real disk: write JSON, parse floats back.
	var json_text := JSON.stringify(sealed, "\t")
	var parsed = JSON.parse_string(json_text)
	if parsed == null or not parsed is Dictionary:
		_fail("JSON parse failed for sealed save")
		return
	var check: Dictionary = _SaveSchema.validate_and_migrate(parsed)
	if not bool(check.get("ok", false)):
		_fail("disk JSON validate failed: %s" % str(check.get("reason")))
		return
	var data: Dictionary = check.get("data", {})
	_WorldState.replace_active()
	_WorldState.get_active().import_persistence_bundle(data.get("world_state", {}))

	var feat: Dictionary = _FeatureRegistry.get_feature(10, 11)
	if feat.is_empty():
		_fail("JSON path lost feature cell")
	elif not (feat.get("center") is Vector2i):
		_fail("JSON path feature center not Vector2i (got %s)" % [feat.get("center")])
	else:
		var c: Vector2i = feat.center
		if c != Vector2i(10, 11):
			_fail("JSON path feature center wrong %s" % c)

	var spawns: Array = _FeatureRegistry.get_entity_spawns()
	if spawns.is_empty():
		_fail("JSON path lost entity_spawns")
	else:
		var s0: Dictionary = spawns[0]
		if not (s0.get("world_pos") is Vector2i):
			_fail("entity_spawns.world_pos not Vector2i after JSON (got %s)" % [s0.get("world_pos")])
		# get_spawns_in_chunk must not SCRIPT ERROR after JSON load
		var in_chunk: Array = _FeatureRegistry.get_spawns_in_chunk(Vector2i(0, 0), 16)
		var found := false
		for s in in_chunk:
			if s is Dictionary and s.get("world_pos") is Vector2i:
				var p: Vector2i = s.world_pos
				if p == Vector2i(12, 13):
					found = true
		if not found:
			_fail("get_spawns_in_chunk did not find restored animal spawn with Vector2i world_pos")

	var towns: Array = _FeatureRegistry.get_towns()
	if towns.is_empty():
		_fail("JSON path lost towns")
	else:
		var t0: Dictionary = towns[0]
		if not (t0.get("center") is Vector2i):
			_fail("town center not Vector2i after JSON (got %s)" % [t0.get("center")])

	# Codec unit: float pair must restore to Vector2i
	var restored = _SaveCodec.restore_feature_value([10.0, 11.0])
	if not (restored is Vector2i) or restored != Vector2i(10, 11):
		_fail("SaveCodec.restore_feature_value must accept float pairs from JSON.parse")

	print("OK JSON/disk Vector2i roundtrip (features, spawns, towns)")


func _test_deterministic_restore() -> void:
	_WorldState.replace_active()
	_TerrainEdits.dig(1, 2, 1)
	_ChannelRegistry.register_channel(3, 3, Vector2i(1, 0), 0.4)
	var b1: Dictionary = _WorldState.get_active().export_persistence_bundle()
	_WorldState.replace_active()
	_WorldState.get_active().import_persistence_bundle(b1)
	var b2: Dictionary = _WorldState.get_active().export_persistence_bundle()
	if int(b1.get("revision", -1)) != int(b2.get("revision", -2)):
		_fail("deterministic restore revision mismatch")
	if str(b1.get("height_delta", {})) != str(b2.get("height_delta", {})):
		_fail("deterministic height_delta mismatch")
	if str(b1.get("channels", {})) != str(b2.get("channels", {})):
		_fail("deterministic channels mismatch")
	print("OK deterministic restoration")


func _test_checkpoint_rollback() -> void:
	_WorldState.replace_active()
	_TerrainEdits.dig(5, 5, 1)
	var before: Dictionary = _WorldState.get_active().capture_overlay_snapshot()
	_TerrainEdits.dig(5, 5, 1)
	_TerrainEdits.dig(8, 8, 1)
	_WorldState.get_active().restore_overlay_snapshot(before)
	if int(_WorldState.get_active().height_delta.get(Vector2i(8, 8), 0)) != 0:
		_fail("rollback left unexpected edit")
	if int(_WorldState.get_active().height_delta.get(Vector2i(5, 5), 0)) != -1:
		_fail("rollback did not restore prior dig layers")
	print("OK checkpoint rollback")


func _test_integrity_attach() -> void:
	var payload := {
		"schema_version": 2,
		"world_state": {
			"height_delta": {},
			"build_tile": {},
			"channels": {},
		},
		"terrain_edits": {"height_delta": {}, "build_tile": {}},
	}
	var sealed: Dictionary = _SaveSchema.attach_integrity(payload)
	if not sealed.has("checksum"):
		_fail("attach_integrity missing checksum")
	var ok: Dictionary = _SaveSchema.validate_and_migrate(sealed)
	if not bool(ok.get("ok", false)):
		_fail("sealed payload must validate: %s" % str(ok.get("reason")))
	print("OK integrity attach + validate")
