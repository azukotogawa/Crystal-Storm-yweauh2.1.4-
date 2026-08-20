extends SceneTree
## Headless proof: generic voxel fluid engine + multi-fluid channel registry.

const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _FluidRegistry = preload("res://helpers/fluid_registry.gd")
const _FluidTypeDef = preload("res://config/fluid_type_def.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _VoxelFluidEngine = preload("res://fluids/voxel_fluid_engine.gd")


func _init() -> void:
	var failed := false
	_ChannelRegistry.reset()
	_TerrainEdits.reset()
	_FluidRegistry.ensure_builtins()

	for path in [
		"res://fluids/voxel_fluid_engine.gd",
		"res://fluids/voxel_fluid_service.gd",
		"res://crystal/crystal_fluid_sim.gd",
		"res://helpers/fluid_registry.gd",
		"res://config/fluid_type_def.gd",
	]:
		var scr: GDScript = load(path) as GDScript
		if scr == null or scr.reload() != OK:
			push_error("FAIL compile %s" % path)
			failed = true
		else:
			print("OK compile ", path)

	failed = _test_fluid_registry() or failed
	failed = _test_multi_fluid_channels() or failed
	failed = _test_water_downhill() or failed
	failed = _test_water_cliff_waterfall() or failed
	failed = _test_water_depression_fill() or failed
	failed = _test_water_equilibrium() or failed
	failed = _test_gravity_preference() or failed
	failed = _test_post_dig_reflow() or failed

	if failed:
		quit(1)
	print("All voxel fluid engine tests OK")
	quit(0)


func _test_fluid_registry() -> bool:
	var failed := false
	for id in [&"water", &"crystal", &"lava", &"poison", &"oil"]:
		var def = _FluidRegistry.get_def(id)
		if def == null:
			push_error("missing fluid def %s" % str(id))
			failed = true
			continue
		if def.spread_speed <= 0.0 or def.viscosity <= 0.0 or def.update_rate_hz <= 0.0:
			push_error("invalid tunables for %s" % str(id))
			failed = true
	if not failed:
		var water = _FluidRegistry.get_def(&"water")
		var crystal = _FluidRegistry.get_def(&"crystal")
		if water.flow_model != _FluidTypeDef.FlowModel.GRAVITY_CHANNEL:
			push_error("water should use GRAVITY_CHANNEL")
			failed = true
		elif crystal.flow_model != _FluidTypeDef.FlowModel.PRESSURE_POOL:
			push_error("crystal should use PRESSURE_POOL")
			failed = true
		else:
			print("OK fluid registry builtins + flow models")
	return failed


func _test_multi_fluid_channels() -> bool:
	_ChannelRegistry.reset()
	_ChannelRegistry.register_fluid(3, 4, _ChannelRegistry.FLUID_WATER, Vector2i(1, 0), 0.6)
	_ChannelRegistry.register_fluid(3, 4, _ChannelRegistry.FLUID_CRYSTAL, Vector2i(0, 1), 0.35)
	if not _ChannelRegistry.has_fluid(3, 4, _ChannelRegistry.FLUID_WATER):
		push_error("water missing on shared cell")
		return true
	if not _ChannelRegistry.has_fluid(3, 4, _ChannelRegistry.FLUID_CRYSTAL):
		push_error("crystal missing on shared cell")
		return true
	if not is_equal_approx(_ChannelRegistry.get_fluid_level(3, 4, _ChannelRegistry.FLUID_WATER), 0.6):
		push_error("water level wrong")
		return true
	if not is_equal_approx(_ChannelRegistry.get_fluid_level(3, 4, _ChannelRegistry.FLUID_CRYSTAL), 0.35):
		push_error("crystal level wrong")
		return true
	_ChannelRegistry.set_fluid_level(3, 4, _ChannelRegistry.FLUID_WATER, 0.2)
	if not is_equal_approx(_ChannelRegistry.get_fluid_level(3, 4, _ChannelRegistry.FLUID_CRYSTAL), 0.35):
		push_error("crystal level changed when water adjusted")
		return true
	print("OK multi-fluid channel registration")
	return false


func _make_water_engine(heights: Dictionary) -> _VoxelFluidEngine:
	var cfg := _CrystalSimConfig.create_default()
	var terrain := _CrystalTerrainQuery.new()
	terrain.test_base_heights = heights
	var engine := _VoxelFluidEngine.new(cfg, terrain, _FluidRegistry.get_def(&"water"))
	engine.empty_cell_inflow_cap = 0.35
	engine.max_cells_per_tick = 64
	return engine


func _test_water_downhill() -> bool:
	var heights: Dictionary = {}
	for x in 8:
		for z in 8:
			heights[Vector2i(x, z)] = 10.0
	heights[Vector2i(4, 4)] = 12.0
	heights[Vector2i(5, 4)] = 8.0
	heights[Vector2i(4, 5)] = 11.0

	var engine := _make_water_engine(heights)
	var source := Vector2i(4, 4)
	var downhill := Vector2i(5, 4)
	var uphill := Vector2i(4, 5)
	engine.set_depth(source, 0.9, -1, false)

	var down_tick := -1
	var up_tick := -1
	for tick in 30:
		engine.tick_flow(0.2)
		if down_tick < 0 and engine.get_depth_at(downhill.x, downhill.y) >= 0.05:
			down_tick = tick
		if up_tick < 0 and engine.get_depth_at(uphill.x, uphill.y) >= 0.05:
			up_tick = tick

	if down_tick < 0:
		push_error("water never reached downhill neighbor")
		return true
	if up_tick >= 0 and down_tick > up_tick:
		push_error("downhill tick=%d should precede uphill tick=%d" % [down_tick, up_tick])
		return true
	var down_depth: float = engine.get_depth_at(downhill.x, downhill.y)
	if down_depth < 0.05:
		push_error("downhill depth too low %.3f" % down_depth)
		return true
	print("OK water downhill preference down_tick=%d depth=%.3f" % [down_tick, down_depth])
	return false


func _test_water_cliff_waterfall() -> bool:
	var heights: Dictionary = {}
	for x in 6:
		for z in 6:
			heights[Vector2i(x, z)] = 10.0
	heights[Vector2i(2, 2)] = 14.0
	heights[Vector2i(3, 2)] = 6.0

	var engine := _make_water_engine(heights)
	engine.set_depth(Vector2i(2, 2), 1.0, -1, false)
	for _i in 20:
		engine.tick_flow(0.25)
	var cliff_depth: float = engine.get_depth_at(3, 2)
	if cliff_depth < 0.08:
		push_error("cliff neighbor should receive waterfall flow depth=%.3f" % cliff_depth)
		return true
	var source_left: float = engine.get_depth_at(2, 2)
	if source_left > 0.85:
		push_error("source should drain over cliff source=%.3f" % source_left)
		return true
	print("OK water cliff waterfall cliff_depth=%.3f source_left=%.3f" % [cliff_depth, source_left])
	return false


func _test_water_depression_fill() -> bool:
	var heights: Dictionary = {}
	for x in 7:
		for z in 7:
			heights[Vector2i(x, z)] = 10.0
	heights[Vector2i(3, 3)] = 7.0
	heights[Vector2i(4, 3)] = 7.0
	heights[Vector2i(3, 4)] = 7.0
	heights[Vector2i(4, 4)] = 7.0

	var engine := _make_water_engine(heights)
	engine.set_depth(Vector2i(2, 3), 0.8, -1, false)
	for _i in 40:
		engine.tick_flow(0.2)

	var filled := 0
	for pos in [Vector2i(3, 3), Vector2i(4, 3), Vector2i(3, 4), Vector2i(4, 4)]:
		if engine.get_depth_at(pos.x, pos.y) >= 0.05:
			filled += 1
	if filled < 2:
		push_error("depression should accumulate water filled=%d" % filled)
		return true
	print("OK water depression fill cells=%d" % filled)
	return false


func _test_water_equilibrium() -> bool:
	var heights: Dictionary = {}
	for x in 5:
		for z in 5:
			heights[Vector2i(x, z)] = 9.0

	var engine := _make_water_engine(heights)
	engine.set_depth(Vector2i(2, 2), 0.5, -1, false)
	for _i in 60:
		engine.tick_flow(0.15)
	var before: float = engine.get_depth_at(2, 2)
	var neighbor_sum := 0.0
	for dir in _CrystalTypes.NEIGHBOR_DIRS:
		var n: Vector2i = Vector2i(2, 2) + dir
		neighbor_sum += engine.get_depth_at(n.x, n.y)
	engine.tick_flow(0.15)
	var after: float = engine.get_depth_at(2, 2)
	var delta: float = absf(after - before)
	if delta > 0.08 and neighbor_sum > 0.05:
		push_error("equilibrium not reached delta=%.3f" % delta)
		return true
	print("OK water equilibrium delta=%.3f" % delta)
	return false


func _test_gravity_preference() -> bool:
	var heights: Dictionary = {}
	for x in 5:
		for z in 5:
			heights[Vector2i(x, z)] = 10.0
	heights[Vector2i(2, 2)] = 12.0
	heights[Vector2i(3, 2)] = 8.0

	var cfg := _CrystalSimConfig.create_default()
	var terrain := _CrystalTerrainQuery.new()
	terrain.test_base_heights = heights

	var low_g_def: _FluidTypeDef = _FluidRegistry.get_def(&"water").duplicate(true)
	low_g_def.gravity_preference = 0.1
	var high_g_def: _FluidTypeDef = _FluidRegistry.get_def(&"water").duplicate(true)
	high_g_def.gravity_preference = 1.0

	var low_engine := _VoxelFluidEngine.new(cfg, terrain, low_g_def)
	low_engine.empty_cell_inflow_cap = 0.35
	var high_engine := _VoxelFluidEngine.new(cfg, terrain, high_g_def)
	high_engine.empty_cell_inflow_cap = 0.35

	low_engine.set_depth(Vector2i(2, 2), 0.9, -1, false)
	high_engine.set_depth(Vector2i(2, 2), 0.9, -1, false)
	low_engine.tick_flow(0.2)
	high_engine.tick_flow(0.2)
	var low_depth: float = low_engine.get_depth_at(3, 2)
	var high_depth: float = high_engine.get_depth_at(3, 2)
	if high_depth <= low_depth:
		push_error("gravity_preference should increase flow high=%.3f low=%.3f" % [high_depth, low_depth])
		return true
	print("OK gravity_preference high=%.3f low=%.3f" % [high_depth, low_depth])
	return false


func _test_post_dig_reflow() -> bool:
	_ChannelRegistry.reset()
	_TerrainEdits.reset()

	var heights: Dictionary = {}
	for x in 6:
		for z in 6:
			heights[Vector2i(x, z)] = 10.0
	heights[Vector2i(3, 3)] = 10.5

	_ChannelRegistry.register_channel(2, 3, Vector2i(1, 0), 0.7)
	_ChannelRegistry.register_channel(3, 3, Vector2i(0, 0), 0.1)

	var cfg := _CrystalSimConfig.create_default()
	var terrain := _CrystalTerrainQuery.new()
	terrain.test_base_heights = heights
	var engine := _VoxelFluidEngine.new(cfg, terrain, _FluidRegistry.get_def(&"water"))
	engine.empty_cell_inflow_cap = 0.35

	var before_dig: float = _ChannelRegistry.get_water_level(3, 3)
	_TerrainEdits.dig(3, 3, 1)

	terrain.begin_sim_tick(1)
	_ChannelRegistry.sync_depth_from_engine(engine)
	var cells: Array = []
	for key in _ChannelRegistry.all_fluid_positions(_ChannelRegistry.FLUID_WATER):
		cells.append(key)
		for dir in _CrystalTypes.NEIGHBOR_DIRS:
			cells.append(key + dir)
	cells.append(Vector2i(3, 3))
	engine.set_subset_cells(cells)

	for _i in 12:
		terrain.begin_sim_tick(_i + 2)
		var changed: Array = engine.tick_flow(0.2)
		for pos_variant in changed:
			var pos: Vector2i = pos_variant
			var level: float = float(engine.depth.get(pos, 0.0))
			if level < 0.05:
				_ChannelRegistry.unregister_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER)
			elif _ChannelRegistry.has_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER):
				_ChannelRegistry.set_fluid_level(pos.x, pos.y, _ChannelRegistry.FLUID_WATER, level)
			elif _ChannelRegistry.is_channel(pos.x, pos.y):
				_ChannelRegistry.set_fluid_level(pos.x, pos.y, _ChannelRegistry.FLUID_WATER, level)

	var after_dig: float = _ChannelRegistry.get_water_level(3, 3)
	var source_after: float = _ChannelRegistry.get_water_level(2, 3)
	if after_dig <= before_dig + 0.02 and source_after >= 0.55:
		push_error("dig should pull water into depression before=%.3f after=%.3f source=%.3f" % [
			before_dig, after_dig, source_after
		])
		return true
	print("OK post-dig local reflow depression=%.3f source=%.3f" % [after_dig, source_after])
	return false