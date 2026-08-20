class_name BuildingRegistry
extends RefCounted

const _BuildableDef = preload("res://config/buildable_def.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")

static var _defs: Dictionary = {}


static func reset() -> void:
	_defs.clear()


static func register(def: _BuildableDef) -> void:
	if def:
		_defs[def.id] = def


static func register_all(defs: Array) -> void:
	for def in defs:
		if def is _BuildableDef:
			register(def)


static func get_def(id: StringName) -> _BuildableDef:
	return _defs.get(id)


static func get_def_for_tile(tile_id: int) -> _BuildableDef:
	for def in _defs.values():
		if def.tile_id == tile_id:
			return def
	return null


static func get_all() -> Array:
	return _defs.values()


static func ensure_builtins() -> void:
	if not _defs.is_empty():
		return
	register(_make_stone_wall())
	register(_make_wood_wall())
	register(_make_gate())
	register(_make_bridge())


static func _make_stone_wall() -> _BuildableDef:
	var d := _BuildableDef.new()
	d.id = &"stone_wall"
	d.display_name = "Stone Wall"
	d.category = _BuildableDef.Category.TERRAIN_WALL
	d.material_id = "stone"
	d.material_count = 1
	d.wood_fallback_count = 2
	d.tile_id = _VoxelTypes.STONE
	d.height_delta = 1
	d.raises_terrain = true
	d.flow_resistance = 0.85
	d.placement_range = 3.0
	return d


static func _make_wood_wall() -> _BuildableDef:
	var d := _BuildableDef.new()
	d.id = &"wood_wall"
	d.display_name = "Wood Wall"
	d.category = _BuildableDef.Category.TERRAIN_WALL
	d.material_id = "wood"
	d.material_count = 2
	d.tile_id = _VoxelTypes.DIRT
	d.height_delta = 1
	d.raises_terrain = true
	d.flow_resistance = 0.55
	d.placement_range = 3.0
	return d


static func _make_gate() -> _BuildableDef:
	var d := _BuildableDef.new()
	d.id = &"gate"
	d.display_name = "Gate"
	d.category = _BuildableDef.Category.PASSAGE
	d.material_id = "wood"
	d.material_count = 1
	d.wood_fallback_count = 0
	d.tile_id = _VoxelTypes.DIRT
	d.height_delta = 0
	d.raises_terrain = false
	d.is_passage = true
	# Strong baffle while remaining walkable (player passes; crystal crawls).
	d.flow_resistance = 0.72
	d.placement_range = 3.0
	return d


static func _make_bridge() -> _BuildableDef:
	var d := _BuildableDef.new()
	d.id = &"bridge"
	d.display_name = "Bridge"
	d.category = _BuildableDef.Category.BRIDGE
	d.material_id = "wood"
	d.material_count = 1
	d.wood_fallback_count = 0
	d.tile_id = _VoxelTypes.DIRT
	d.height_delta = 1
	d.raises_terrain = true
	d.is_bridge = true
	d.flow_resistance = 0.28
	d.placement_range = 3.0
	return d
