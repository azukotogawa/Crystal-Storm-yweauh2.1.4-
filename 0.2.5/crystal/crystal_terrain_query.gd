class_name CrystalTerrainQuery
extends RefCounted

const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _PlantableRegistry = preload("res://world/plantable_registry.gd")
const _PlantableDef = preload("res://config/plantable_def.gd")
const _BuildingRegistry = preload("res://building/building_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")

var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager
var sim_config: _CrystalSimConfig = _CrystalSimConfig.create_default()


func get_terrain_height(pos: Vector2i) -> float:
	if world == null:
		return 0.0
	if world.has_method("get_surface_height_smooth"):
		return world.get_surface_height_smooth(float(pos.x), float(pos.y))
	return world.get_surface_height(float(pos.x), float(pos.y))


func get_tile(pos: Vector2i) -> int:
	if world == null:
		return VoxelTypes.AIR
	return world.get_tile_type(float(pos.x), float(pos.y))


func is_water_tile(tile_id: int) -> bool:
	return _CrystalTypes.is_water_tile(tile_id)


func apply_sim_config(cfg: _CrystalSimConfig) -> void:
	if cfg:
		sim_config = cfg


func get_flow_factor_at(pos: Vector2i, tile_id: int) -> float:
	var factor := _base_flow_factor(pos, tile_id)
	factor *= _denial_mult_at(pos)
	return clampf(factor, 0.02, 1.0)


func get_channel_flow_mult(from_pos: Vector2i, to_pos: Vector2i) -> float:
	if not _ChannelRegistry.is_channel(from_pos.x, from_pos.y):
		return 1.0

	var flow_dir: Vector2i = _ChannelRegistry.get_flow_dir(from_pos.x, from_pos.y)
	var step: Vector2i = to_pos - from_pos
	if flow_dir == Vector2i.ZERO:
		return 1.0
	if step == flow_dir:
		return sim_config.channel_along_flow_mult
	if step == -flow_dir:
		return sim_config.channel_cross_flow_mult
	return sim_config.channel_cross_flow_mult * 0.85


func get_channel_water_level(pos: Vector2i) -> float:
	return _ChannelRegistry.get_water_level(pos.x, pos.y)


func _base_flow_factor(pos: Vector2i, tile_id: int) -> float:
	if _ChannelRegistry.is_channel(pos.x, pos.y):
		var level: float = _ChannelRegistry.get_water_level(pos.x, pos.y)
		var level_scale := lerpf(0.65, sim_config.channel_water_level_flow_scale, level)
		return sim_config.channel_base_flow_factor * level_scale

	var feat: Dictionary = _FeatureRegistry.get_feature(pos.x, pos.y)
	if feat.has("plant_id"):
		var def = _PlantableRegistry.get_def(StringName(str(feat.plant_id))) as _PlantableDef
		if def:
			var stage: int = int(feat.get("growth_stage", def.mature_stage()))
			return def.flow_factor_for_stage(stage)

	var build_tile: int = _TerrainEdits.get_build_tile(pos.x, pos.y)
	if build_tile >= 0:
		if feat.has("flow_resistance"):
			return 1.0 - clampf(float(feat.flow_resistance), 0.02, 0.98)
		var build_def = _BuildingRegistry.get_def_for_tile(build_tile)
		if build_def:
			return 1.0 - clampf(build_def.flow_resistance, 0.02, 0.98)
		return sim_config.built_wall_flow_factor

	return sim_config.vegetation_flow_factor(tile_id)


func _denial_mult_at(pos: Vector2i) -> float:
	var mult := 1.0
	for plant_pos_variant in _FeatureRegistry.get_plant_positions():
		var plant_pos: Vector2i = plant_pos_variant
		var feat: Dictionary = _FeatureRegistry.get_feature(plant_pos.x, plant_pos.y)
		var plant_id: StringName = StringName(str(feat.get("plant_id", "")))
		var def = _PlantableRegistry.get_def(plant_id) as _PlantableDef
		if def == null or def.denial_radius <= 0:
			continue
		var stage: int = int(feat.get("growth_stage", 0))
		if def.denial_requires_mature and stage < def.mature_stage():
			continue
		var dist: float = Vector2(pos).distance_to(Vector2(plant_pos))
		if dist > float(def.denial_radius) + 0.01:
			continue
		var denial: float = def.mature_denial_flow_factor
		mult = lerpf(mult, denial, 1.0 - sim_config.denial_stack_diminish * 0.5)
	return mult