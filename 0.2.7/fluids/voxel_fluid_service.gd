class_name VoxelFluidService
extends Node
## Runtime water simulation: gravity channel flow over dug trenches + natural rivers.
## Persists water into ChannelRegistry; crystal uses CrystalFluidSim separately.

const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _FluidRegistry = preload("res://helpers/fluid_registry.gd")
const _VoxelFluidEngine = preload("res://fluids/voxel_fluid_engine.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")

signal channel_fluid_changed(pos: Vector2i)

var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager
var sim_config: _CrystalSimConfig = _CrystalSimConfig.create_default()

var _water_engine: _VoxelFluidEngine
var _terrain_query: _CrystalTerrainQuery
var _dirty_cells: Dictionary = {}
var _tick_accum: float = 0.0
var _sim_tick_id: int = 0
## Natural river/water tiles injected as sources this tick (not force-persisted as channels).
var _river_source_cells: Dictionary = {}
var _sleeping: bool = true
var _last_tick_us: int = 0
var _last_load_us: int = 0
var _last_subset_size: int = 0
var _last_changed_count: int = 0
var _last_gather_us: int = 0
var _last_copy_us: int = 0
var _last_sim_us: int = 0
var _last_persist_us: int = 0
var _last_visual_us: int = 0
var _last_process_us: int = 0
var _last_tile_samples: int = 0
var _last_registry_reads: int = 0
var _last_offscreen_in_subset: int = 0
var _last_signal_emits: int = 0


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
	_water_engine.empty_cell_inflow_cap = 0.25


func mark_region_dirty(wx: int, wz: int, radius: int = 1) -> void:
	# Only registered water expands to neighbors. Natural river tiles are visual
	# sources and must not pull a whole marsh into the gather.
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			var cell := Vector2i(wx + dx, wz + dz)
			_dirty_cells[cell] = true
			if _ChannelRegistry.has_fluid(cell.x, cell.y, _ChannelRegistry.FLUID_WATER):
				for dir in _CrystalTypes.NEIGHBOR_DIRS:
					_dirty_cells[cell + dir] = true


func recompute_region_now(wx: int, wz: int, radius: int = 1, steps: int = 6) -> void:
	mark_region_dirty(wx, wz, radius)
	var fluid_def = _FluidRegistry.get_def(_ChannelRegistry.FLUID_WATER)
	var step_dt := 1.0 / maxf(fluid_def.update_rate_hz if fluid_def else 10.0, 1.0)
	# Cap work during interactive reflow so dig/channel do not freeze the main thread.
	var prev_cap: int = 0
	if _water_engine:
		prev_cap = int(_water_engine.max_cells_per_tick)
		_water_engine.max_cells_per_tick = mini(maxi(prev_cap, 1), 64)
	# Local-only subset: do not scan every fluid cell in the world on each dig.
	_interactive_local_center = Vector2i(wx, wz)
	_interactive_local_radius = maxi(radius + 3, 4)
	_interactive_local_mode = true
	for _i in steps:
		_tick_water(step_dt)
	_interactive_local_mode = false
	if _water_engine:
		_water_engine.max_cells_per_tick = prev_cap


var _interactive_local_mode: bool = false
var _interactive_local_center: Vector2i = Vector2i.ZERO
var _interactive_local_radius: int = 4


