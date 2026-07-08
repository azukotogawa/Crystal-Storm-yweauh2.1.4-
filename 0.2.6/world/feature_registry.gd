class_name FeatureRegistry
extends RefCounted

const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _PlantableRegistry = preload("res://world/plantable_registry.gd")
const _PlantableDef = preload("res://config/plantable_def.gd")

const CHUNK_CELLS := 16

# Central overlay registry for towns, vegetation, and entity spawn points.
# Terrain managers write here; chunk generation and entity systems read from here.

static var _tile_overrides: Dictionary = {}       # Vector2i -> int (VoxelTypes id)
static var _feature_cells: Dictionary = {}        # Vector2i -> { kind, data }
static var _towns: Array[Dictionary] = []
static var _entity_spawns: Array[Dictionary] = []

static var _plant_keys: Array = []
static var _plant_keys_dirty: bool = true
static var _plant_denial_cache: Array = []
static var _plant_denial_cache_dirty: bool = true
static var _denial_spatial: Dictionary = {}        # Vector2i chunk -> Array[denial entry]
static var _denial_spatial_dirty: bool = true


static func reset() -> void:
	_tile_overrides.clear()
	_feature_cells.clear()
	_towns.clear()
	_entity_spawns.clear()
	_plant_keys.clear()
	_plant_keys_dirty = true
	_plant_denial_cache.clear()
	_plant_denial_cache_dirty = true
	_denial_spatial.clear()
	_denial_spatial_dirty = true


static func set_tile_override(wx: int, wz: int, voxel_id: int) -> void:
	_tile_overrides[Vector2i(wx, wz)] = voxel_id


static func clear_tile_override(wx: int, wz: int) -> void:
	_tile_overrides.erase(Vector2i(wx, wz))


static func clear_feature(wx: int, wz: int) -> void:
	var key := Vector2i(wx, wz)
	if _feature_cells.has(key) and _feature_cells[key].has("plant_id"):
		_mark_plant_removed(key)
	_feature_cells.erase(key)


static func get_tile_override(wx: int, wz: int) -> int:
	return int(_tile_overrides.get(Vector2i(wx, wz), -1))


static func register_feature(wx: int, wz: int, kind: int, data: Dictionary = {}) -> void:
	var key := Vector2i(wx, wz)
	var had_plant: bool = _feature_cells.has(key) and _feature_cells[key].has("plant_id")
	var entry := data.duplicate()
	entry["kind"] = kind
	var old_stage := int(_feature_cells.get(key, {}).get("growth_stage", -1)) if had_plant else -1
	_feature_cells[key] = entry
	if entry.has("plant_id"):
		_plant_keys_dirty = true
		_maybe_invalidate_denial(entry, old_stage)


## In-place growth update — avoids duplicate() + denial rebuild every progress tick.
static func set_plant_growth_state(wx: int, wz: int, stage: int, progress: float) -> void:
	var key := Vector2i(wx, wz)
	if not _feature_cells.has(key):
		return
	var feat: Dictionary = _feature_cells[key]
	if not feat.has("plant_id"):
		return
	var old_stage := int(feat.get("growth_stage", 0))
	feat["growth_stage"] = stage
	feat["growth_progress"] = progress
	_maybe_invalidate_denial(feat, old_stage)


static func get_feature(wx: int, wz: int) -> Dictionary:
	return _feature_cells.get(Vector2i(wx, wz), {})


static func get_plant_positions() -> Array:
	return get_plant_keys()


static func get_plant_keys() -> Array:
	if _plant_keys_dirty:
		_rebuild_plant_keys()
	return _plant_keys


static func _rebuild_plant_keys() -> void:
	_plant_keys.clear()
	for key_variant in _feature_cells.keys():
		var key: Vector2i = key_variant
		if _feature_cells[key].has("plant_id"):
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
	for key_variant in _feature_cells.keys():
		var key: Vector2i = key_variant
		var feat: Dictionary = _feature_cells[key]
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
	var town := {
		"center": center,
		"radius": radius,
		"name": town_name,
	}
	_towns.append(town)
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if Vector2(dx, dz).length() > float(radius):
				continue
			register_feature(center.x + dx, center.y + dz, _WorldFeatureTypes.FeatureKind.TOWN, town)


static func get_towns() -> Array[Dictionary]:
	return _towns


static func get_ruin_centers() -> Array[Vector2i]:
	var found: Dictionary = {}
	for key in _feature_cells.keys():
		var feat: Dictionary = _feature_cells[key]
		if int(feat.get("kind", 0)) != _WorldFeatureTypes.FeatureKind.RUIN:
			continue
		var center: Vector2i = _coerce_vec2i(feat.get("center", key), key)
		found[center] = true
	var out: Array[Vector2i] = []
	for c in found.keys():
		out.append(c)
	return out


static func register_entity_spawn(wx: int, wz: int, kind: int, animal_kind: int = -1) -> void:
	var entry := {
		"world_pos": Vector2i(wx, wz),
		"kind": kind,
		"animal_kind": animal_kind,
	}
	_entity_spawns.append(entry)
	register_feature(wx, wz, kind, entry)


static func get_entity_spawns() -> Array[Dictionary]:
	return _entity_spawns


static func to_dict() -> Dictionary:
	const _Codec = preload("res://systems/save_codec.gd")
	var tiles := {}
	for key_variant in _tile_overrides.keys():
		var key: Vector2i = key_variant
		tiles[_Codec.vec2i_key(key)] = int(_tile_overrides[key])
	var features := {}
	for key_variant in _feature_cells.keys():
		var key: Vector2i = key_variant
		features[_Codec.vec2i_key(key)] = _Codec.sanitize_feature_value(_feature_cells[key])
	return {
		"tile_overrides": tiles,
		"feature_cells": features,
	}


static func apply_save_overlay(data: Dictionary) -> void:
	const _Codec = preload("res://systems/save_codec.gd")
	var tiles: Dictionary = data.get("tile_overrides", {})
	for key in tiles.keys():
		var cell := _Codec.vec2i_from_key(str(key))
		set_tile_override(cell.x, cell.y, int(tiles[key]))
	var features: Dictionary = data.get("feature_cells", {})
	for key in features.keys():
		var cell := _Codec.vec2i_from_key(str(key))
		var restored: Dictionary = _Codec.restore_feature_value(features[key])
		var kind: int = int(restored.get("kind", _WorldFeatureTypes.FeatureKind.NONE))
		restored.erase("kind")
		register_feature(cell.x, cell.y, kind, restored)
	_plant_keys_dirty = true
	_plant_denial_cache_dirty = true
	_denial_spatial_dirty = true


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
	for spawn in _entity_spawns:
		var pos: Vector2i = spawn.world_pos
		if pos.x >= min_x and pos.x < max_x and pos.y >= min_z and pos.y < max_z:
			found.append(spawn)
	return found