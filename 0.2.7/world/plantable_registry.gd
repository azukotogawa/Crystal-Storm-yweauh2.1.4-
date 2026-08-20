class_name PlantableRegistry
extends RefCounted

const _PlantableDef = preload("res://config/plantable_def.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")

static var _defs: Dictionary = {}


static func reset() -> void:
	_defs.clear()


static func ensure_builtins() -> void:
	if not _defs.is_empty():
		return
	_register(_make_grass())
	_register(_make_tall_grass())
	_register(_make_wildflower())
	_register(_make_fern())
	_register(_make_bush())
	_register(_make_tree())


static func register_all(defs: Array) -> void:
	for def in defs:
		if def is _PlantableDef:
			_register(def)


static func _make_grass() -> _PlantableDef:
	var d := _PlantableDef.new()
	d.id = &"grass_tuft"
	d.display_name = "Grass Patch"
	d.tile_id = VoxelTypes.GRASS_TUFT
	d.feature_kind = _WorldFeatureTypes.FeatureKind.GRASS_PATCH
	d.material_id = "herb"
	d.material_cost = 1
	d.crystal_flow_factor = 0.55
	d.absorb_rate = 0.14
	d.growth_stage_count = 2
	d.growth_seconds_per_stage = 8.0
	d.stage_flow_factors = PackedFloat32Array([0.88, 0.55])
	d.stage_absorb_rates = PackedFloat32Array([0.05, 0.14])
	d.denial_radius = 0
	return d


static func _make_tall_grass() -> _PlantableDef:
	var d := _PlantableDef.new()
	d.id = &"tall_grass"
	d.display_name = "Tall Grass"
	d.tile_id = VoxelTypes.GRASSLAND3
	d.feature_kind = _WorldFeatureTypes.FeatureKind.GRASS_PATCH
	d.material_id = "herb"
	d.material_cost = 1
	d.crystal_flow_factor = 0.5
	d.absorb_rate = 0.11
	d.growth_stage_count = 2
	d.growth_seconds_per_stage = 10.0
	d.stage_flow_factors = PackedFloat32Array([0.9, 0.5])
	d.stage_absorb_rates = PackedFloat32Array([0.04, 0.11])
	d.denial_radius = 0
	return d


static func _make_wildflower() -> _PlantableDef:
	var d := _PlantableDef.new()
	d.id = &"wildflower"
	d.display_name = "Wildflower"
	d.tile_id = VoxelTypes.GRASSLAND2
	d.feature_kind = _WorldFeatureTypes.FeatureKind.GRASS_PATCH
	d.material_id = "herb"
	d.material_cost = 1
	d.crystal_flow_factor = 0.48
	d.absorb_rate = 0.1
	d.growth_stage_count = 2
	d.growth_seconds_per_stage = 12.0
	d.stage_flow_factors = PackedFloat32Array([0.92, 0.48])
	d.stage_absorb_rates = PackedFloat32Array([0.03, 0.1])
	d.denial_radius = 0
	return d


static func _make_fern() -> _PlantableDef:
	var d := _PlantableDef.new()
	d.id = &"fern"
	d.display_name = "Fern"
	d.tile_id = VoxelTypes.HILLS2
	d.feature_kind = _WorldFeatureTypes.FeatureKind.BUSH
	d.material_id = "herb"
	d.material_cost = 2
	d.crystal_flow_factor = 0.42
	d.absorb_rate = 0.08
	d.growth_stage_count = 2
	d.growth_seconds_per_stage = 16.0
	d.stage_flow_factors = PackedFloat32Array([0.88, 0.42])
	d.stage_absorb_rates = PackedFloat32Array([0.03, 0.08])
	d.denial_radius = 1
	return d


static func _make_bush() -> _PlantableDef:
	var d := _PlantableDef.new()
	d.id = &"bush"
	d.display_name = "Bush"
	d.tile_id = VoxelTypes.BUSH
	d.feature_kind = _WorldFeatureTypes.FeatureKind.BUSH
	d.material_id = "herb"
	d.material_cost = 2
	d.crystal_flow_factor = 0.38
	d.absorb_rate = 0.09
	d.growth_stage_count = 3
	d.growth_seconds_per_stage = 14.0
	d.stage_flow_factors = PackedFloat32Array([0.9, 0.62, 0.38])
	d.stage_absorb_rates = PackedFloat32Array([0.04, 0.07, 0.09])
	d.denial_radius = 1
	d.mature_denial_flow_factor = 0.18
	return d


static func _make_tree() -> _PlantableDef:
	var d := _PlantableDef.new()
	d.id = &"tree"
	d.display_name = "Tree"
	d.tile_id = VoxelTypes.TREE_TRUNK
	d.feature_kind = _WorldFeatureTypes.FeatureKind.TREE
	d.material_id = "wood"
	d.material_cost = 3
	d.crystal_flow_factor = 0.22
	d.absorb_rate = 0.05
	d.growth_stage_count = 3
	d.growth_seconds_per_stage = 22.0
	d.stage_flow_factors = PackedFloat32Array([0.92, 0.55, 0.22])
	d.stage_absorb_rates = PackedFloat32Array([0.02, 0.04, 0.05])
	d.denial_radius = 2
	d.mature_denial_flow_factor = 0.1
	return d


static func _register(def: _PlantableDef) -> void:
	_defs[def.id] = def


static func get_def(id: StringName):
	return _defs.get(id)


static func get_def_for_tile(tile_id: int):
	for def in _defs.values():
		if def.tile_id == tile_id:
			return def
	return null


static func get_all() -> Array:
	return _defs.values()