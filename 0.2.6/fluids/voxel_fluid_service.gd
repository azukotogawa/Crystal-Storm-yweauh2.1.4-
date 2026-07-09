class_name VoxelFluidService
extends Node

const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _FluidRegistry = preload("res://helpers/fluid_registry.gd")
const _VoxelFluidEngine = preload("res://fluids/voxel_fluid_engine.gd")

signal channel_fluid_changed(pos: Vector2i)

var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager
var sim_config: _CrystalSimConfig = _CrystalSimConfig.create_default()

var _water_engine: _VoxelFluidEngine
var _terrain_query: _CrystalTerrainQuery
var _dirty_cells: Dictionary = {}
var _tick_accum: float = 0.0
var _sim_tick_id: int = 0


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
	_water_engine = _VoxelFluidEngine.new(sim_config, _terrain_query, _FluidRegistry.get_def(_ChannelRegistry.FLUID_WATER))
	_water_engine.is_cell_active = Callable(self, "_is_cell_active")
	_water_engine.max_cells_per_tick = 96
	_water_engine.empty_cell_inflow_cap = 0.25


func mark_region_dirty(wx: int, wz: int, radius: int = 1) -> void:
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			_dirty_cells[Vector2i(wx + dx, wz + dz)] = true
			var neighbor := Vector2i(wx + dx, wz + dz)
			if _ChannelRegistry.is_channel(neighbor.x, neighbor.y):
				for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					_dirty_cells[neighbor + dir] = true


func recompute_region_now(wx: int, wz: int, radius: int = 1, steps: int = 6) -> void:
	mark_region_dirty(wx, wz, radius)
	var fluid_def = _FluidRegistry.get_def(_ChannelRegistry.FLUID_WATER)
	var step_dt := 1.0 / maxf(fluid_def.update_rate_hz, 1.0)
	for _i in steps:
		_tick_water(step_dt)


func _process(delta: float) -> void:
	if _water_engine == null:
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
		return
	_tick_accum += delta
	var step_dt := 1.0 / maxf(fluid_def.update_rate_hz, 1.0)
	while _tick_accum >= step_dt:
		_tick_water(step_dt)
		_tick_accum -= step_dt


func _tick_water(delta: float) -> void:
	if _dirty_cells.is_empty() and _ChannelRegistry.all_fluid_positions(_ChannelRegistry.FLUID_WATER).is_empty():
		return
	_sim_tick_id += 1
	_terrain_query.begin_sim_tick(_sim_tick_id)
	_load_water_subset()
	var changed: Array = _water_engine.tick_flow(delta)
	_persist_water_changes(changed)
	_dirty_cells.clear()


func _load_water_subset() -> void:
	_water_engine.clear()
	var cells: Array = []
	for key_variant in _ChannelRegistry.all_fluid_positions(_ChannelRegistry.FLUID_WATER):
		var key: Vector2i = key_variant
		var level: float = _ChannelRegistry.get_fluid_level(key.x, key.y, _ChannelRegistry.FLUID_WATER)
		var min_d: float = _water_engine.fluid_def.min_depth if _water_engine.fluid_def else 0.05
		if level >= min_d:
			_water_engine.depth[key] = level
		cells.append(key)
		for dir in _CrystalTypes.NEIGHBOR_DIRS:
			cells.append(key + dir)
	for key_variant in _dirty_cells.keys():
		var key: Vector2i = key_variant
		if key not in cells:
			cells.append(key)
	_water_engine.set_subset_cells(cells)


func _persist_water_changes(changed: Array) -> void:
	for pos_variant in changed:
		var pos: Vector2i = pos_variant
		var level: float = float(_water_engine.depth.get(pos, 0.0))
		var min_d: float = _water_engine.fluid_def.min_depth if _water_engine.fluid_def else 0.05
		if level < min_d:
			if _ChannelRegistry.has_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER):
				_ChannelRegistry.unregister_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER)
		else:
			var flow_dir := _ChannelRegistry.get_flow_dir(pos.x, pos.y, _ChannelRegistry.FLUID_WATER)
			if not _ChannelRegistry.has_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER):
				_ChannelRegistry.register_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER, flow_dir, level)
			else:
				_ChannelRegistry.set_fluid_level(pos.x, pos.y, _ChannelRegistry.FLUID_WATER, level)
		channel_fluid_changed.emit(pos)


func _is_cell_active(pos: Vector2i) -> bool:
	if chunk_manager == null:
		return true
	if chunk_manager.has_method("is_world_cell_loaded"):
		return chunk_manager.is_world_cell_loaded(pos.x, pos.y)
	return true


func get_water_engine() -> _VoxelFluidEngine:
	return _water_engine