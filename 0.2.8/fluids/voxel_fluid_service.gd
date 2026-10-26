class_name VoxelFluidService
extends Node

const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _FluidRegistry = preload("res://helpers/fluid_registry.gd")
const _VoxelFluidEngine = preload("res://fluids/voxel_fluid_engine.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _WaterSurface = preload("res://helpers/water_surface.gd")

signal channel_fluid_changed(pos: Vector2i)

var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager
var sim_config: _CrystalSimConfig = _CrystalSimConfig.create_default()

var _water_engine: _VoxelFluidEngine
var _terrain_query: _CrystalTerrainQuery
var _dirty_cells: Dictionary = {}
var _tick_accum: float = 0.0
var _sim_tick_id: int = 0
var _sleeping: bool = true
var _last_tick_us: int = 0
var _last_load_us: int = 0
var _last_subset_size: int = 0
var _last_changed_count: int = 0
var _last_process_us: int = 0
var _last_signal_emits: int = 0
var _last_wet_count: int = 0
var _last_source_count: int = 0


func _ready() -> void:
	var _STP = load("res://systems/startup_total_profiler.gd")
	if _STP and _STP.is_enabled():
		_STP.begin("VoxelFluidService._ready", "synchronous_main")
	add_to_group("voxel_fluid_service")
	world = get_tree().get_first_node_in_group("world")
	chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	_FluidRegistry.ensure_builtins()
	_init_water_engine()
	var cfg_svc = get_tree().get_first_node_in_group("config_service")
	if cfg_svc and cfg_svc.crystal_sim:
		apply_sim_config(cfg_svc.crystal_sim)
	if _STP and _STP.is_enabled():
		_STP.end("VoxelFluidService._ready")


func apply_sim_config(cfg: _CrystalSimConfig) -> void:
	if cfg == null:
		return
	sim_config = cfg
	_FluidRegistry.apply_crystal_config(cfg)
	if _water_engine:
		_water_engine.config = cfg
		_water_engine.fluid_def = _FluidRegistry.get_def(_ChannelRegistry.FLUID_WATER)


func _init_water_engine() -> void:
	_terrain_query = _CrystalTerrainQuery.new()
	_terrain_query.world = world
	_terrain_query.chunk_manager = chunk_manager
	_water_engine = _VoxelFluidEngine.new(
		sim_config, _terrain_query, _FluidRegistry.get_def(_ChannelRegistry.FLUID_WATER)
	)
	_water_engine.is_cell_active = Callable(self, "_is_cell_active")
	_water_engine.max_cells_per_tick = 96


func request_flow(wx: int, wz: int, steps: int = 0) -> void:
	var origin := Vector2i(wx, wz)
	_dirty_cells[origin] = true
	for dir in _CrystalTypes.NEIGHBOR_DIRS:
		_dirty_cells[origin + dir] = true
	var fluid_def = _FluidRegistry.get_def(_ChannelRegistry.FLUID_WATER)
	var step_dt := 1.0 / maxf(fluid_def.update_rate_hz if fluid_def else 10.0, 1.0)
	for _i in steps:
		_tick_water(step_dt)


func _process(delta: float) -> void:
	var t_proc := Time.get_ticks_usec()
	if _water_engine == null:
		return
	_WaterSurface.advance(delta)
	if GameplayInput.world_loading:
		_sleeping = true
		return
	if chunk_manager == null:
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	if world == null:
		world = get_tree().get_first_node_in_group("world")
	var fluid_def = _FluidRegistry.get_def(_ChannelRegistry.FLUID_WATER)
	if fluid_def == null:
		return
	if _dirty_cells.is_empty():
		_sleeping = true
		_tick_accum = 0.0
		return
	_tick_accum += delta
	var step_dt := 1.0 / maxf(fluid_def.update_rate_hz, 1.0)
	if _tick_accum >= step_dt:
		var t0 := Time.get_ticks_usec()
		_tick_water(step_dt)
		_last_tick_us = Time.get_ticks_usec() - t0
		_tick_accum = 0.0
	_last_process_us = Time.get_ticks_usec() - t_proc


func _tick_water(delta: float) -> void:
	if _dirty_cells.is_empty():
		_sleeping = true
		_last_subset_size = 0
		return
	_sleeping = false
	_sim_tick_id += 1
	if _terrain_query:
		_terrain_query.world = world
		_terrain_query.chunk_manager = chunk_manager
		_terrain_query.begin_sim_tick(_sim_tick_id)
	var region: Dictionary = {}
	for key_variant in _dirty_cells.keys():
		var key: Vector2i = key_variant
		region[key] = true
		for dir in _CrystalTypes.NEIGHBOR_DIRS:
			region[key + dir] = true
	_last_subset_size = region.size()
	_water_engine.clear()
	var loaded: Dictionary = region.duplicate()
	for key_variant in region.keys():
		for dir in _CrystalTypes.NEIGHBOR_DIRS:
			loaded[key_variant + dir] = true
	var sources := 0
	for key_variant in loaded.keys():
		var pos: Vector2i = key_variant
		if not _is_cell_active(pos):
			continue
		if _is_natural_water_cell(pos):
			_water_engine.sources[pos] = true
			sources += 1
		elif _ChannelRegistry.has_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER):
			var lvl: int = int(round(_ChannelRegistry.get_water_level(pos.x, pos.y) * float(_VoxelFluidEngine.SOURCE_LEVEL)))
			_water_engine.set_level(pos, clampi(lvl, 1, _VoxelFluidEngine.SOURCE_LEVEL - 1))
	_last_source_count = sources
	_water_engine.set_subset_cells(region.keys())
	var changed: Array = _water_engine.tick_flow(delta)
	_last_changed_count = changed.size()
	var persisted: Array = _persist_changes(changed)
	var next_dirty: Dictionary = {}
	for pos_variant in persisted:
		var pos: Vector2i = pos_variant
		next_dirty[pos] = true
		for dir in _CrystalTypes.NEIGHBOR_DIRS:
			next_dirty[pos + dir] = true
	for pos_variant in _water_engine.leftover:
		next_dirty[pos_variant] = true
	_dirty_cells = next_dirty
	_last_wet_count = _water_engine.cell_count()


