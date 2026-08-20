extends SceneTree

const _CrystalFluidSim = preload("res://crystal/crystal_fluid_sim.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")

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

	sim.clear()
	sim.set_depth(Vector2i(0, 0), 2.0, 0, false)
	var before_frontier: int = sim.cell_count()
	sim.tick_flow(0.15)
	var after_frontier: int = sim.cell_count()
	var frontier_ok := true
	for pos_variant in sim.depth.keys():
		var pos: Vector2i = pos_variant
		if pos == Vector2i(0, 0):
			continue
		var touches := 0
		for dir in _CrystalTypes.NEIGHBOR_DIRS:
			var n: Vector2i = pos + dir
			if float(sim.depth.get(n, 0.0)) >= sim.config.min_depth:
				touches += 1
		if touches < 1:
			frontier_ok = false
			break
	if not frontier_ok and after_frontier > before_frontier:
		push_error("new crystal cells should touch existing fluid front")
		failed = true
	elif after_frontier > before_frontier:
		print("OK frontier cells contiguous after first spread tick")

	sim.tick_flow(0.05)
	if sim.last_mesh_dirty_cells > sim.last_changed_cells:
		push_error("mesh_dirty=%d exceeded changed=%d" % [sim.last_mesh_dirty_cells, sim.last_changed_cells])
		failed = true
	elif sim.last_mesh_dirty_cells > 64:
		push_error("mesh_dirty=%d too large for incremental tick" % sim.last_mesh_dirty_cells)
		failed = true
	else:
		print("OK incremental mesh_dirty=%d changed=%d" % [sim.last_mesh_dirty_cells, sim.last_changed_cells])

	# Incremental mesh patch lives on CrystalPresentation (sim split); fluid still exposes mesh dirty.
	var pres_src := (load("res://crystal/crystal_presentation.gd") as GDScript).source_code
	var fluid_src := (load("res://crystal/crystal_fluid_sim.gd") as GDScript).source_code
	if "_patch_chunk_layer" not in pres_src or "get_last_mesh_dirty" not in fluid_src:
		push_error("crystal presentation/fluid must patch incremental mesh dirty cells")
		failed = true
	else:
		print("OK crystal presentation incremental patch path")

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