extends SceneTree


const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _CrystalFluidSim = preload("res://crystal/crystal_fluid_sim.gd")
const _FluidRegistry = preload("res://helpers/fluid_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _VoxelFluidEngine = preload("res://fluids/voxel_fluid_engine.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldState = preload("res://world/world_state.gd")


var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	_ChannelRegistry.reset()
	_TerrainEdits.reset()
	_FluidRegistry.ensure_builtins()

	_test_trench_redirect()
	_test_depression_fill()
	_test_crystal_resists_water()
	_test_flow_dir_bias()

	if _failed == 0:
		print("All water sprint tests OK")
		quit(0)
	else:
		push_error("verify_water_sprint: %d failure(s)" % _failed)
		quit(1)


func _make_water_engine(heights: Dictionary) -> _VoxelFluidEngine:
	var cfg := _CrystalSimConfig.create_default()
	var terrain := _CrystalTerrainQuery.new()
	terrain.test_base_heights = heights
	var engine := _VoxelFluidEngine.new(cfg, terrain, _FluidRegistry.get_def(&"water"))
	engine.empty_cell_inflow_cap = 0.35
	engine.max_cells_per_tick = 96
	return engine


func _test_trench_redirect() -> void:
	_ChannelRegistry.reset()
	_TerrainEdits.reset()
	var heights: Dictionary = {}
	for x in 8:
		for z in 8:
			heights[Vector2i(x, z)] = 10.0
	heights[Vector2i(2, 2)] = 12.0
	heights[Vector2i(3, 2)] = 9.0
	heights[Vector2i(4, 2)] = 8.0
	heights[Vector2i(2, 3)] = 11.5

	_ChannelRegistry.register_channel(2, 2, Vector2i(1, 0), 0.9)
	_ChannelRegistry.register_channel(3, 2, Vector2i(1, 0), 0.1)
	_ChannelRegistry.register_channel(4, 2, Vector2i(1, 0), 0.05)
	_ChannelRegistry.register_channel(2, 3, Vector2i(0, 1), 0.05)

	var engine := _make_water_engine(heights)
	_ChannelRegistry.sync_depth_from_engine(engine)
	var cells: Array = _ChannelRegistry.all_fluid_positions(_ChannelRegistry.FLUID_WATER)
	engine.set_subset_cells(cells)

	for _i in 18:
		var changed: Array = engine.tick_flow(0.2)
		for pos_variant in changed:
			var pos: Vector2i = pos_variant
			var level: float = float(engine.depth.get(pos, 0.0))
			if level < 0.05:
				_ChannelRegistry.unregister_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER)
			elif _ChannelRegistry.has_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER):
				_ChannelRegistry.set_fluid_level(pos.x, pos.y, _ChannelRegistry.FLUID_WATER, level)

	var along: float = _ChannelRegistry.get_water_level(4, 2)
	var cross: float = _ChannelRegistry.get_water_level(2, 3)
	if along < 0.08:
		_fail("trench redirect: water should flow along downhill trench level=%.3f" % along)
	elif cross > along + 0.15:
		_fail("trench redirect: cross-flow %.3f should not dominate along %.3f" % [cross, along])
	else:
		print("OK trench redirect along=%.3f cross=%.3f" % [along, cross])


func _test_depression_fill() -> void:
	print("OK depression fill covered by verify_water_body.gd")


func _test_crystal_resists_water() -> void:
	_ChannelRegistry.reset()
	_TerrainEdits.reset()
	var heights: Dictionary = {}
	for x in 10:
		for z in 5:
			heights[Vector2i(x, z)] = 8.0

	var cfg := _CrystalSimConfig.create_default()
	cfg.pressure_flow_rate = 1.4
	cfg.lateral_spread_bias = 0.02
	cfg.channel_base_flow_factor = 0.1
	cfg.river_flow_factor = 0.06

	var dry := _CrystalTerrainQuery.new()
	dry.test_base_heights = heights
	dry.sim_config = cfg
	var dry_factor: float = dry.get_flow_factor_at(Vector2i(4, 2), _VoxelTypes.GRASS_TUFT)
	var dry_sim := _CrystalFluidSim.new(cfg, dry)
	dry_sim.empty_cell_inflow_cap = 0.2
	dry_sim.set_depth(Vector2i(0, 2), 3.0, 0, false)
	for i in 40:
		dry.begin_sim_tick(i + 1)
		dry_sim.tick_flow(0.25)
	var dry_far: float = dry_sim.get_depth_at(6, 2)

	_ChannelRegistry.register_channel(3, 2, Vector2i(1, 0), 0.9)
	_ChannelRegistry.register_channel(4, 2, Vector2i(1, 0), 0.9)
	_ChannelRegistry.register_channel(5, 2, Vector2i(1, 0), 0.9)

	var wet := _CrystalTerrainQuery.new()
	wet.test_base_heights = heights
	wet.sim_config = cfg
	var wet_factor: float = wet.get_flow_factor_at(Vector2i(4, 2), _VoxelTypes.GRASS_TUFT)
	if wet_factor >= dry_factor * 0.85:
		_fail("crystal should conduct less through water dry=%.3f wet=%.3f" % [dry_factor, wet_factor])
		return

	var wet_sim := _CrystalFluidSim.new(cfg, wet)
	wet_sim.empty_cell_inflow_cap = 0.2
	wet_sim.set_depth(Vector2i(0, 2), 3.0, 0, false)
	for i in 40:
		wet.begin_sim_tick(i + 1)
		wet_sim.tick_flow(0.25)
	var wet_far: float = wet_sim.get_depth_at(6, 2)

	if wet_far > dry_far + 0.08:
		_fail("crystal should spread less across water channel dry_far=%.3f wet_far=%.3f" % [
			dry_far, wet_far
		])
	else:
		print(
			"OK crystal resists water factor dry=%.3f wet=%.3f far dry=%.3f wet=%.3f"
			% [dry_factor, wet_factor, dry_far, wet_far]
		)
	_ChannelRegistry.reset()


func _test_flow_dir_bias() -> void:
	_ChannelRegistry.reset()
	var cfg := _CrystalSimConfig.create_default()
	var terrain := _CrystalTerrainQuery.new()
	var heights: Dictionary = {}
	for x in 5:
		for z in 5:
			heights[Vector2i(x, z)] = 10.0
	terrain.test_base_heights = heights
	terrain.sim_config = cfg

	_ChannelRegistry.register_channel(2, 2, Vector2i(1, 0), 0.7)
	var along: float = terrain.get_channel_flow_mult(Vector2i(2, 2), Vector2i(3, 2))
	var cross: float = terrain.get_channel_flow_mult(Vector2i(2, 2), Vector2i(2, 3))
	if along <= cross:
		_fail("flow_dir bias along=%.3f should exceed cross=%.3f" % [along, cross])
	else:
		print("OK flow_dir bias along=%.3f cross=%.3f" % [along, cross])
