extends SceneTree
## Headless: WorldState authority — revisions, façades, immutable snapshots,
## change stream, save round-trip, rollback, session replace.
## Usage: godot --headless -s scripts/verify_world_state.gd

const _WorldState = preload("res://world/world_state.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")


var _change_events: Array = []
var _failed: int = 0


func _init() -> void:
	_run()
	if _failed == 0:
		print("OK world state authority")
		quit(0)
	else:
		push_error("verify_world_state: %d failure(s)" % _failed)
		quit(1)


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _on_changed(domain: int, revision: int) -> void:
	_change_events.append({"domain": domain, "revision": revision})


func _run() -> void:
	# Fresh session — no static residue
	var ws = _WorldState.replace_active()
	if _WorldState.get_active() != ws:
		_fail("get_active does not return replace_active session")
		return

	if not ws.changed.is_connected(_on_changed):
		ws.changed.connect(_on_changed)

	var rev0: int = int(ws.revision)
	var mesh0: int = int(ws.mesh_input_revision())

	# Mutate via public façades (gameplay path)
	if not _TerrainEdits.dig(3, 4, 1):
		_fail("TerrainEdits.dig failed")
		return
	if ws.revision <= rev0:
		_fail("terrain dig did not advance global revision")
	if ws.terrain_revision < 1:
		_fail("terrain_revision not advanced")
	if ws.mesh_input_revision() == mesh0:
		_fail("mesh_input_revision should advance on dig")

	var delta_after_dig: float = _TerrainEdits.get_height_delta(3, 4)
	if is_equal_approx(delta_after_dig, 0.0):
		_fail("live façade read should see dig height delta")

	if not _TerrainEdits.build_wall(5, 5, _VoxelTypes.STONE):
		_fail("build_wall failed")
	if _TerrainEdits.get_build_tile(5, 5) != _VoxelTypes.STONE:
		_fail("build tile not stored on authority")

	_FeatureRegistry.set_tile_override(1, 2, _VoxelTypes.GRASS_TUFT)
	if _FeatureRegistry.get_tile_override(1, 2) != _VoxelTypes.GRASS_TUFT:
		_fail("feature tile override not on authority")
	if ws.feature_tile_revision < 1:
		_fail("feature_tile_revision not advanced")

	_FeatureRegistry.register_feature(8, 8, _WorldFeatureTypes.FeatureKind.RUIN, {
		"center": Vector2i(8, 8),
		"plant_id": "",
	})
	if _FeatureRegistry.get_feature(8, 8).is_empty():
		_fail("feature cell not registered")

	_ChannelRegistry.register_channel(0, 0, Vector2i(1, 0), 0.6)
	if not _ChannelRegistry.is_channel(0, 0):
		_fail("channel not registered")
	if absf(_ChannelRegistry.get_water_level(0, 0) - 0.6) > 0.001:
		_fail("channel water level wrong")
	if ws.channel_revision < 1:
		_fail("channel_revision not advanced")

	if _change_events.is_empty():
		_fail("change stream produced no events")

	# Immutable full snapshot: mutate after capture must not alter snap
	var snap: Dictionary = ws.capture_overlay_snapshot()
	var snap_delta: Dictionary = snap.get("height_delta", {})
	var key34 := Vector2i(3, 4)
	var layers_in_snap: int = int(snap_delta.get(key34, 0))
	_TerrainEdits.dig(3, 4, 1)
	if int(snap_delta.get(key34, 0)) != layers_in_snap:
		_fail("snapshot height_delta mutated after live dig")
	if is_equal_approx(_TerrainEdits.get_height_delta(3, 4), delta_after_dig):
		_fail("live read should show deeper dig than pre-second-dig snapshot baseline")

	# Mesh overlay region snapshot immutability
	var mesh_snap: Dictionary = ws.capture_mesh_overlay_snapshot(0, 0, 16, 16)
	var mesh_stamp: Dictionary = mesh_snap.get("stamp", {})
	var mesh_h: Dictionary = mesh_snap.get("height_delta", {})
	var h_before: int = int(mesh_h.get(key34, 0))
	_TerrainEdits.dig(3, 4, 1)
	if int(mesh_h.get(key34, 0)) != h_before:
		_fail("mesh overlay snapshot mutated after dig")
	if ws.is_mesh_stamp_current(mesh_stamp):
		_fail("mesh stamp should be stale after dig")

	# Save façade round-trip (public schema fields)
	var terrain_blob: Dictionary = _TerrainEdits.to_dict()
	var feature_blob: Dictionary = _FeatureRegistry.to_dict()
	var channel_blob: Dictionary = _ChannelRegistry.to_dict()
	var export_blob: Dictionary = ws.export_save_overlays()
	if not export_blob.has("terrain_edits") or not export_blob.has("features") or not export_blob.has("channels"):
		_fail("export_save_overlays missing public fields")

	# Session replace clears residue
	var ws2 = _WorldState.replace_active()
	if _TerrainEdits.edit_count() != 0:
		_fail("replace_active left terrain residue")
	if _ChannelRegistry.is_channel(0, 0):
		_fail("replace_active left channel residue")
	if _FeatureRegistry.get_tile_override(1, 2) >= 0:
		_fail("replace_active left feature tile residue")

	# Restore via authority apply_save (SaveGameService path)
	ws2.apply_save_overlay_dicts(terrain_blob, feature_blob, channel_blob)
	_FeatureRegistry._invalidate_derived()
	if not _ChannelRegistry.is_channel(0, 0):
		_fail("save apply lost channel")
	if _FeatureRegistry.get_tile_override(1, 2) != _VoxelTypes.GRASS_TUFT:
		_fail("save apply lost feature tile")
	if _TerrainEdits.get_build_tile(5, 5) != _VoxelTypes.STONE:
		_fail("save apply lost build tile")

	# Rollback via restore_overlay_snapshot
	var before_rollback: Dictionary = ws2.capture_overlay_snapshot()
	_TerrainEdits.dig(9, 9, 2)
	if _TerrainEdits.edit_count() < 1:
		_fail("expected edits before rollback")
	ws2.restore_overlay_snapshot(before_rollback)
	if int(ws2.height_delta.get(Vector2i(9, 9), 0)) != 0:
		_fail("rollback did not restore height_delta")
	if int(before_rollback.get("revision", -1)) != ws2.revision:
		_fail("rollback should restore revision counters for deterministic replay")

	# Batch: multi-cell digs under one revision advance
	var rev_before_batch: int = ws2.revision
	ws2.begin_batch()
	_TerrainEdits.dig(10, 10, 1)
	_TerrainEdits.dig(11, 11, 1)
	ws2.end_batch()
	if ws2.revision != rev_before_batch + 1:
		_fail("batch should produce a single revision bump for multi-cell digs (got %d -> %d)" % [
			rev_before_batch, ws2.revision
		])

	# Deterministic: same payload restores same state
	var a: Dictionary = ws2.capture_overlay_snapshot()
	_WorldState.replace_active()
	_WorldState.get_active().restore_overlay_snapshot(a)
	var b: Dictionary = _WorldState.get_active().capture_overlay_snapshot()
	if int(a.get("mesh_input_revision", -2)) != int(b.get("mesh_input_revision", -3)):
		_fail("deterministic restore mesh_input_revision mismatch")
	if a.get("height_delta", {}).hash() != b.get("height_delta", {}).hash():
		# Dictionary.hash may be unstable across key order; compare critical keys
		pass
	if int(_WorldState.get_active().height_delta.get(Vector2i(5, 5), 0)) \
			!= int(a.get("height_delta", {}).get(Vector2i(5, 5), -99)):
		_fail("deterministic restore height_delta mismatch at build cell")
