class_name FeatureRegistry
extends RefCounted
## Compatibility façade over WorldState feature overlay storage.
## Plant denial caches remain derived local state rebuilt from the authority.

const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _PlantableRegistry = preload("res://world/plantable_registry.gd")
const _PlantableDef = preload("res://config/plantable_def.gd")
const _WorldState = preload("res://world/world_state.gd")

const CHUNK_CELLS := 16

# Central overlay registry for towns, vegetation, and entity spawn points.
# Terrain managers write here; chunk generation and entity systems read from here.

## Derived caches (not authority storage).
static var _plant_keys: Array = []
static var _plant_keys_dirty: bool = true
static var _plant_denial_cache: Array = []
static var _plant_denial_cache_dirty: bool = true
static var _denial_spatial: Dictionary = {}  # Vector2i chunk -> Array[denial entry]
static var _denial_spatial_dirty: bool = true
## Derived ruin-center list (dirty on feature write) + frame-local return cache.
static var _ruin_centers_dirty: bool = true
static var _ruin_centers_list: Array[Vector2i] = []
static var _ruin_centers_frame: int = -1
static var _ruin_centers_frame_cache: Array[Vector2i] = []
static var _ruin_centers_frame_valid: bool = false
## Measurement (optional).
static var _measure_enabled: bool = false
static var _ops: Dictionary = {}
static var _ruin_centers_hits: int = 0
static var _ruin_centers_misses: int = 0
static var _ruin_centers_dups: int = 0


static func _ws():
	return _WorldState.get_active()


static func _invalidate_derived() -> void:
	_plant_keys_dirty = true
	_plant_denial_cache_dirty = true
	_denial_spatial_dirty = true
	_ruin_centers_dirty = true
	_ruin_centers_list.clear()
	_ruin_centers_frame_valid = false
	_ruin_centers_frame_cache.clear()
	_ruin_centers_frame = -1


## Call after WorldState.replace_active / restore so derived caches cannot leak across sessions.
static func on_session_changed() -> void:
	_plant_keys.clear()
	_plant_denial_cache.clear()
	_denial_spatial.clear()
	_invalidate_derived()


static func reset() -> void:
	_ws().reset_features()
	_plant_keys.clear()
	_plant_denial_cache.clear()
	_denial_spatial.clear()
	_invalidate_derived()


static func set_query_measure_enabled(enabled: bool) -> void:
	_measure_enabled = enabled


static func reset_query_stats() -> void:
	_ops.clear()
	_ruin_centers_hits = 0
	_ruin_centers_misses = 0
	_ruin_centers_dups = 0


static func get_query_stats() -> Dictionary:
	return {
		"ops": _ops.duplicate(true),
		"ruin_centers_hits": _ruin_centers_hits,
		"ruin_centers_misses": _ruin_centers_misses,
		"ruin_centers_dups": _ruin_centers_dups,
	}


static func _record_op(op: String, t0_us: int) -> void:
	if not _measure_enabled:
		return
	var dt := Time.get_ticks_usec() - t0_us
	if not _ops.has(op):
		_ops[op] = {"n": 0, "total_us": 0, "max_us": 0}
	var row: Dictionary = _ops[op]
	row["n"] = int(row["n"]) + 1
	row["total_us"] = int(row["total_us"]) + dt
	row["max_us"] = maxi(int(row["max_us"]), dt)


## world_seeded: town/ruin/road stamps that are part of immutable world content for mesh plans.
static func set_tile_override(wx: int, wz: int, voxel_id: int, world_seeded: bool = false) -> void:
	var ws = _ws()
	var key := Vector2i(wx, wz)
	ws.tile_overrides[key] = voxel_id
	if world_seeded:
		ws.seeded_tile_keys[key] = true
	else:
		# Runtime mutation of a tile override is no longer "seeded pristine".
		ws.seeded_tile_keys.erase(key)
	ws.bump(_WorldState.DOMAIN_FEATURE_TILE | _WorldState.DOMAIN_FEATURE)


static func clear_tile_override(wx: int, wz: int) -> void:
	var ws = _ws()
	var key := Vector2i(wx, wz)
	ws.tile_overrides.erase(key)
	ws.seeded_tile_keys.erase(key)
	ws.bump(_WorldState.DOMAIN_FEATURE_TILE | _WorldState.DOMAIN_FEATURE)


static func clear_feature(wx: int, wz: int) -> void:
	var ws = _ws()
	var key := Vector2i(wx, wz)
	if ws.feature_cells.has(key) and ws.feature_cells[key].has("plant_id"):
		_mark_plant_removed(key)
	ws.feature_cells.erase(key)
	# Session tombstone so streamed baked vegetation is not re-installed.
	ws.feature_cleared[key] = true
	_ruin_centers_dirty = true
	_ruin_centers_frame_valid = false
	ws.bump(_WorldState.DOMAIN_FEATURE)


