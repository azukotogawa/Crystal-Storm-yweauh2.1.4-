extends SceneTree
## Unit proof: CrystalFluidSim prefers downhill flow and caps uphill frontier inflow.

const _CrystalFluidSim = preload("res://crystal/crystal_fluid_sim.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")


func _init() -> void:
	var failed := false
	_TerrainEdits.reset()

	var scr: GDScript = load("res://crystal/crystal_fluid_sim.gd") as GDScript
	if scr == null or scr.reload() != OK:
		push_error("FAIL crystal_fluid_sim compile")
		quit(1)
		return

	var cfg := _CrystalSimConfig.create_default()
	cfg.pressure_flow_rate = 1.4
	cfg.max_flow_per_cell = 2.0
	cfg.cliff_height = 1.05
	cfg.lateral_spread_bias = 0.0

	var terrain := _CrystalTerrainQuery.new()
	terrain.test_base_heights = _make_height_grid()
	var sim := _CrystalFluidSim.new(cfg, terrain)
	sim.max_new_cells_per_tick = 0
	sim.empty_cell_inflow_cap = 0.08

	var source := Vector2i(5, 5)
	var downhill := Vector2i(6, 5)
	var uphill := Vector2i(5, 6)
	sim.set_depth(source, 2.2, 0, false)

	var downhill_tick := -1
	var uphill_tick := -1
	for tick in 40:
		sim.tick_flow(0.25)
		if downhill_tick < 0 and sim.get_depth_at(downhill.x, downhill.y) >= cfg.min_depth:
			downhill_tick = tick
		if uphill_tick < 0 and sim.get_depth_at(uphill.x, uphill.y) >= cfg.min_depth:
			uphill_tick = tick

	if downhill_tick < 0:
		push_error("downhill neighbor never received crystal")
		failed = true
	elif uphill_tick < 0:
		print("OK downhill reached before uphill (uphill blocked in window)")
	elif downhill_tick <= uphill_tick:
		print("OK downhill tick=%d before uphill tick=%d" % [downhill_tick, uphill_tick])
	else:
		push_error("downhill tick=%d should precede uphill tick=%d" % [downhill_tick, uphill_tick])
		failed = true

	var down_depth: float = sim.get_depth_at(downhill.x, downhill.y)
	var up_depth: float = sim.get_depth_at(uphill.x, uphill.y)
	if down_depth < cfg.min_depth:
		push_error("downhill depth too low: %.3f" % down_depth)
		failed = true
	elif up_depth >= cfg.min_depth and down_depth <= up_depth:
		push_error("downhill depth %.3f should exceed uphill %.3f" % [down_depth, up_depth])
		failed = true
	else:
		print("OK depth downhill=%.3f uphill=%.3f (uphill slower)" % [down_depth, up_depth])

	# Uphill inflow cap: empty-cell transfer per tick should not exceed cap.
	sim.clear()
	terrain.begin_sim_tick(1)
	terrain.test_base_heights = _make_height_grid()
	sim.set_depth(source, 3.0, 0, false)
	var before_up: float = sim.get_depth_at(uphill.x, uphill.y)
	sim.tick_flow(0.2)
	var after_up: float = sim.get_depth_at(uphill.x, uphill.y)
	var gained: float = after_up - before_up
	if gained > sim.empty_cell_inflow_cap + 0.02:
		push_error("uphill inflow %.3f exceeded cap %.3f" % [gained, sim.empty_cell_inflow_cap])
		failed = true
	else:
		print("OK uphill inflow capped gain=%.3f cap=%.3f" % [gained, sim.empty_cell_inflow_cap])

	if failed:
		quit(1)
	print("All crystal flow mechanics tests OK")
	quit(0)


func _make_height_grid() -> Dictionary:
	var heights: Dictionary = {}
	for x in 12:
		for z in 12:
			heights[Vector2i(x, z)] = 10.0
	heights[Vector2i(6, 5)] = 8.0
	heights[Vector2i(5, 6)] = 11.5
	heights[Vector2i(4, 5)] = 14.0
	return heights