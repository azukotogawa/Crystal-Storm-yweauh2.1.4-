class_name FeatureRegistry
extends RefCounted

const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")

# Central overlay registry for towns, vegetation, and entity spawn points.
# Terrain managers write here; chunk generation and entity systems read from here.

static var _tile_overrides: Dictionary = {}       # Vector2i -> int (VoxelTypes id)
static var _feature_cells: Dictionary = {}        # Vector2i -> { kind, data }
static var _towns: Array[Dictionary] = []
static var _entity_spawns: Array[Dictionary] = []


static func reset() -> void:
	_tile_overrides.clear()
	_feature_cells.clear()
	_towns.clear()
	_entity_spawns.clear()


static func set_tile_override(wx: int, wz: int, voxel_id: int) -> void:
	_tile_overrides[Vector2i(wx, wz)] = voxel_id


static func clear_tile_override(wx: int, wz: int) -> void:
	_tile_overrides.erase(Vector2i(wx, wz))


static func clear_feature(wx: int, wz: int) -> void:
	_feature_cells.erase(Vector2i(wx, wz))


static func get_tile_override(wx: int, wz: int) -> int:
	return int(_tile_overrides.get(Vector2i(wx, wz), -1))


static func register_feature(wx: int, wz: int, kind: int, data: Dictionary = {}) -> void:
	var entry := data.duplicate()
	entry["kind"] = kind
	_feature_cells[Vector2i(wx, wz)] = entry


static func get_feature(wx: int, wz: int) -> Dictionary:
	return _feature_cells.get(Vector2i(wx, wz), {})


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
		var center: Vector2i = feat.get("center", key)
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