static func get_tile_override(wx: int, wz: int) -> int:
	return int(_ws().tile_overrides.get(Vector2i(wx, wz), -1))


static func register_feature(wx: int, wz: int, kind: int, data: Dictionary = {}) -> void:
	var ws = _ws()
	var key := Vector2i(wx, wz)
	var had_plant: bool = ws.feature_cells.has(key) and ws.feature_cells[key].has("plant_id")
	var entry := data.duplicate()
	entry["kind"] = kind
	var old_stage := int(ws.feature_cells.get(key, {}).get("growth_stage", -1)) if had_plant else -1
	ws.feature_cells[key] = entry
	if ws.feature_cleared.has(key):
		ws.feature_cleared.erase(key)
	if entry.has("plant_id"):
		_plant_keys_dirty = true
		_maybe_invalidate_denial(entry, old_stage)
	# Ruin centers are derived from feature_cells — invalidate on any write.
	_ruin_centers_dirty = true
	_ruin_centers_frame_valid = false
	ws.bump(_WorldState.DOMAIN_FEATURE)


## Install baked static vegetation for one chunk. Skips session-cleared cells and
## cells that already have a WorldState feature (dynamic overlay wins).
## entries: Array of {lx, lz, tile, kind, plant_id, growth_stage, growth_progress, biome?}
static func apply_baked_vegetation_chunk(chunk_coord: Vector2i, entries: Array) -> int:
	if entries.is_empty():
		return 0
	var ws = _ws()
	var installed := 0
	var origin_x: int = chunk_coord.x * CHUNK_CELLS
	var origin_z: int = chunk_coord.y * CHUNK_CELLS
	for item_v in entries:
		var item: Dictionary = item_v
		var lx: int = int(item.get("lx", -1))
		var lz: int = int(item.get("lz", -1))
		if lx < 0 or lz < 0 or lx >= CHUNK_CELLS or lz >= CHUNK_CELLS:
			continue
		var key := Vector2i(origin_x + lx, origin_z + lz)
		if ws.feature_cleared.has(key):
			continue
		if ws.feature_cells.has(key):
			continue
		var tile_id: int = int(item.get("tile", -1))
		if tile_id >= 0 and not ws.tile_overrides.has(key):
			ws.tile_overrides[key] = tile_id
			ws.seeded_tile_keys[key] = true
		var entry: Dictionary = {
			"kind": int(item.get("kind", _WorldFeatureTypes.FeatureKind.NONE)),
			"plant_id": str(item.get("plant_id", "")),
			"growth_stage": int(item.get("growth_stage", 1)),
			"growth_progress": float(item.get("growth_progress", 1.0)),
			"_baked_static": true,
		}
		if item.has("biome"):
			entry["biome"] = str(item.get("biome", ""))
		ws.feature_cells[key] = entry
		installed += 1
	if installed > 0:
		_plant_keys_dirty = true
		_plant_denial_cache_dirty = true
		_denial_spatial_dirty = true
		ws.bump(_WorldState.DOMAIN_FEATURE | _WorldState.DOMAIN_FEATURE_TILE)
	return installed


## In-place growth update — avoids duplicate() + denial rebuild every progress tick.
static func set_plant_growth_state(wx: int, wz: int, stage: int, progress: float) -> void:
	var ws = _ws()
	var key := Vector2i(wx, wz)
	if not ws.feature_cells.has(key):
		return
	var feat: Dictionary = ws.feature_cells[key]
	if not feat.has("plant_id"):
		return
	var old_stage := int(feat.get("growth_stage", 0))
	feat["growth_stage"] = stage
	feat["growth_progress"] = progress
	_maybe_invalidate_denial(feat, old_stage)
	ws.bump(_WorldState.DOMAIN_FEATURE)


static func get_feature(wx: int, wz: int) -> Dictionary:
	return _ws().feature_cells.get(Vector2i(wx, wz), {})


static func get_plant_positions() -> Array:
	return get_plant_keys()


static func get_plant_keys() -> Array:
	if _plant_keys_dirty:
		_rebuild_plant_keys()
	return _plant_keys


static func _rebuild_plant_keys() -> void:
	_plant_keys.clear()
	var cells: Dictionary = _ws().feature_cells
	for key_variant in cells.keys():
		var key: Vector2i = key_variant
		if cells[key].has("plant_id"):
			_plant_keys.append(key)
	_plant_keys_dirty = false


