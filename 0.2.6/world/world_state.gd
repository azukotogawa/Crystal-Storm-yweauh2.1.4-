class_name WorldState
extends RefCounted
## Canonical session owner for mutable world overlays.
##
## TerrainEdits / FeatureRegistry / ChannelRegistry are public façades that
## delegate storage and mutations here. Worker paths must use frozen snapshots
## (capture_mesh_overlay_snapshot / ChunkData.capture_worker_snapshot), never
## live Dictionary references off the main thread.
##
## Domains:
## - TERRAIN / FEATURE_TILE affect heightfield mesh inputs.
## - FEATURE (meta) covers plants/towns/spawns without forcing mesh invalidation.
## - CHANNEL covers water routing (sim/query; not terrain mesh).

const DOMAIN_NONE := 0
const DOMAIN_TERRAIN := 1
const DOMAIN_FEATURE := 2
const DOMAIN_FEATURE_TILE := 4
const DOMAIN_CHANNEL := 8
## Mesh workers care about terrain height/build tiles and feature tile overrides.
const DOMAIN_MESH_INPUT := DOMAIN_TERRAIN | DOMAIN_FEATURE_TILE

signal changed(domain: int, revision: int)

static var _active = null

## Monotonic global revision (any overlay mutation).
var revision: int = 0
var terrain_revision: int = 0
var feature_revision: int = 0
var feature_tile_revision: int = 0
var channel_revision: int = 0

## TerrainEdits storage (write authority)
var height_delta: Dictionary = {}  # Vector2i -> int (layer deltas)
var build_tile: Dictionary = {}  # Vector2i -> int (VoxelTypes id)

## FeatureRegistry storage
var tile_overrides: Dictionary = {}  # Vector2i -> int
var feature_cells: Dictionary = {}  # Vector2i -> Dictionary
## World-seed stamps (towns/ruins/roads) — immutable content for mesh-plan pristine checks.
## Not player digs/builds/crystal; does not itself force plan rebuild.
var seeded_tile_keys: Dictionary = {}  # Vector2i -> true
var towns: Array = []
var entity_spawns: Array = []
## Session tombstones: baked static vegetation/features removed by dig/absorb/harvest.
## Prevents re-applying baked plants when a chunk becomes resident again.
var feature_cleared: Dictionary = {}  # Vector2i -> true

## ChannelRegistry storage
var channels: Dictionary = {}  # Vector2i -> { water_level, flow_dir }

var _batch_depth: int = 0
var _batch_domains: int = 0


static func get_active():
	if _active == null:
		_active = load("res://world/world_state.gd").new()
	return _active


static func set_active(state) -> void:
	_active = state


static func ensure_active():
	return get_active()


## Replace the active session with a fresh empty state (tests / full reload).
static func replace_active(state = null):
	if state != null:
		_active = state
	else:
		_active = load("res://world/world_state.gd").new()
	_notify_session_changed()
	return _active


static func _notify_session_changed() -> void:
	# FeatureRegistry keeps process-local derived caches; clear on session swap.
	var fr = load("res://world/feature_registry.gd")
	if fr and fr.has_method("on_session_changed"):
		fr.on_session_changed()


func begin_batch() -> void:
	_batch_depth += 1


func end_batch() -> void:
	_batch_depth = maxi(_batch_depth - 1, 0)
	if _batch_depth == 0 and _batch_domains != DOMAIN_NONE:
		var domains: int = _batch_domains
		_batch_domains = DOMAIN_NONE
		_bump_now(domains)


func bump(domain: int) -> void:
	if domain == DOMAIN_NONE:
		return
	if _batch_depth > 0:
		_batch_domains |= domain
		return
	_bump_now(domain)


func _bump_now(domain: int) -> void:
	revision += 1
	if domain & DOMAIN_TERRAIN:
		terrain_revision += 1
	if domain & (DOMAIN_FEATURE | DOMAIN_FEATURE_TILE):
		feature_revision += 1
	if domain & DOMAIN_FEATURE_TILE:
		feature_tile_revision += 1
	if domain & DOMAIN_CHANNEL:
		channel_revision += 1
	changed.emit(domain, revision)


func mesh_input_revision() -> int:
	## Stable combined stamp; both counters are monotonic.
	return terrain_revision * 1_000_003 + feature_tile_revision


func capture_mesh_overlay_stamp() -> Dictionary:
	return {
		"revision": revision,
		"mesh_input_revision": mesh_input_revision(),
		"terrain_revision": terrain_revision,
		"feature_tile_revision": feature_tile_revision,
	}


func is_mesh_stamp_current(stamp: Dictionary) -> bool:
	if stamp.is_empty():
		return false
	return int(stamp.get("mesh_input_revision", -1)) == mesh_input_revision()


