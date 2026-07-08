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

var growth_enabled: bool = true
var growth_hz: float = 4.0
var plants_per_tick: int = 24
var env_check_interval_ticks: int = 4
var index_refresh_interval_sec: float = 8.0

var _growth_keys: Array = []
var _cursor: int = 0
var _growth_accum: float = 0.0
var _index_timer: float = 0.0
var _cached_plant_speed: float = 1.0
var _plant_speed_cache_tick: int = -1
var _env_cache: Dictionary = {}  # Vector2i -> {mult, tick}


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


func apply_performance_config(cfg) -> void:
	if cfg == null:
		return
	growth_enabled = bool(cfg.vegetation_growth_enabled)
	growth_hz = maxf(float(cfg.vegetation_growth_hz), 0.5)
	plants_per_tick = maxi(int(cfg.vegetation_plants_per_tick), 1)
	env_check_interval_ticks = maxi(int(cfg.vegetation_env_check_interval), 1)
	index_refresh_interval_sec = maxf(float(cfg.vegetation_index_refresh_sec), 2.0)
	set_process(growth_enabled)


func _bind_config() -> void:
	var cfg_svc = get_tree().get_first_node_in_group("config_service")
	if cfg_svc and cfg_svc.crystal_sim:
		sim_config = cfg_svc.crystal_sim
	var perf = get_tree().get_first_node_in_group("performance_service")
	if perf and perf.quality:
		apply_performance_config(perf.quality)


func register_plant(wx: int, wz: int, _plant_id: StringName) -> void:
	var key := Vector2i(wx, wz)
	if key not in _growth_keys:
		_growth_keys.append(key)


func _refresh_growth_index() -> void:
	_growth_keys = _FeatureRegistry.get_plant_keys().duplicate()
	_cursor = 0
	_env_cache.clear()


func _process(delta: float) -> void:
	if not growth_enabled:
		return

	_index_timer -= delta
	if _index_timer <= 0.0:
		_index_timer = index_refresh_interval_sec
		_refresh_growth_index()

	if _growth_keys.is_empty():
		return

	_growth_accum += delta
	var step := 1.0 / growth_hz
	var profiler = get_node_or_null("/root/PerfProfiler")
	while _growth_accum >= step:
		if profiler and profiler.has_method("begin"):
			profiler.begin("vegetation_growth")
		_tick_growth_batch(step)
		if profiler and profiler.has_method("end"):
			profiler.end("vegetation_growth")
		_growth_accum -= step


func _tick_growth_batch(batch_delta: float) -> void:
	var tick_id: int = Engine.get_frames_drawn()
	if _plant_speed_cache_tick != tick_id:
		_cached_plant_speed = _player_plant_speed()
		_plant_speed_cache_tick = tick_id

	var budget := mini(plants_per_tick, _growth_keys.size())
	var i := 0
	while i < budget and not _growth_keys.is_empty():
		if _cursor >= _growth_keys.size():
			_cursor = 0
		var key: Vector2i = _growth_keys[_cursor]
		_cursor += 1
		i += 1
		_tick_plant_growth(key, batch_delta, tick_id)


func _tick_plant_growth(key: Vector2i, delta: float, tick_id: int) -> void:
	if chunk_manager and chunk_manager.has_method("is_world_cell_loaded"):
		if not chunk_manager.is_world_cell_loaded(key.x, key.y):
			return
	var feat: Dictionary = _FeatureRegistry.get_feature(key.x, key.y)
	if feat.is_empty() or not feat.has("plant_id"):
		_remove_growth_key(key)
		return

	var plant_id: StringName = StringName(str(feat.get("plant_id", "")))
	var def = _PlantableRegistry.get_def(plant_id) as _PlantableDef
	if def == null:
		return

	var stage: int = int(feat.get("growth_stage", 0))
	var mature: int = def.mature_stage()
	if stage >= mature:
		_remove_growth_key(key)
		return

	var progress: float = float(feat.get("growth_progress", 0.0))
	var rate_mult := _growth_rate_mult_cached(key, def, tick_id)
	progress += delta * rate_mult * _cached_plant_speed / maxf(def.growth_seconds_per_stage, 0.1)

	if progress < 1.0:
		_FeatureRegistry.set_plant_growth_state(key.x, key.y, stage, progress)
		return

	stage += 1
	_FeatureRegistry.set_plant_growth_state(key.x, key.y, stage, 0.0)
	growth_stage_changed.emit(key, plant_id, stage)

	if world and world.has_method("invalidate_column_cache"):
		world.invalidate_column_cache(key.x, key.y)
	if chunk_manager and chunk_manager.has_method("rebuild_chunk_at_world"):
		chunk_manager.rebuild_chunk_at_world(float(key.x), float(key.y))

	if stage >= mature:
		_remove_growth_key(key)
		_env_cache.erase(key)


func _remove_growth_key(key: Vector2i) -> void:
	var idx := _growth_keys.find(key)
	if idx >= 0:
		_growth_keys.remove_at(idx)
		if _cursor > idx:
			_cursor -= 1
		elif _cursor >= _growth_keys.size():
			_cursor = 0


func _growth_rate_mult_cached(pos: Vector2i, _def: _PlantableDef, tick_id: int) -> float:
	var cached: Dictionary = _env_cache.get(pos, {})
	if cached.has("tick") and int(cached.tick) + env_check_interval_ticks > tick_id:
		return float(cached.get("mult", 1.0))

	var mult := _compute_growth_rate_mult(pos)
	_env_cache[pos] = {"mult": mult, "tick": tick_id}
	return mult


func _compute_growth_rate_mult(pos: Vector2i) -> float:
	var mult := 1.0
	if _ChannelRegistry.is_channel(pos.x, pos.y):
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