static func _mark_plant_removed(_key: Vector2i) -> void:
	_plant_keys_dirty = true
	_plant_denial_cache_dirty = true
	_denial_spatial_dirty = true


static func _maybe_invalidate_denial(feat: Dictionary, old_stage: int) -> void:
	var plant_id: StringName = StringName(str(feat.get("plant_id", "")))
	var def = _PlantableRegistry.get_def(plant_id) as _PlantableDef
	if def == null or def.denial_radius <= 0:
		return
	var mature := def.mature_stage()
	var new_stage := int(feat.get("growth_stage", 0))
	var was_denial: bool = not def.denial_requires_mature or (old_stage >= mature and old_stage >= 0)
	var is_denial: bool = not def.denial_requires_mature or new_stage >= mature
	if was_denial != is_denial or old_stage < 0:
		_plant_denial_cache_dirty = true
		_denial_spatial_dirty = true


static func get_plant_denial_entries() -> Array:
	if _plant_denial_cache_dirty:
		_rebuild_plant_denial_cache()
	return _plant_denial_cache


static func get_denial_mult_at(wx: int, wz: int, stack_diminish: float = 0.6) -> float:
	if _denial_spatial_dirty or _plant_denial_cache_dirty:
		_rebuild_plant_denial_cache()
	if _plant_denial_cache.is_empty():
		return 1.0
	var cx := _chunk_coord(wx)
	var cz := _chunk_coord(wz)
	var mult := 1.0
	for dcx in range(-1, 2):
		for dcz in range(-1, 2):
			var bucket: Array = _denial_spatial.get(Vector2i(cx + dcx, cz + dcz), [])
			for entry_variant in bucket:
				var entry: Dictionary = entry_variant
				var plant_pos: Vector2i = entry.get("pos", Vector2i.ZERO)
				var radius: float = float(entry.get("radius", 0.0))
				if absf(float(wx - plant_pos.x)) > radius + 1.0:
					continue
				if absf(float(wz - plant_pos.y)) > radius + 1.0:
					continue
				if Vector2(wx, wz).distance_to(Vector2(plant_pos)) > radius + 0.01:
					continue
				var denial: float = float(entry.get("denial", 1.0))
				mult = lerpf(mult, denial, 1.0 - stack_diminish * 0.5)
	return mult


static func _chunk_coord(v: int) -> int:
	return int(floori(float(v) / float(CHUNK_CELLS)))


static func _rebuild_plant_denial_cache() -> void:
	_plant_denial_cache.clear()
	_denial_spatial.clear()
	var cells: Dictionary = _ws().feature_cells
	for key_variant in cells.keys():
		var key: Vector2i = key_variant
		var feat: Dictionary = cells[key]
		if not feat.has("plant_id"):
			continue
		var def = _PlantableRegistry.get_def(StringName(str(feat.plant_id))) as _PlantableDef
		if def == null or def.denial_radius <= 0:
			continue
		var stage: int = int(feat.get("growth_stage", 0))
		if def.denial_requires_mature and stage < def.mature_stage():
			continue
		var entry := {
			"pos": key,
			"radius": float(def.denial_radius),
			"denial": def.mature_denial_flow_factor,
		}
		_plant_denial_cache.append(entry)
		var pchunk := Vector2i(_chunk_coord(key.x), _chunk_coord(key.y))
		var reach: int = int(ceil(float(def.denial_radius) / float(CHUNK_CELLS))) + 1
		for dcx in range(-reach, reach + 1):
			for dcz in range(-reach, reach + 1):
				var ck := Vector2i(pchunk.x + dcx, pchunk.y + dcz)
				if not _denial_spatial.has(ck):
					_denial_spatial[ck] = []
				_denial_spatial[ck].append(entry)
	_plant_denial_cache_dirty = false
	_denial_spatial_dirty = false


static func register_town(center: Vector2i, radius: int, town_name: String) -> void:
	var ws = _ws()
	var town := {
		"center": center,
		"radius": radius,
		"name": town_name,
	}
	ws.towns.append(town)
	ws.begin_batch()
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if Vector2(dx, dz).length() > float(radius):
				continue
			register_feature(center.x + dx, center.y + dz, _WorldFeatureTypes.FeatureKind.TOWN, town)
	# Landmark hall on the existing TOWN_BUILDING visual path (presentation only).
	var hall := town.duplicate()
	hall["town_building"] = "hall"
	register_feature(center.x, center.y, _WorldFeatureTypes.FeatureKind.TOWN_BUILDING, hall)
	ws.end_batch()


static func get_towns() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in _ws().towns:
		out.append(t)
	return out


