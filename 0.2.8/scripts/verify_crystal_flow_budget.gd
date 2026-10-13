extends SceneTree
## Budgeted tick_flow must match unbounded tick_flow for the same logical ticks.


func _init() -> void:
	var failed := false
	var Fluid = load("res://crystal/crystal_fluid_sim.gd")
	var Terrain = load("res://crystal/crystal_terrain_query.gd")
	var Cfg = load("res://config/crystal_sim_config.gd")
	var cfg = Cfg.create_default()
	cfg.flow_substeps = 1

	var tq_a = Terrain.new()
	var tq_b = Terrain.new()
	# Flat test heights
	for x in range(-8, 9):
		for z in range(-8, 9):
			tq_a.test_base_heights[Vector2i(x, z)] = 40.0
			tq_b.test_base_heights[Vector2i(x, z)] = 40.0

	var a = Fluid.new(cfg, tq_a)
	var b = Fluid.new(cfg, tq_b)
	a.max_cells_per_tick = 0
	b.max_cells_per_tick = 0
	a.max_new_cells_per_tick = 0
	b.max_new_cells_per_tick = 0

	# Seed same blob
	for x in range(-4, 5):
		for z in range(-4, 5):
			a.set_depth(Vector2i(x, z), 0.6, 0, false)
			b.set_depth(Vector2i(x, z), 0.6, 0, false)

	tq_a.begin_sim_tick(1)
	tq_b.begin_sim_tick(1)
	a.flow_budget_us = 0
	for _i in 5:
		a.tick_flow(0.05)

	b.flow_budget_us = 50  # tiny budget forces multi-call resumes
	for _i in 5:
		var guard := 0
		while true:
			b.tick_flow(0.05)
			if b.last_flow_complete:
				break
			guard += 1
			if guard > 500:
				push_error("budget resume stuck")
				failed = true
				break

	# Compare depths
	if a.depth.size() != b.depth.size():
		push_error("cell count mismatch %d vs %d" % [a.depth.size(), b.depth.size()])
		failed = true
	for k in a.depth.keys():
		var da: float = float(a.depth[k])
		var db: float = float(b.depth.get(k, -999.0))
		if absf(da - db) > 1e-4:
			push_error("depth mismatch at %s %s vs %s" % [k, da, db])
			failed = true
			break
	if not failed:
		print("OK budgeted tick_flow matches unbounded cells=", a.depth.size())

	# Simulation façade resume
	var Sim = load("res://crystal/crystal_simulation.gd")
	var Snap = load("res://crystal/crystal_sim_snapshot.gd")
	var sim = Sim.new(cfg, tq_a)
	sim.flow_budget_us = 40
	for x in range(-3, 4):
		for z in range(-3, 4):
			sim.set_depth(Vector2i(x, z), 0.55, 0, false)
	var snap = Snap.new()
	snap.tick_id = 10
	snap.delta = 0.05
	snap.flow_substeps = 1
	snap.terrain = tq_a
	snap.spawn_emitters = []
	snap.loaded_chunks = {}
	snap.sim_loaded_chunks_only = false
	var g := 0
	while true:
		sim.tick(snap if g == 0 else null)
		if sim.last_tick_complete:
			break
		g += 1
		if g > 500:
			push_error("sim budget resume stuck")
			failed = true
			break
	if not failed:
		print("OK CrystalSimulation budgeted tick completes frames=", g + 1)

	if failed:
		push_error("VERIFY_CRYSTAL_FLOW_BUDGET_FAIL")
		quit(1)
	else:
		print("VERIFY_CRYSTAL_FLOW_BUDGET_OK")
		quit(0)
