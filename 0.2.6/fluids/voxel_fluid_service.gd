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


func _ready() -> void:
	add_to_group("voxel_fluid_service")
	world = get_tree().get_first_node_in_group("world")
	chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	_FluidRegistry.ensure_builtins()
	_init_water_engine()
	var cfg_svc = get_tree().get_first_node_in_group("config_service")
	if cfg_svc and cfg_svc.crystal_sim:
		apply_sim_config(cfg_svc.crystal_sim)


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
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			var cell := Vector2i(wx + dx, wz + dz)
			_dirty_cells[cell] = true
			if _ChannelRegistry.is_channel(cell.x, cell.y) or _is_natural_water_cell(cell):
				for dir in _CrystalTypes.NEIGHBOR_DIRS:
					_dirty_cells[cell + dir] = true


func recompute_region_now(wx: int, wz: int, radius: int = 1, steps: int = 6) -> void:
	mark_region_dirty(wx, wz, radius)
	var fluid_def = _FluidRegistry.get_def(_ChannelRegistry.FLUID_WATER)
	var step_dt := 1.0 / maxf(fluid_def.update_rate_hz if fluid_def else 10.0, 1.0)
	for _i in steps:
		_tick_water(step_dt)


func _process(delta: float) -> void:
	if _water_engine == null:
		return
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("voxel_fluid")
	if chunk_manager == null:
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	if world == null:
		world = get_tree().get_first_node_in_group("world")
	if _terrain_query:
		_terrain_query.world = world
		_terrain_query.chunk_manager = chunk_manager
	var fluid_def = _FluidRegistry.get_def(_ChannelRegistry.FLUID_WATER)
	if fluid_def == null:
		if profiler and profiler.has_method("end"):
			profiler.end("voxel_fluid")
		return
	_tick_accum += delta
	var step_dt := 1.0 / maxf(fluid_def.update_rate_hz, 1.0)
	# Cap steps so a hitch doesn't cascade fluid work.
	var steps := 0
	while _tick_accum >= step_dt and steps < 3:
		var t0 := Time.get_ticks_usec()
		_tick_water(step_dt)
		if profiler and profiler.has_method("record_func"):
			profiler.record_func("VoxelFluidService::_tick_water", Time.get_ticks_usec() - t0)
		_tick_accum -= step_dt
		steps += 1
	if profiler and profiler.has_method("end"):
		profiler.end("voxel_fluid")


func _tick_water(delta: float) -> void:
	var has_water := not _ChannelRegistry.all_fluid_positions(_ChannelRegistry.FLUID_WATER).is_empty()
	if _dirty_cells.is_empty() and not has_water:
		return
	_sim_tick_id += 1
	_terrain_query.begin_sim_tick(_sim_tick_id)
	_load_water_subset()
	var changed: Array = _water_engine.tick_flow(delta)
	_persist_water_changes(changed)
	_dirty_cells.clear()
	_river_source_cells.clear()


func _load_water_subset() -> void:
	_water_engine.clear()
	_river_source_cells.clear()
	var cells: Dictionary = {}
	var min_d: float = _water_engine.fluid_def.min_depth if _water_engine.fluid_def else 0.05

	for key_variant in _ChannelRegistry.all_fluid_positions(_ChannelRegistry.FLUID_WATER):
		var key: Vector2i = key_variant
		var level: float = _ChannelRegistry.get_fluid_level(key.x, key.y, _ChannelRegistry.FLUID_WATER)
		if level >= min_d:
			_water_engine.depth[key] = level
		cells[key] = true
		for dir in _CrystalTypes.NEIGHBOR_DIRS:
			cells[key + dir] = true

	for key_variant in _dirty_cells.keys():
		var key: Vector2i = key_variant
		cells[key] = true
		for dir in _CrystalTypes.NEIGHBOR_DIRS:
			cells[key + dir] = true

	# Rivers flow: inject natural water/river tiles near active cells as gravity sources.
	var seed_keys: Array = cells.keys()
	for key_variant in seed_keys:
		var key: Vector2i = key_variant
		if _is_natural_water_cell(key):
			_river_source_cells[key] = true
			var existing: float = float(_water_engine.depth.get(key, 0.0))
			_water_engine.depth[key] = maxf(existing, 0.95)
			cells[key] = true
			for dir in _CrystalTypes.NEIGHBOR_DIRS:
				cells[key + dir] = true

	_water_engine.set_subset_cells(cells.keys())


func _persist_water_changes(changed: Array) -> void:
	var min_d: float = _water_engine.fluid_def.min_depth if _water_engine.fluid_def else 0.05
	for pos_variant in changed:
		var pos: Vector2i = pos_variant
		# Natural river beds stay sources; don't register/unregister them as player channels.
		if _river_source_cells.has(pos) and _is_natural_water_cell(pos):
			channel_fluid_changed.emit(pos)
			continue
		var level: float = float(_water_engine.depth.get(pos, 0.0))
		if level < min_d:
			if _ChannelRegistry.has_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER):
				_ChannelRegistry.unregister_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER)
				channel_fluid_changed.emit(pos)
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
		channel_fluid_changed.emit(pos)


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


func get_water_level_at(wx: int, wz: int) -> float:
	if _ChannelRegistry.has_fluid(wx, wz, _ChannelRegistry.FLUID_WATER):
		return _ChannelRegistry.get_fluid_level(wx, wz, _ChannelRegistry.FLUID_WATER)
	if _is_natural_water_cell(Vector2i(wx, wz)):
		return 1.0
	return 0.0
