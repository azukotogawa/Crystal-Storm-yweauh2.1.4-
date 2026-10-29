extends SceneTree

const _CrystalFluidSim = preload("res://crystal/crystal_fluid_sim.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _PerfConfig = preload("res://config/performance_quality_config.gd")


func _init() -> void:
	call_deferred("_run")


func _make(legacy: bool):
	var med = _PerfConfig.apply_preset(1)
	var cfg := _CrystalSimConfig.create_default()
	var sim := _CrystalFluidSim.new(cfg, _CrystalTerrainQuery.new())
	sim.max_new_cells_per_tick = med.max_crystal_new_cells_per_tick
	sim.max_cells_per_tick = med.max_crystal_flow_cells
	sim.empty_cell_inflow_cap = med.crystal_empty_cell_inflow_cap
	sim.spread_damping_start_cells = med.crystal_spread_damping_start
	sim.spread_damping_full_cells = med.crystal_spread_damping_full
	sim.spread_damping_min_mult = med.crystal_spread_damping_min
	sim.mesh_depth_epsilon = med.crystal_mesh_depth_epsilon
	sim.flow_budget_us = 0
	sim.index_full_scan_max = 1 << 30 if legacy else 64
	for z in 70:
		for x in 70:
			if (x * 7 + z * 13) % 29 == 0:
				continue
			var d := 0.3 + float((x * 31 + z * 17) % 23) / 10.0
			sim.set_depth(Vector2i(x, z), d, (x + z) % 3, false)
	return sim


func _rows(sim) -> Array:
	var out: Array = []
	for p in sim.depth.keys():
		out.append([p, sim.depth[p], sim.spawn_id_by_cell.get(p, -1)])
	return out


func _run() -> void:
	var a = _make(true)
	var b = _make(false)
	var failed := false
	for t in 240:
		if t % 40 == 20:
			for i in 12:
				var p := Vector2i((t + i * 5) % 70, (t * 3 + i * 11) % 70)
				a.set_depth(p, 0.0, -1, false)
				b.set_depth(p, 0.0, -1, false)
		a.tick_flow(0.1)
		b.tick_flow(0.1)
		if a.last_flow_selected_cells != b.last_flow_selected_cells:
			push_error("selected differ t=%d %d vs %d" % [t, a.last_flow_selected_cells, b.last_flow_selected_cells])
			failed = true
			break
	var ra := _rows(a)
	var rb := _rows(b)
	if ra != rb:
		push_error("rows differ cells=%d vs %d" % [ra.size(), rb.size()])
		failed = true
	else:
		print("OK rows identical cells=%d" % ra.size())
	if b.ordered_keys() != b.depth.keys():
		push_error("ordered_keys mismatch")
		failed = true
	else:
		print("OK ordered_keys match")
	var total := 0.0
	for p in b.depth.keys():
		total += float(b.depth[p])
	var vol: float = float(b.recalc_volume().volume)
	if absf(vol - total) > 1e-6:
		push_error("volume drift %.9f vs %.9f" % [vol, total])
		failed = true
	else:
		print("OK running volume %.4f" % vol)
	if failed:
		quit(1)
		return
	print("All crystal index equivalence tests OK")
	quit(0)