func _persist_changes(changed: Array) -> Array:
	var layer: float = maxf(_layer(), 0.001)
	var out: Array = []
	for pos_variant in changed:
		var pos: Vector2i = pos_variant
		if _is_natural_water_cell(pos):
			continue
		var lvl: int = _water_engine.level_at(pos)
		if lvl <= 0:
			continue
		var level: float = float(lvl) / float(_VoxelFluidEngine.SOURCE_LEVEL)
		if not _ChannelRegistry.has_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER):
			_ChannelRegistry.register_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER, Vector2i.ZERO, level)
		else:
			_ChannelRegistry.set_fluid_level(pos.x, pos.y, _ChannelRegistry.FLUID_WATER, level)
		_ChannelRegistry.set_runtime_surface_y(pos.x, pos.y, _visual_bed(pos) + level * layer)
		out.append(pos)
		_emit_water_visual(pos)
	if not out.is_empty() and chunk_manager and chunk_manager.has_method("flush_rebuild_pending"):
		chunk_manager.flush_rebuild_pending()
	_last_signal_emits = out.size()
	return out


func _layer() -> float:
	return _WorldSettings.get_active().layer_height()


func _visual_bed(pos: Vector2i) -> float:
	if _terrain_query:
		return _terrain_query.get_terrain_height(pos)
	return 0.0


func _visual_top(pos: Vector2i) -> float:
	return _visual_bed(pos) + _layer()


func _is_natural_water_cell(pos: Vector2i) -> bool:
	if _TerrainEdits.get_height_delta(pos.x, pos.y) != 0.0:
		return false
	var tile: int = VoxelTypes.AIR
	if _terrain_query:
		tile = _terrain_query.get_tile(pos)
	elif world != null:
		tile = world.get_tile_type(float(pos.x), float(pos.y))
	return _CrystalTypes.is_water_tile(tile)


