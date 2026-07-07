class_name PlantableRegistry
extends RefCounted

const _PlantableDef = preload("res://config/plantable_def.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")

static var _defs: Dictionary = {}


static func ensure_builtins() -> void:
	if not _defs.is_empty():
		return
	_register(_make(&"grass_tuft", "Grass Patch", VoxelTypes.GRASS_TUFT,
		_WorldFeatureTypes.FeatureKind.GRASS_PATCH, "herb", 1, 0.55))
	_register(_make(&"bush", "Bush", VoxelTypes.BUSH,
		_WorldFeatureTypes.FeatureKind.BUSH, "herb", 2, 0.38))
	_register(_make(&"tree", "Tree", VoxelTypes.TREE_TRUNK,
		_WorldFeatureTypes.FeatureKind.TREE, "wood", 3, 0.22))


static func _make(id: StringName, label: String, tile: int, kind: int, mat: String, cost: int, flow: float) -> _PlantableDef:
	var d := _PlantableDef.new()
	d.id = id
	d.display_name = label
	d.tile_id = tile
	d.feature_kind = kind
	d.material_id = mat
	d.material_cost = cost
	d.crystal_flow_factor = flow
	return d


static func _register(def: _PlantableDef) -> void:
	_defs[def.id] = def


static func get_def(id: StringName):
	return _defs.get(id)


static func get_all() -> Array:
	return _defs.values()