func _process(delta: float) -> void:
	var t_proc := Time.get_ticks_usec()
	if _water_engine == null:
		return
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("voxel_fluid")
	if GameplayInput.world_loading:
		_sleeping = true
		_last_process_us = Time.get_ticks_usec() - t_proc
		if profiler and profiler.has_method("end"):
			profiler.end("voxel_fluid")
		return
	if chunk_manager == null:
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	if world == null:
		world = get_tree().get_first_node_in_group("world")
	if _terrain_query:
		_terrain_query.world = world
		_terrain_query.chunk_manager = chunk_manager
	var fluid_def = _FluidRegistry.get_def(_ChannelRegistry.FLUID_WATER)
	if fluid_def == null:
		_last_process_us = Time.get_ticks_usec() - t_proc
		if profiler and profiler.has_method("end"):
			profiler.end("voxel_fluid")
		return
	if _dirty_cells.is_empty():
		_sleeping = true
		_tick_accum = 0.0
		_last_process_us = Time.get_ticks_usec() - t_proc
		if profiler and profiler.has_method("end"):
			profiler.end("voxel_fluid")
		return
	_tick_accum += delta
	var step_dt := 1.0 / maxf(fluid_def.update_rate_hz, 1.0)
	# One gravity step per frame. Extra catch-up was multiplying the gather.
	if _tick_accum >= step_dt:
		var t0 := Time.get_ticks_usec()
		_tick_water(step_dt)
		_last_tick_us = Time.get_ticks_usec() - t0
		if profiler and profiler.has_method("record_func"):
			profiler.record_func("VoxelFluidService::_tick_water", _last_tick_us)
		_tick_accum = 0.0
	_last_process_us = Time.get_ticks_usec() - t_proc
	if profiler and profiler.has_method("end"):
		profiler.end("voxel_fluid")


func _tick_water(delta: float) -> void:
	if _dirty_cells.is_empty() and not _interactive_local_mode:
		_sleeping = true
		return
	_sleeping = false
	_sim_tick_id += 1
	if _terrain_query:
		_terrain_query.begin_sim_tick(_sim_tick_id)
	var t_load := Time.get_ticks_usec()
	_load_water_subset()
	_last_load_us = Time.get_ticks_usec() - t_load
	var t_sim := Time.get_ticks_usec()
	var changed: Array = _water_engine.tick_flow(delta)
	_last_sim_us = Time.get_ticks_usec() - t_sim
	var t_persist := Time.get_ticks_usec()
	_persist_water_changes(changed)
	_last_changed_count = changed.size()
	_advance_dirty_from_changes(changed)
	_last_persist_us = Time.get_ticks_usec() - t_persist
	_river_source_cells.clear()


func _advance_dirty_from_changes(changed: Array) -> void:
	var next_dirty: Dictionary = {}
	for pos_variant in changed:
		var pos: Vector2i = pos_variant
		next_dirty[pos] = true
		for dir in _CrystalTypes.NEIGHBOR_DIRS:
			next_dirty[pos + dir] = true
	_dirty_cells = next_dirty


func _collect_active_region() -> Dictionary:
	var cells: Dictionary = {}
	if _interactive_local_mode:
		var r: int = _interactive_local_radius
		var c0: Vector2i = _interactive_local_center
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				cells[Vector2i(c0.x + dx, c0.y + dz)] = true
	for key_variant in _dirty_cells.keys():
		var key: Vector2i = key_variant
		cells[key] = true
		for dir in _CrystalTypes.NEIGHBOR_DIRS:
			cells[key + dir] = true
	return cells


func _load_water_subset() -> void:
	var t_gather := Time.get_ticks_usec()
	_river_source_cells.clear()
	var cells: Dictionary = _collect_active_region()
	_last_gather_us = Time.get_ticks_usec() - t_gather
	var t_copy := Time.get_ticks_usec()
	_water_engine.clear()
	var min_d: float = _water_engine.fluid_def.min_depth if _water_engine.fluid_def else 0.05
	var tile_n := 0
	var reg_n := 0
	var off_n := 0
	for key_variant in cells.keys():
		var key: Vector2i = key_variant
		var level: float = _ChannelRegistry.get_fluid_level(key.x, key.y, _ChannelRegistry.FLUID_WATER)
		reg_n += 1
		if level >= min_d:
			_water_engine.depth[key] = level
		# River tiles are visual. Inject only a player-registered channel that
		# sits on a river bed — never every dirty river neighbor (marsh blow-up).
		if level >= min_d and _is_natural_water_cell(key):
			tile_n += 1
			_river_source_cells[key] = true
			_water_engine.depth[key] = maxf(level, 0.95)
		if chunk_manager and chunk_manager.has_method("is_world_cell_loaded"):
			if not bool(chunk_manager.is_world_cell_loaded(key.x, key.y)):
				off_n += 1
	_last_subset_size = cells.size()
	_last_tile_samples = tile_n
	_last_registry_reads = reg_n
	_last_offscreen_in_subset = off_n
	_water_engine.set_subset_cells(cells.keys())
	_last_copy_us = Time.get_ticks_usec() - t_copy


