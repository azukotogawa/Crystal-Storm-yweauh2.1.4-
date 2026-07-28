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
## Headless tests: base height per cell when world is null.
var test_base_heights: Dictionary = {}
## Single-sample cached height (faster than smooth bilinear for flow sim).
var use_fast_terrain_height: bool = true

var _cache_tick: int = -1
var _height_cache: Dictionary = {}
var _tile_cache: Dictionary = {}
var _flow_cache: Dictionary = {}
var _channel_mult_cache: Dictionary = {}

## Optional query measurement (CRYSTALSTORM_TERRAIN_QUERY_MEASURE=1).
var _measure_enabled: bool = false
var _height_hits: int = 0
var _height_misses: int = 0
var _tile_hits: int = 0
var _tile_misses: int = 0
var _flow_hits: int = 0
var _flow_misses: int = 0
var _channel_hits: int = 0
var _channel_misses: int = 0
var _ops: Dictionary = {}  # name -> {n, total_us, max_us}
var _callers: Dictionary = {}  # op -> {caller -> count}


func begin_sim_tick(tick_id: int) -> void:
	if _cache_tick == tick_id:
		return
	_cache_tick = tick_id
	_height_cache.clear()
	_tile_cache.clear()
	_flow_cache.clear()
	_channel_mult_cache.clear()


func set_query_measure_enabled(enabled: bool) -> void:
	_measure_enabled = enabled
	if enabled and OS.get_environment("CRYSTALSTORM_TERRAIN_QUERY_MEASURE") != "1":
		# Allow explicit enable from profiler scripts without env.
		pass


func reset_query_stats() -> void:
	_height_hits = 0
	_height_misses = 0
	_tile_hits = 0
	_tile_misses = 0
	_flow_hits = 0
	_flow_misses = 0
	_channel_hits = 0
	_channel_misses = 0
	_ops.clear()
	_callers.clear()


func get_query_stats() -> Dictionary:
	var h_n := _height_hits + _height_misses
	var t_n := _tile_hits + _tile_misses
	var f_n := _flow_hits + _flow_misses
	return {
		"ops": _ops.duplicate(true),
		"callers": _callers.duplicate(true),
		"height_hits": _height_hits,
		"height_misses": _height_misses,
		"height_dups": _height_hits,
		"height_hit_rate": float(_height_hits) / float(maxi(h_n, 1)),
		"tile_hits": _tile_hits,
		"tile_misses": _tile_misses,
		"tile_dups": _tile_hits,
		"tile_hit_rate": float(_tile_hits) / float(maxi(t_n, 1)),
		"flow_hits": _flow_hits,
		"flow_misses": _flow_misses,
		"flow_dups": _flow_hits,
		"flow_hit_rate": float(_flow_hits) / float(maxi(f_n, 1)),
		"channel_hits": _channel_hits,
		"channel_misses": _channel_misses,
		"cache_tick": _cache_tick,
	}


func get_terrain_height(pos: Vector2i) -> float:
	_inc_profiler_frame("terrain_queries")
	var t0 := Time.get_ticks_usec() if _measure_enabled else 0
	if _height_cache.has(pos):
		if _measure_enabled:
			_height_hits += 1
			_record_op("get_terrain_height", t0, "cache_hit")
		return _height_cache[pos]
	if _measure_enabled:
		_height_misses += 1
	var h: float
	if test_base_heights.has(pos):
		h = float(test_base_heights[pos])
		h += _TerrainEdits.get_height_delta(pos.x, pos.y)
	elif world != null:
		if use_fast_terrain_height:
			h = world.get_surface_height(float(pos.x), float(pos.y))
		elif world.has_method("get_surface_height_smooth"):
			h = world.get_surface_height_smooth(float(pos.x), float(pos.y))
		else:
			h = world.get_surface_height(float(pos.x), float(pos.y))
	else:
		h = _TerrainEdits.get_height_delta(pos.x, pos.y)
	_height_cache[pos] = h
	if _measure_enabled:
		_record_op("get_terrain_height", t0, "cache_miss")
	return h