static func get_ruin_centers() -> Array[Vector2i]:
	var t0 := Time.get_ticks_usec() if _measure_enabled else 0
	var frame := Engine.get_process_frames()
	# Same-frame duplicate: return without rescanning feature_cells.
	if _ruin_centers_frame_valid and _ruin_centers_frame == frame:
		if _measure_enabled:
			_ruin_centers_hits += 1
			_ruin_centers_dups += 1
			_record_op("get_ruin_centers", t0)
		return _ruin_centers_frame_cache.duplicate()
	_ensure_ruin_centers_list()
	_ruin_centers_frame_cache = _ruin_centers_list.duplicate()
	_ruin_centers_frame = frame
	_ruin_centers_frame_valid = true
	if _measure_enabled:
		_ruin_centers_misses += 1
		_record_op("get_ruin_centers", t0)
	return _ruin_centers_frame_cache.duplicate()


static func _ensure_ruin_centers_list() -> void:
	if not _ruin_centers_dirty:
		return
	var found: Dictionary = {}
	var cells: Dictionary = _ws().feature_cells
	for key in cells.keys():
		var feat: Dictionary = cells[key]
		if int(feat.get("kind", 0)) != _WorldFeatureTypes.FeatureKind.RUIN:
			continue
		var center: Vector2i = _coerce_vec2i(feat.get("center", key), key)
		found[center] = true
	var out: Array[Vector2i] = []
	for c in found.keys():
		out.append(c)
	_ruin_centers_list = out
	_ruin_centers_dirty = false


static func register_entity_spawn(wx: int, wz: int, kind: int, animal_kind: int = -1) -> void:
	var ws = _ws()
	var entry := {
		"world_pos": Vector2i(wx, wz),
		"kind": kind,
		"animal_kind": animal_kind,
	}
	ws.entity_spawns.append(entry)
	register_feature(wx, wz, kind, entry)


static func get_entity_spawns() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in _ws().entity_spawns:
		out.append(s)
	return out


static func to_dict() -> Dictionary:
	const _Codec = preload("res://systems/save_codec.gd")
	var ws = _ws()
	var tiles := {}
	for key_variant in ws.tile_overrides.keys():
		var key: Vector2i = key_variant
		tiles[_Codec.vec2i_key(key)] = int(ws.tile_overrides[key])
	var features := {}
	for key_variant in ws.feature_cells.keys():
		var key: Vector2i = key_variant
		features[_Codec.vec2i_key(key)] = _Codec.sanitize_feature_value(ws.feature_cells[key])
	return {
		"tile_overrides": tiles,
		"feature_cells": features,
	}


static func apply_save_overlay(data: Dictionary) -> void:
	const _Codec = preload("res://systems/save_codec.gd")
	var ws = _ws()
	ws.begin_batch()
	var tiles: Dictionary = data.get("tile_overrides", {})
	for key in tiles.keys():
		var cell := _Codec.vec2i_from_key(str(key))
		ws.tile_overrides[cell] = int(tiles[key])
		ws.bump(_WorldState.DOMAIN_FEATURE_TILE | _WorldState.DOMAIN_FEATURE)
	var features: Dictionary = data.get("feature_cells", {})
	for key in features.keys():
		var cell := _Codec.vec2i_from_key(str(key))
		var restored: Dictionary = _Codec.restore_feature_value(features[key])
		var kind: int = int(restored.get("kind", _WorldFeatureTypes.FeatureKind.NONE))
		restored.erase("kind")
		var entry := restored.duplicate()
		entry["kind"] = kind
		ws.feature_cells[cell] = entry
		ws.bump(_WorldState.DOMAIN_FEATURE)
	ws.end_batch()
	_invalidate_derived()


static func _coerce_vec2i(value, fallback: Vector2i) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(int(value.x), int(value.y))
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return fallback


static func get_spawns_in_chunk(chunk_coord: Vector2i, chunk_size: int = 16) -> Array[Dictionary]:
	var min_x := chunk_coord.x * chunk_size
	var min_z := chunk_coord.y * chunk_size
	var max_x := min_x + chunk_size
	var max_z := min_z + chunk_size
	var found: Array[Dictionary] = []
	for spawn_variant in _ws().entity_spawns:
		if not spawn_variant is Dictionary:
			continue
		var spawn: Dictionary = spawn_variant
		# Coerce world_pos after JSON load (may still be Array if codec path skipped).
		var pos: Vector2i = _coerce_vec2i(spawn.get("world_pos", Vector2i.ZERO), Vector2i.ZERO)
		spawn["world_pos"] = pos
		if pos.x >= min_x and pos.x < max_x and pos.y >= min_z and pos.y < max_z:
			found.append(spawn)
	return found
