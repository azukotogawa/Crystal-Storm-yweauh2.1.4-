extends SceneTree

const _CrystalFluidSim = preload("res://crystal/crystal_fluid_sim.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")

func _init() -> void:
	var failed := false

	var scr: GDScript = load("res://crystal/crystal_fluid_sim.gd") as GDScript
	if scr == null or scr.reload() != OK:
		push_error("FAIL crystal_fluid_sim compile")
		failed = true
	else:
		print("OK crystal_fluid_sim compiles")

	var sim := _CrystalFluidSim.new(_CrystalSimConfig.create_default(), _CrystalTerrainQuery.new())
	sim.max_new_cells_per_tick = 5
	sim.empty_cell_inflow_cap = 0.08
	sim.spread_damping_start_cells = 10
	sim.spread_damping_full_cells = 50
	sim.spread_damping_min_mult = 0.4

	# Seed a line of crystal — flow should not instantly flood thousands of cells.
	for i in 10:
		sim.set_depth(Vector2i(i, 0), 1.5, 0, false)

	var before: int = sim.cell_count()
	for _t in 20:
		sim.tick_flow(0.2)
	var after: int = sim.cell_count()
	var growth: int = after - before
	if growth > 120:
		push_error("unbounded spread growth=%d (before=%d after=%d)" % [growth, before, after])
		failed = true
	else:
		print("OK spread growth capped-ish growth=", growth, " cells=", after)

	if sim.last_new_cells > sim.max_new_cells_per_tick:
		push_error("last_new_cells exceeded cap")
		failed = true
	else:
		print("OK last_new_cells=", sim.last_new_cells, " cap=", sim.max_new_cells_per_tick)

	var med = load("res://config/performance_quality_config.gd").apply_preset(1)
	if med.max_crystal_new_cells_per_tick <= 0 or med.max_crystal_new_cells_per_tick > 64:
		push_error("MEDIUM new cells cap out of range")
		failed = true
	else:
		print("OK MEDIUM new_cap=", med.max_crystal_new_cells_per_tick)

	var low = load("res://config/performance_quality_config.gd").apply_preset(0)
	if low.max_crystal_new_cells_per_tick >= med.max_crystal_new_cells_per_tick:
		push_error("LOW should have lower new cell cap than MEDIUM")
		failed = true
	else:
		print("OK LOW new_cap=", low.max_crystal_new_cells_per_tick)

	if failed:
		quit(1)
	print("All crystal spread limit tests OK")
	quit(0)