func _emit_water_visual(pos: Vector2i) -> void:
	channel_fluid_changed.emit(pos)
	if chunk_manager and chunk_manager.has_method("invalidate_columns_at_world"):
		chunk_manager.invalidate_columns_at_world(pos.x, pos.y)


func is_persistent_source(wx: int, wz: int) -> bool:
	return _is_natural_water_cell(Vector2i(wx, wz))


func is_wet_column(wx: int, wz: int) -> bool:
	if _is_natural_water_cell(Vector2i(wx, wz)):
		return true
	return _ChannelRegistry.has_fluid(wx, wz, _ChannelRegistry.FLUID_WATER)


func get_body_surface_y(wx: int, wz: int) -> float:
	if _ChannelRegistry.has_fluid(wx, wz, _ChannelRegistry.FLUID_WATER):
		var sy: float = _ChannelRegistry.get_runtime_surface_y(wx, wz)
		if sy > 0.01:
			return sy
	if _is_natural_water_cell(Vector2i(wx, wz)):
		return _visual_top(Vector2i(wx, wz))
	return 0.0


func _is_cell_active(pos: Vector2i) -> bool:
	if chunk_manager == null:
		return true
	if chunk_manager.has_method("is_world_cell_loaded"):
		return chunk_manager.is_world_cell_loaded(pos.x, pos.y)
	return true


func get_water_engine() -> _VoxelFluidEngine:
	return _water_engine


func get_sim_diagnostics() -> Dictionary:
	var overlay_n := 0
	var ws = load("res://world/world_state.gd").get_active()
	if ws != null and "channels" in ws:
		overlay_n = int((ws.channels as Dictionary).size())
	var depth_n := 0
	if _water_engine:
		depth_n = _water_engine.cell_count()
	return {
		"channel_cells": overlay_n,
		"loaded_channel_cells": _last_subset_size,
		"offscreen_channel_cells": maxi(overlay_n - _last_subset_size, 0),
		"subset_cells": _last_subset_size,
		"engine_depth_cells": depth_n,
		"dirty_cells": _dirty_cells.size(),
		"tick_id": _sim_tick_id,
		"max_cells_per_tick": int(_water_engine.max_cells_per_tick) if _water_engine else 0,
		"active_gate": "dirty_region",
		"loads_all_channels_each_tick": false,
		"sleeping": _sleeping,
		"last_tick_us": _last_tick_us,
		"last_load_us": _last_load_us,
		"last_changed_cells": _last_changed_count,
		"signal_emits": _last_signal_emits,
		"signal_listeners": channel_fluid_changed.get_connections().size(),
		"wet_count": _last_wet_count,
		"source_count": _last_source_count,
	}


func show_channel_level(pos: Vector2i, level: float, surface_y: float) -> void:
	if level < 0.05:
		if _ChannelRegistry.has_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER):
			_ChannelRegistry.unregister_channel(pos.x, pos.y)
		_emit_water_visual(pos)
		return
	if not _ChannelRegistry.has_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER):
		_ChannelRegistry.register_channel(pos.x, pos.y, Vector2i.ZERO, level)
	else:
		_ChannelRegistry.set_water_level(pos.x, pos.y, level)
	var layer: float = _WorldSettings.get_active().layer_height()
	var waterline: float = surface_y + clampf(level, 0.0, 1.0) * layer
	_ChannelRegistry.set_runtime_surface_y(pos.x, pos.y, waterline)
	_emit_water_visual(pos)


func get_water_level_at(wx: int, wz: int) -> float:
	if _ChannelRegistry.has_fluid(wx, wz, _ChannelRegistry.FLUID_WATER):
		return _ChannelRegistry.get_fluid_level(wx, wz, _ChannelRegistry.FLUID_WATER)
	if _is_natural_water_cell(Vector2i(wx, wz)):
		return 1.0
	return 0.0