func _persist_water_changes(changed: Array) -> void:
	var min_d: float = _water_engine.fluid_def.min_depth if _water_engine.fluid_def else 0.05
	var emits := 0
	var vis_us := 0
	for pos_variant in changed:
		var pos: Vector2i = pos_variant
		# Natural river beds stay sources; don't register/unregister them as player channels.
		if _river_source_cells.has(pos) and _is_natural_water_cell(pos):
			var tv := Time.get_ticks_usec()
			channel_fluid_changed.emit(pos)
			vis_us += Time.get_ticks_usec() - tv
			emits += 1
			continue
		var level: float = float(_water_engine.depth.get(pos, 0.0))
		if level < min_d:
			if _ChannelRegistry.has_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER):
				_ChannelRegistry.unregister_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER)
				var tv2 := Time.get_ticks_usec()
				channel_fluid_changed.emit(pos)
				vis_us += Time.get_ticks_usec() - tv2
				emits += 1
			continue
		var flow_dir := _ChannelRegistry.get_flow_dir(pos.x, pos.y, _ChannelRegistry.FLUID_WATER)
		if flow_dir == Vector2i.ZERO and world != null:
			flow_dir = _ChannelRegistry.compute_downhill_dir(world, pos.x, pos.y)
		if not _ChannelRegistry.has_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER):
			_ChannelRegistry.register_fluid(
				pos.x, pos.y, _ChannelRegistry.FLUID_WATER, flow_dir, level
			)
		else:
			_ChannelRegistry.set_fluid_level(pos.x, pos.y, _ChannelRegistry.FLUID_WATER, level)
		var tv3 := Time.get_ticks_usec()
		channel_fluid_changed.emit(pos)
		vis_us += Time.get_ticks_usec() - tv3
		emits += 1
	_last_visual_us = vis_us
	_last_signal_emits = emits


func _is_natural_water_cell(pos: Vector2i) -> bool:
	if world == null:
		return false
	var tile: int = world.get_tile_type(float(pos.x), float(pos.y))
	return _CrystalTypes.is_water_tile(tile) or tile == _VoxelTypes.RIVER


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
		"max_cells_per_tick": int(_water_engine.max_cells_per_tick) if _water_engine else 0,
		"active_gate": "dirty_region",
		"loads_all_channels_each_tick": false,
		"sleeping": _sleeping,
		"last_tick_us": _last_tick_us,
		"last_load_us": _last_load_us,
		"last_changed_cells": _last_changed_count,
		"phase_us": {
			"process": _last_process_us,
			"gather": _last_gather_us,
			"copy": _last_copy_us,
			"sim": _last_sim_us,
			"persist": maxi(_last_persist_us - _last_visual_us, 0),
			"visual": _last_visual_us,
			"tick_total": _last_tick_us,
		},
		"tile_samples": _last_tile_samples,
		"registry_reads": _last_registry_reads,
		"offscreen_in_subset": _last_offscreen_in_subset,
		"signal_emits": _last_signal_emits,
		"signal_listeners": channel_fluid_changed.get_connections().size(),
	}


func get_water_level_at(wx: int, wz: int) -> float:
	if _ChannelRegistry.has_fluid(wx, wz, _ChannelRegistry.FLUID_WATER):
		return _ChannelRegistry.get_fluid_level(wx, wz, _ChannelRegistry.FLUID_WATER)
	if _is_natural_water_cell(Vector2i(wx, wz)):
		return 1.0
	return 0.0
