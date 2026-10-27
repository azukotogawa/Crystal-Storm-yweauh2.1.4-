class_name CrystalCorruption
extends RefCounted

const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _PlantableRegistry = preload("res://world/plantable_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _WorldState = preload("res://world/world_state.gd")

const PHASE_CRYSTAL := "crystal"
const PHASE_SCAR := "scar"

static var _scars: Dictionary = {}
static var _scar_order: Array[Vector2i] = []
static var _cursor: int = 0


static func reset() -> void:
	_scars.clear()
	_scar_order.clear()
	_cursor = 0


static func scar_count() -> int:
	return _scar_order.size()


static func is_corrupted_ground(tile_id: int) -> bool:
	return tile_id == VoxelTypes.CRYSTAL \
		or tile_id == VoxelTypes.CRYSTAL_VEIN \
		or tile_id == VoxelTypes.CRYSTAL_SHARD_GROUND \
		or tile_id == VoxelTypes.CRYSTAL_SCAR


static func ground_variant(pos: Vector2i) -> int:
	var h := absi(pos.x * 73856093 ^ pos.y * 19349663)
	var ids: Array[int] = [
		VoxelTypes.CRYSTAL,
		VoxelTypes.CRYSTAL_VEIN,
		VoxelTypes.CRYSTAL_SHARD_GROUND,
	]
	return ids[h % ids.size()]


static func corrupted_plant_for(plant_id: String) -> String:
	match plant_id:
		"tree", "shard_tree":
			return "shard_tree"
		"bush", "fern", "crystal_bush":
			return "crystal_bush"
		_:
			return "crystal_grass"


static func hostile_for_animal(kind: String) -> String:
	match kind:
		"deer":
			return "crystal_stag"
		"boar":
			return "corrupted_beast"
		"rabbit":
			return "crystal_mite"
		"bird":
			return "crystal_wisp"
		_:
			return ""


static func corrupt_absorbed_cell(pos: Vector2i, tile_id: int, feat: Dictionary) -> bool:
	_PlantableRegistry.ensure_builtins()
	if _blocked(feat) or bool(feat.get("corrupt", false)):
		return false
	var kind := int(feat.get("kind", _WorldFeatureTypes.FeatureKind.NONE))
	var override_id := _FeatureRegistry.get_tile_override(pos.x, pos.y)
	var had_override := override_id >= 0
	var original_tile := override_id if had_override else tile_id
	var entry := feat.duplicate()
	entry["corrupt"] = true
	entry["phase"] = PHASE_CRYSTAL
	entry["original_tile"] = original_tile
	entry["had_override"] = had_override
	entry["biome"] = str(feat.get("biome", ""))
	if kind == _WorldFeatureTypes.FeatureKind.ANIMAL_SPAWN:
		_FeatureRegistry.register_feature(pos.x, pos.y, kind, entry)
		_FeatureRegistry.set_tile_override(pos.x, pos.y, ground_variant(pos))
		return true
	var plant := str(feat.get("plant_id", ""))
	if plant != "":
		entry["original_plant"] = plant
		entry["original_stage"] = int(feat.get("growth_stage", 0))
		entry["original_kind"] = kind
		var next := corrupted_plant_for(plant)
		entry["plant_id"] = next
		var def = _PlantableRegistry.get_def(StringName(next))
		if def:
			kind = int(def.feature_kind)
	else:
		entry["marker"] = true
	_FeatureRegistry.register_feature(pos.x, pos.y, kind, entry)
	_FeatureRegistry.set_tile_override(pos.x, pos.y, ground_variant(pos))
	return true


static func begin_scar(pos: Vector2i, heal_seconds: float) -> void:
	var feat := _FeatureRegistry.get_feature(pos.x, pos.y)
	if _blocked(feat):
		return
	var seconds := maxf(heal_seconds, 0.05)
	var entry := feat.duplicate()
	if not bool(entry.get("corrupt", false)):
		var override_id := _FeatureRegistry.get_tile_override(pos.x, pos.y)
		entry["had_override"] = override_id >= 0
		entry["original_tile"] = override_id if override_id >= 0 else int(VoxelTypes.GRASSLAND)
		var plant := str(entry.get("plant_id", ""))
		if plant != "":
			entry["original_plant"] = plant
			entry["original_stage"] = int(entry.get("growth_stage", 0))
			entry["original_kind"] = int(entry.get("kind", _WorldFeatureTypes.FeatureKind.GRASS_PATCH))
		else:
			entry["marker"] = true
		entry["corrupt"] = true
	entry["phase"] = PHASE_SCAR
	entry["scar_left"] = seconds
	if entry.has("plant_id"):
		entry.erase("plant_id")
	var kind := int(entry.get("kind", _WorldFeatureTypes.FeatureKind.NONE))
	_FeatureRegistry.register_feature(pos.x, pos.y, kind, entry)
	_FeatureRegistry.set_tile_override(pos.x, pos.y, VoxelTypes.CRYSTAL_SCAR)
	_scars[pos] = seconds
	if not _scar_order.has(pos):
		_scar_order.append(pos)


static func has_scar(pos: Vector2i) -> bool:
	return _scars.has(pos)


static func tick_scars(delta: float, budget: int = 8) -> Array:
	var healed: Array[Vector2i] = []
	if _scar_order.is_empty() or budget <= 0 or delta <= 0.0:
		return healed
	var steps := mini(budget, _scar_order.size())
	var i := 0
	while i < steps and not _scar_order.is_empty():
		if _cursor >= _scar_order.size():
			_cursor = 0
		var pos: Vector2i = _scar_order[_cursor]
		var left := float(_scars.get(pos, 0.0)) - delta
		if left <= 0.0:
			_heal_cell(pos)
			_scar_order.remove_at(_cursor)
			healed.append(pos)
		else:
			_scars[pos] = left
			var live := _FeatureRegistry.get_feature(pos.x, pos.y)
			if not live.is_empty():
				live["scar_left"] = left
			_cursor += 1
		i += 1
	return healed


static func reindex_scars() -> void:
	_scars.clear()
	_scar_order.clear()
	_cursor = 0
	var ws = _WorldState.get_active()
	if ws == null:
		return
	for key_v in ws.feature_cells.keys():
		var key: Vector2i = key_v
		var feat: Dictionary = ws.feature_cells[key]
		if str(feat.get("phase", "")) != PHASE_SCAR:
			continue
		_scars[key] = float(feat.get("scar_left", 0.0))
		_scar_order.append(key)


static func _blocked(feat: Dictionary) -> bool:
	if bool(feat.get("player_built", false)):
		return true
	var kind := int(feat.get("kind", -1))
	return kind == _WorldFeatureTypes.FeatureKind.RUIN \
		or kind == _WorldFeatureTypes.FeatureKind.TOWN \
		or kind == _WorldFeatureTypes.FeatureKind.TOWN_BUILDING


static func _heal_cell(pos: Vector2i) -> void:
	var feat := _FeatureRegistry.get_feature(pos.x, pos.y)
	var original_tile := int(feat.get("original_tile", VoxelTypes.GRASSLAND))
	if bool(feat.get("had_override", false)):
		_FeatureRegistry.set_tile_override(pos.x, pos.y, original_tile)
	else:
		_FeatureRegistry.clear_tile_override(pos.x, pos.y)
	var plant := str(feat.get("original_plant", ""))
	if plant != "":
		var kind := int(feat.get("original_kind", _WorldFeatureTypes.FeatureKind.GRASS_PATCH))
		var restored := {
			"plant_id": plant,
			"growth_stage": 0,
			"growth_progress": 0.0,
		}
		var biome := str(feat.get("biome", ""))
		if biome != "":
			restored["biome"] = biome
		_FeatureRegistry.register_feature(pos.x, pos.y, kind, restored)
	elif bool(feat.get("marker", false)):
		# Drop the scar marker without a tombstone so baked plants can return.
		_drop_feature_allow_regrowth(pos)
	elif not feat.is_empty():
		var kept := feat.duplicate()
		for key in [
			"corrupt", "phase", "scar_left", "original_tile", "had_override",
			"original_plant", "original_stage", "original_kind", "marker",
		]:
			kept.erase(key)
		var kind := int(kept.get("kind", _WorldFeatureTypes.FeatureKind.NONE))
		kept.erase("kind")
		_FeatureRegistry.register_feature(pos.x, pos.y, kind, kept)
	_scars.erase(pos)


static func _drop_feature_allow_regrowth(pos: Vector2i) -> void:
	var ws = _WorldState.get_active()
	if ws == null:
		return
	ws.feature_cells.erase(pos)
	ws.feature_cleared.erase(pos)
	ws.bump(_WorldState.DOMAIN_FEATURE)