## Frozen mesh-input overlay for a rectangular world-column region (inclusive min, exclusive max).
## Copies values so workers never hold live mutable maps.
func capture_mesh_overlay_snapshot(min_wx: int, min_wz: int, max_wx: int, max_wz: int) -> Dictionary:
	var height: Dictionary = {}
	var build: Dictionary = {}
	var tiles: Dictionary = {}
	for wx in range(min_wx, max_wx):
		for wz in range(min_wz, max_wz):
			var key := Vector2i(wx, wz)
			if height_delta.has(key):
				height[key] = int(height_delta[key])
			if build_tile.has(key):
				build[key] = int(build_tile[key])
			if tile_overrides.has(key):
				tiles[key] = int(tile_overrides[key])
	return {
		"stamp": capture_mesh_overlay_stamp(),
		"min_wx": min_wx,
		"min_wz": min_wz,
		"max_wx": max_wx,
		"max_wz": max_wz,
		"height_delta": height,
		"build_tile": build,
		"tile_overrides": tiles,
	}


func capture_overlay_snapshot() -> Dictionary:
	## Full serializable session snapshot for rollback / deterministic restore.
	## Nested entries are deep-copied so the result is immutable w.r.t. later writes.
	return {
		"revision": revision,
		"terrain_revision": terrain_revision,
		"feature_revision": feature_revision,
		"feature_tile_revision": feature_tile_revision,
		"channel_revision": channel_revision,
		"mesh_input_revision": mesh_input_revision(),
		"height_delta": height_delta.duplicate(),
		"build_tile": build_tile.duplicate(),
		"tile_overrides": tile_overrides.duplicate(),
		"feature_cells": feature_cells.duplicate(true),
		"towns": towns.duplicate(true),
		"entity_spawns": entity_spawns.duplicate(true),
		"channels": channels.duplicate(true),
	}


## Restore overlay storage and revision counters from a capture_overlay_snapshot payload.
## Does not emit intermediate change events; emits one combined domain event.
func restore_overlay_snapshot(snap: Dictionary) -> void:
	height_delta = (snap.get("height_delta", {}) as Dictionary).duplicate()
	build_tile = (snap.get("build_tile", {}) as Dictionary).duplicate()
	tile_overrides = (snap.get("tile_overrides", {}) as Dictionary).duplicate()
	feature_cells = (snap.get("feature_cells", {}) as Dictionary).duplicate(true)
	towns = (snap.get("towns", []) as Array).duplicate(true)
	entity_spawns = (snap.get("entity_spawns", []) as Array).duplicate(true)
	channels = (snap.get("channels", {}) as Dictionary).duplicate(true)
	# Preserve captured counters when present so replay/restore is deterministic.
	if snap.has("revision"):
		revision = int(snap.revision)
		terrain_revision = int(snap.get("terrain_revision", 0))
		feature_revision = int(snap.get("feature_revision", 0))
		feature_tile_revision = int(snap.get("feature_tile_revision", 0))
		channel_revision = int(snap.get("channel_revision", 0))
	else:
		_bump_now(DOMAIN_MESH_INPUT | DOMAIN_FEATURE | DOMAIN_CHANNEL)
		_notify_session_changed()
		return
	changed.emit(DOMAIN_MESH_INPUT | DOMAIN_FEATURE | DOMAIN_CHANNEL, revision)
	_notify_session_changed()


func reset_terrain() -> void:
	height_delta.clear()
	build_tile.clear()
	bump(DOMAIN_TERRAIN)


func reset_features() -> void:
	tile_overrides.clear()
	seeded_tile_keys.clear()
	feature_cells.clear()
	feature_cleared.clear()
	towns.clear()
	entity_spawns.clear()
	bump(DOMAIN_FEATURE | DOMAIN_FEATURE_TILE)


func reset_channels() -> void:
	channels.clear()
	bump(DOMAIN_CHANNEL)


func reset_all_overlays() -> void:
	begin_batch()
	height_delta.clear()
	build_tile.clear()
	tile_overrides.clear()
	seeded_tile_keys.clear()
	feature_cells.clear()
	feature_cleared.clear()
	towns.clear()
	entity_spawns.clear()
	channels.clear()
	_batch_domains = DOMAIN_MESH_INPUT | DOMAIN_FEATURE | DOMAIN_CHANNEL
	end_batch()


