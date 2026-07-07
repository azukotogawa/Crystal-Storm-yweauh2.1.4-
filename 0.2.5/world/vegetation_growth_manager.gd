class_name VegetationGrowthManager
extends Node

const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _PlantableRegistry = preload("res://world/plantable_registry.gd")
const _PlantableDef = preload("res://config/plantable_def.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _StatIds = preload("res://stats/stat_ids.gd")

signal growth_stage_changed(world_pos: Vector2i, plant_id: StringName, stage: int)

var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager
var crystal_manager: CrystalManager
var sim_config: _CrystalSimConfig = _CrystalSimConfig.create_default()

var _growth_cells: Array[Vector2i] = []
var _refresh_timer: float = 0.0


func _enter_tree() -> void:
	add_to_group("vegetation_growth_manager")


func _ready() -> void:
	world = get_tree().get_first_node_in_group("world")
	chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	crystal_manager = get_tree().get_first_node_in_group("crystal_manager")
	_PlantableRegistry.ensure_builtins()
	call_deferred("_bind_config")
	call_deferred("_refresh_growth_index")


func apply_sim_config(cfg: _CrystalSimConfig) -> void:
	if cfg:
		sim_config = cfg


func _bind_config() -> void:
	var cfg_svc = get_tree().get_first_node_in_group("config_service")
	if cfg_svc and cfg_svc.crystal_sim:
		sim_config = cfg_svc.crystal_sim


func register_plant(wx: int, wz: int, plant_id: StringName) -> void:
	var key := Vector2i(wx, wz)
	if key not in _growth_cells:
		_growth_cells.append(key)


func _refresh_growth_index() -> void:
	_growth_cells.clear()
	for key_variant in _FeatureRegistry.get_plant_positions():
		var key: Vector2i = key_variant
		if key not in _growth_cells:
			_growth_cells.append(key)


func _process(delta: float) -> void:
	if _growth_cells.is_empty():
		return

	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 2.5
		_refresh_growth_index()

	for key in _growth_cells.duplicate():
		_tick_plant_growth(key, delta)


func _tick_plant_growth(key: Vector2i, delta: float) -> void:
	var feat: Dictionary = _FeatureRegistry.get_feature(key.x, key.y)
	if feat.is_empty() or not feat.has("plant_id"):
		_growth_cells.erase(key)
		return

	var plant_id: StringName = StringName(str(feat.get("plant_id", "")))
	var def = _PlantableRegistry.get_def(plant_id) as _PlantableDef
	if def == null:
		return

	var stage: int = int(feat.get("growth_stage", 0))
	var mature: int = def.mature_stage()
	if stage >= mature:
		return

	var progress: float = float(feat.get("growth_progress", 0.0))
	var rate_mult := _growth_rate_mult(key, def)
	var plant_speed := _player_plant_speed()
	progress += delta * rate_mult * plant_speed / maxf(def.growth_seconds_per_stage, 0.1)

	if progress < 1.0:
		feat["growth_progress"] = progress
		_FeatureRegistry.register_feature(key.x, key.y, int(feat.get("kind", 0)), feat)
		return

	stage += 1
	feat["growth_stage"] = stage
	feat["growth_progress"] = 0.0
	_FeatureRegistry.register_feature(key.x, key.y, int(feat.get("kind", 0)), feat)
	growth_stage_changed.emit(key, plant_id, stage)

	if world and world.has_method("invalidate_column_cache"):
		world.invalidate_column_cache(key.x, key.y)
	if chunk_manager and chunk_manager.has_method("rebuild_chunk_at_world"):
		chunk_manager.rebuild_chunk_at_world(float(key.x), float(key.y))

	if stage >= mature:
		_growth_cells.erase(key)


func _growth_rate_mult(pos: Vector2i, _def: _PlantableDef) -> float:
	var mult := 1.0
	if world and _ChannelRegistry.is_channel(pos.x, pos.y):
		mult *= sim_config.growth_near_water_bonus
	elif world:
		for dir in _CrystalTypes.NEIGHBOR_DIRS:
			var n: Vector2i = pos + dir
			if _ChannelRegistry.is_channel(n.x, n.y):
				mult *= sim_config.growth_near_water_bonus
				break
			var tile: int = world.get_tile_type(float(n.x), float(n.y))
			if _CrystalTypes.is_water_tile(tile):
				mult *= sim_config.growth_near_water_bonus
				break

	if crystal_manager:
		if crystal_manager.has_crystal_at(pos.x, pos.y):
			mult *= sim_config.growth_near_crystal_penalty
		else:
			var min_depth: float = crystal_manager.sim_config.min_depth if crystal_manager.sim_config else 0.04
			var near_crystal := crystal_manager.get_depth_at(pos.x + 1, pos.y) >= min_depth \
				or crystal_manager.get_depth_at(pos.x - 1, pos.y) >= min_depth \
				or crystal_manager.get_depth_at(pos.x, pos.y + 1) >= min_depth \
				or crystal_manager.get_depth_at(pos.x, pos.y - 1) >= min_depth
			if near_crystal:
				mult *= sim_config.growth_near_crystal_penalty

	return mult


func _player_plant_speed() -> float:
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("get_stat"):
		return maxf(player.get_stat(_StatIds.PLANT_SPEED), 0.1)
	return 1.0