func get_tile(pos: Vector2i) -> int:
	_inc_profiler_frame("terrain_queries")
	if world == null:
		return VoxelTypes.AIR
	var t0 := Time.get_ticks_usec() if _measure_enabled else 0
	if _tile_cache.has(pos):
		if _measure_enabled:
			_tile_hits += 1
			_record_op("get_tile", t0, "cache_hit")
		return _tile_cache[pos]
	if _measure_enabled:
		_tile_misses += 1
	var tile: int = world.get_tile_type(float(pos.x), float(pos.y))
	_tile_cache[pos] = tile
	if _measure_enabled:
		_record_op("get_tile", t0, "cache_miss")
	return tile


func is_water_tile(tile_id: int) -> bool:
	return _CrystalTypes.is_water_tile(tile_id)


func apply_sim_config(cfg: _CrystalSimConfig) -> void:
	if cfg:
		sim_config = cfg


func get_flow_factor_at(pos: Vector2i, tile_id: int) -> float:
	var cache_key: int = pos.x * 73856093 ^ pos.y * 19349663 ^ tile_id * 83492791
	var t0 := Time.get_ticks_usec() if _measure_enabled else 0
	if _flow_cache.has(cache_key):
		if _measure_enabled:
			_flow_hits += 1
			_record_op("get_flow_factor_at", t0, "cache_hit")
		return _flow_cache[cache_key]
	if _measure_enabled:
		_flow_misses += 1
	var factor := _base_flow_factor(pos, tile_id)
	factor *= _denial_mult_at(pos)
	factor = clampf(factor, 0.02, 1.0)
	_flow_cache[cache_key] = factor
	if _measure_enabled:
		_record_op("get_flow_factor_at", t0, "cache_miss")
	return factor


func get_channel_flow_mult(from_pos: Vector2i, to_pos: Vector2i) -> float:
	var key := Vector3i(from_pos.x, from_pos.y, to_pos.x * 17 + to_pos.y)
	var t0 := Time.get_ticks_usec() if _measure_enabled else 0
	if _channel_mult_cache.has(key):
		if _measure_enabled:
			_channel_hits += 1
			_record_op("get_channel_flow_mult", t0, "cache_hit")
		return _channel_mult_cache[key]
	if _measure_enabled:
		_channel_misses += 1
	var mult: float = _channel_flow_mult_uncached(from_pos, to_pos)
	_channel_mult_cache[key] = mult
	if _measure_enabled:
		_record_op("get_channel_flow_mult", t0, "cache_miss")
	return mult


func _channel_flow_mult_uncached(from_pos: Vector2i, to_pos: Vector2i) -> float:
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
	return _FeatureRegistry.get_denial_mult_at(pos.x, pos.y, sim_config.denial_stack_diminish)


func _inc_profiler_frame(counter: String) -> void:
	var tree := Engine.get_main_loop()
	if tree == null or not (tree is SceneTree):
		return
	var profiler: Node = (tree as SceneTree).root.get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("inc_frame"):
		profiler.inc_frame(counter)


func _record_op(op: String, t0_us: int, caller: String = "") -> void:
	if not _measure_enabled:
		return
	var dt := Time.get_ticks_usec() - t0_us
	if not _ops.has(op):
		_ops[op] = {"n": 0, "total_us": 0, "max_us": 0}
	var row: Dictionary = _ops[op]
	row["n"] = int(row["n"]) + 1
	row["total_us"] = int(row["total_us"]) + dt
	row["max_us"] = maxi(int(row["max_us"]), dt)
	if not caller.is_empty():
		if not _callers.has(op):
			_callers[op] = {}
		var cmap: Dictionary = _callers[op]
		cmap[caller] = int(cmap.get(caller, 0)) + 1