## JSON-safe full persistence bundle (sole overlay authority for save).
func export_persistence_bundle() -> Dictionary:
	const _Codec = preload("res://systems/save_codec.gd")
	var tiles := {}
	for key_variant in tile_overrides.keys():
		var key: Vector2i = key_variant
		tiles[_Codec.vec2i_key(key)] = int(tile_overrides[key])
	var features := {}
	for key_variant in feature_cells.keys():
		var key: Vector2i = key_variant
		features[_Codec.vec2i_key(key)] = _Codec.sanitize_feature_value(feature_cells[key])
	var encoded_channels := {}
	for key_variant in channels.keys():
		var key: Vector2i = key_variant
		var entry: Dictionary = channels[key]
		var flow_dir: Vector2i = entry.get("flow_dir", Vector2i.ZERO)
		encoded_channels[_Codec.vec2i_key(key)] = {
			"water_level": float(entry.get("water_level", 0.5)),
			"flow_dir": [flow_dir.x, flow_dir.y],
		}
	return {
		"revision": revision,
		"terrain_revision": terrain_revision,
		"feature_revision": feature_revision,
		"feature_tile_revision": feature_tile_revision,
		"channel_revision": channel_revision,
		"mesh_input_revision": mesh_input_revision(),
		"height_delta": _Codec.encode_vec2i_dict(height_delta),
		"build_tile": _Codec.encode_vec2i_dict(build_tile),
		"tile_overrides": tiles,
		"feature_cells": features,
		"towns": _Codec.sanitize_feature_value(towns),
		"entity_spawns": _Codec.sanitize_feature_value(entity_spawns),
		"channels": encoded_channels,
	}


## Restore from export_persistence_bundle (JSON-decoded). Replaces all overlay storage.
func import_persistence_bundle(data: Dictionary) -> void:
	const _Codec = preload("res://systems/save_codec.gd")
	const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
	var snap := {
		"revision": int(data.get("revision", 0)),
		"terrain_revision": int(data.get("terrain_revision", 0)),
		"feature_revision": int(data.get("feature_revision", 0)),
		"feature_tile_revision": int(data.get("feature_tile_revision", 0)),
		"channel_revision": int(data.get("channel_revision", 0)),
		"height_delta": _Codec.decode_vec2i_dict(data.get("height_delta", {})),
		"build_tile": _Codec.decode_vec2i_dict(data.get("build_tile", {})),
		"tile_overrides": {},
		"feature_cells": {},
		"towns": _Codec.restore_feature_value(data.get("towns", [])),
		"entity_spawns": _Codec.restore_feature_value(data.get("entity_spawns", [])),
		"channels": {},
	}
	var tiles: Dictionary = data.get("tile_overrides", {})
	for key in tiles.keys():
		var cell := _Codec.vec2i_from_key(str(key))
		snap.tile_overrides[cell] = int(tiles[key])
	var features: Dictionary = data.get("feature_cells", {})
	for key in features.keys():
		var cell := _Codec.vec2i_from_key(str(key))
		var restored: Dictionary = _Codec.restore_feature_value(features[key])
		if not restored is Dictionary:
			restored = {}
		if not restored.has("kind"):
			restored["kind"] = int(_WorldFeatureTypes.FeatureKind.NONE)
		snap.feature_cells[cell] = restored
	var ch: Dictionary = data.get("channels", {})
	for key in ch.keys():
		var entry: Dictionary = ch[key] if ch[key] is Dictionary else {}
		var flow_arr: Array = entry.get("flow_dir", [0, 0])
		var flow_dir := Vector2i(int(flow_arr[0]), int(flow_arr[1]))
		var cell := _Codec.vec2i_from_key(str(key))
		snap.channels[cell] = {
			"water_level": clampf(float(entry.get("water_level", 0.5)), 0.05, 1.0),
			"flow_dir": _normalize_cardinal(flow_dir),
		}
	if not snap.towns is Array:
		snap.towns = []
	if not snap.entity_spawns is Array:
		snap.entity_spawns = []
	restore_overlay_snapshot(snap)


func export_save_overlays() -> Dictionary:
	var bundle: Dictionary = export_persistence_bundle()
	return {
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
		"channels": {
			"channels": bundle.get("channels", {}),
		},
		"world_state_revision": int(bundle.get("revision", 0)),
		"world_state": bundle,
	}


## Apply legacy flat save-dict fields (terrain_edits/features/channels).
## Prefer import_persistence_bundle for full authority restore with revisions.
func apply_save_overlay_dicts(terrain_data: Dictionary, feature_data: Dictionary, channel_data: Dictionary) -> void:
	var ch_map: Dictionary = channel_data.get("channels", channel_data)
	import_persistence_bundle({
		"revision": revision + 1,
		"terrain_revision": terrain_revision + 1,
		"feature_revision": feature_revision + 1,
		"feature_tile_revision": feature_tile_revision + 1,
		"channel_revision": channel_revision + 1,
		"height_delta": terrain_data.get("height_delta", {}),
		"build_tile": terrain_data.get("build_tile", {}),
		"tile_overrides": feature_data.get("tile_overrides", {}),
		"feature_cells": feature_data.get("feature_cells", {}),
		"towns": feature_data.get("towns", towns),
		"entity_spawns": feature_data.get("entity_spawns", entity_spawns),
		"channels": ch_map,
	})


static func _normalize_cardinal(dir: Vector2i) -> Vector2i:
	if dir == Vector2i.ZERO:
		return Vector2i.ZERO
	if absf(dir.x) >= absf(dir.y):
		return Vector2i(signi(dir.x), 0)
	return Vector2i(0, signi(dir.y))
