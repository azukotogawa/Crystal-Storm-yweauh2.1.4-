extends SceneTree

const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _FluidRegistry = preload("res://helpers/fluid_registry.gd")
const _FluidTypeDef = preload("res://config/fluid_type_def.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
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
	failed = _test_water_post_dig_reflow() or failed

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
	var terrain := _CrystalTerrainQuery.new()
	terrain.test_base_heights = heights
	var engine := _VoxelFluidEngine.new(_CrystalSimConfig.create_default(), terrain, _FluidRegistry.get_def(&"water"))
	engine.max_cells_per_tick = 64
	return engine


func _grid(w: int, d: int, h: float) -> Dictionary:
	var heights: Dictionary = {}
	for x in w:
		for z in d:
			heights[Vector2i(x, z)] = h
	return heights


func _test_water_downhill() -> bool:
	var heights := _grid(8, 8, 10.0)
	heights[Vector2i(5, 4)] = 4.0
	var engine := _make_water_engine(heights)
	engine.sources[Vector2i(4, 4)] = true
	engine.set_subset_cells(heights.keys())
	engine.tick_flow(0.1)
	var down: int = engine.level_at(Vector2i(5, 4))
	var side: int = engine.level_at(Vector2i(4, 5))
	if down != 7 or side != 0:
		push_error("FAIL downhill down=%d side=%d" % [down, side])
		return true
	print("OK water falls to the lower neighbour only")
	return false


func _test_water_post_dig_reflow() -> bool:
	_ChannelRegistry.reset()
	_TerrainEdits.reset()
	var heights := _grid(6, 6, 10.0)
	_ChannelRegistry.register_channel(2, 3, Vector2i(1, 0), 0.75)
	var engine := _make_water_engine(heights)
	_ChannelRegistry.sync_depth_from_engine(engine)
	var layer: float = _WorldSettings.get_active().layer_height()
	heights[Vector2i(3, 3)] = 10.0 - layer
	engine.set_subset_cells(heights.keys())
	engine.tick_flow(0.1)
	var level: int = engine.level_at(Vector2i(3, 3))
	if level != 5:
		push_error("FAIL post-dig reflow level=%d want 5" % level)
		return true
	print("OK post-dig reflow level=%d" % level)
	return false