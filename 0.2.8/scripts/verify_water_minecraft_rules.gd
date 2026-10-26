extends SceneTree

const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _FluidRegistry = preload("res://helpers/fluid_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _VoxelFluidEngine = preload("res://fluids/voxel_fluid_engine.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const BASE := 10.0
const BUDGET := 24

var _failed := 0
var _layer := 1.0
var _sim_tick := 0


func _init() -> void:
	_TerrainEdits.reset()
	_FluidRegistry.ensure_builtins()
	_layer = _WorldSettings.get_active().layer_height()
	_test_fall()
	_test_spread_distance()
	_test_no_uphill()
	_test_dig_next_to_water()
	_test_sources_never_drain()
	_test_budget()
	if _failed > 0:
		push_error("verify_water_minecraft_rules: %d failure(s)" % _failed)
		quit(1)
		return
	print("All water minecraft rules tests OK")
	quit(0)


func _check(ok: bool, pass_line: String, fail_line: String) -> void:
	if ok:
		print("PASS ", pass_line)
	else:
		_failed += 1
		push_error("FAIL " + fail_line)


func _flat(w: int, d: int) -> Dictionary:
	var heights: Dictionary = {}
	for x in w:
		for z in d:
			heights[Vector2i(x, z)] = BASE
	return heights


func _engine(heights: Dictionary, sources: Array, budget: int = 0) -> _VoxelFluidEngine:
	var terrain := _CrystalTerrainQuery.new()
	terrain.test_base_heights = heights
	var engine := _VoxelFluidEngine.new(_CrystalSimConfig.create_default(), terrain, _FluidRegistry.get_def(&"water"))
	engine.max_cells_per_tick = budget
	for pos in sources:
		engine.sources[pos] = true
	return engine


func _run(engine: _VoxelFluidEngine, heights: Dictionary, ticks: int) -> int:
	var worst := 0
	var work: Array = heights.keys()
	for tick in ticks:
		_sim_tick += 1
		engine.terrain.begin_sim_tick(_sim_tick)
		engine.set_subset_cells(work)
		var changed: Array = engine.tick_flow(0.1)
		worst = maxi(worst, engine.last_processed)
		var next: Dictionary = {}
		for pos_variant in engine.leftover:
			next[pos_variant] = true
		for pos_variant in changed:
			var pos: Vector2i = pos_variant
			next[pos] = true
			for dir in _CrystalTypes.NEIGHBOR_DIRS:
				next[pos + dir] = true
		for key in heights.keys():
			if engine.level_at(key) > 0:
				next[key] = true
		work = next.keys()
	return worst


func _test_fall() -> void:
	var heights := _flat(9, 9)
	heights[Vector2i(5, 4)] = BASE - 2.0 * _layer
	var engine := _engine(heights, [Vector2i(4, 4)])
	_run(engine, heights, 3)
	var lvl := engine.level_at(Vector2i(5, 4))
	var ahead := engine.level_at(Vector2i(4, 5))
	_check(lvl == 7 and ahead == 0, "fall: source above a drop fills the lower cell to 7 and skips side spread", "fall lvl=%d side=%d" % [lvl, ahead])


func _test_spread_distance() -> void:
	var heights := _flat(30, 5)
	for x in range(11, 29):
		heights[Vector2i(x, 2)] = BASE - _layer
	var engine := _engine(heights, [Vector2i(10, 2)])
	_run(engine, heights, 40)
	var reach := 0
	var levels: Array = []
	for x in range(11, 29):
		var lvl := engine.level_at(Vector2i(x, 2))
		levels.append(lvl)
		if lvl > 0:
			reach += 1
	_check(reach == 7 and levels.slice(0, 7) == [7, 6, 5, 4, 3, 2, 1], "spread distance == 7 with levels 7..1", "reach=%d levels=%s" % [reach, str(levels)])


func _test_no_uphill() -> void:
	var heights := _flat(9, 9)
	heights[Vector2i(5, 4)] = BASE + _layer
	heights[Vector2i(3, 4)] = BASE - _layer
	var engine := _engine(heights, [Vector2i(4, 4)])
	_run(engine, heights, 20)
	var up := engine.level_at(Vector2i(5, 4))
	var down := engine.level_at(Vector2i(3, 4))
	_check(up == 0 and down == 7, "no uphill: higher neighbour stays dry, lower fills", "up=%d down=%d" % [up, down])


func _test_dig_next_to_water() -> void:
	var heights := _flat(9, 9)
	var engine := _engine(heights, [Vector2i(4, 4)])
	_run(engine, heights, 10)
	var before := engine.level_at(Vector2i(5, 4))
	heights[Vector2i(5, 4)] = BASE - _layer
	_run(engine, heights, 10)
	var after := engine.level_at(Vector2i(5, 4))
	_check(before == 0 and after == 7, "dig next to water fills the cavity with level 7", "before=%d after=%d" % [before, after])


func _test_sources_never_drain() -> void:
	var heights := _flat(9, 9)
	heights[Vector2i(5, 4)] = BASE - _layer
	var engine := _engine(heights, [Vector2i(4, 4)])
	_run(engine, heights, 200)
	var level := engine.level_at(Vector2i(4, 4))
	_check(level == _VoxelFluidEngine.SOURCE_LEVEL and engine.sources.has(Vector2i(4, 4)), "sources never drain", "source level=%d" % level)


func _test_budget() -> void:
	var heights := _flat(40, 40)
	for x in range(2, 40):
		for z in 40:
			heights[Vector2i(x, z)] = BASE - _layer
	for i in range(-1, 41):
		for edge in [-1, 40]:
			heights[Vector2i(i, edge)] = BASE + _layer
			heights[Vector2i(edge, i)] = BASE + _layer
	var engine := _engine(heights, [Vector2i(1, 20)], BUDGET)
	var worst := _run(engine, heights, 600)
	var wet := 0
	for key in heights.keys():
		if engine.level_at(key) > 0:
			wet += 1
	_check(worst <= BUDGET and worst > 0 and wet > 7, "max cells per frame %d <= budget %d over 600 frames, %d wet" % [worst, BUDGET, wet], "worst=%d wet=%d" % [worst, wet])
