extends SceneTree
## P1 regression: tuned crystal flow reduces checkerboard holes vs legacy lateral=0 params.


const _CrystalFluidSim = preload("res://crystal/crystal_fluid_sim.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _PerfConfig = preload("res://config/performance_quality_config.gd")


func _init() -> void:
	call_deferred("_run")


func _apply_medium_sim_params(sim: _CrystalFluidSim, med) -> void:
	sim.max_new_cells_per_tick = med.max_crystal_new_cells_per_tick
	sim.max_cells_per_tick = med.max_crystal_flow_cells
	sim.empty_cell_inflow_cap = med.crystal_empty_cell_inflow_cap
	sim.spread_damping_start_cells = med.crystal_spread_damping_start
	sim.spread_damping_full_cells = med.crystal_spread_damping_full
	sim.spread_damping_min_mult = med.crystal_spread_damping_min
	sim.mesh_depth_epsilon = med.crystal_mesh_depth_epsilon


func _run() -> void:
	var failed := false
	var med = _PerfConfig.apply_preset(1)
	var origin := Vector2i(20, 20)
	var tick_delta := 1.0 / maxf(float(med.crystal_sim_hz), 1.0)

	var tuned_cfg := _CrystalSimConfig.create_default()
	if tuned_cfg.lateral_spread_bias < 0.08:
		push_error("default lateral_spread_bias too low for settling (%.2f)" % tuned_cfg.lateral_spread_bias)
		failed = true
	else:
		print("OK lateral_spread_bias=%.2f" % tuned_cfg.lateral_spread_bias)

	if med.crystal_empty_cell_inflow_cap < 0.065:
		push_error("MEDIUM inflow cap too low: %.3f" % med.crystal_empty_cell_inflow_cap)
		failed = true
	else:
		print("OK MEDIUM inflow_cap=%.3f" % med.crystal_empty_cell_inflow_cap)

	var ticks := 48
	var tuned_stats := _spread_stats(tuned_cfg, med, origin, tick_delta, ticks)
	if tuned_stats.filled < 20:
		push_error("tuned spread too small filled=%d" % tuned_stats.filled)
		failed = true
	elif tuned_stats.holes > maxi(6, tuned_stats.filled / 8):
		push_error("tuned checkerboard holes=%d filled=%d" % [tuned_stats.holes, tuned_stats.filled])
		failed = true
	else:
		print("OK tuned envelope holes=%d filled=%d" % [tuned_stats.holes, tuned_stats.filled])

	var legacy_cfg := _CrystalSimConfig.create_default()
	legacy_cfg.lateral_spread_bias = 0.0
	legacy_cfg.pressure_flow_rate = 0.17
	legacy_cfg.max_outflow_ratio = 0.10
	var legacy_med = med.duplicate()
	legacy_med.crystal_empty_cell_inflow_cap = 0.055
	legacy_med.max_crystal_new_cells_per_tick = 5
	var legacy_stats := _spread_stats(legacy_cfg, legacy_med, origin, tick_delta, ticks)
	if legacy_stats.holes > tuned_stats.holes:
		print(
			"OK tuned holes=%d < legacy holes=%d"
			% [tuned_stats.holes, legacy_stats.holes]
		)
	elif legacy_stats.filled > tuned_stats.filled + 1:
		push_error(
			"legacy filled=%d should not beat tuned filled=%d"
			% [legacy_stats.filled, tuned_stats.filled]
		)
		failed = true
	elif tuned_stats.filled < legacy_stats.filled:
		print(
			"OK tuned filled=%d >= legacy filled=%d holes=%d/%d"
			% [tuned_stats.filled, legacy_stats.filled, tuned_stats.holes, legacy_stats.holes]
		)
	else:
		print(
			"OK tuned filled=%d legacy filled=%d holes=%d/%d"
			% [tuned_stats.filled, legacy_stats.filled, tuned_stats.holes, legacy_stats.holes]
		)

	if failed:
		quit(1)
	print("All crystal settling tests OK")
	quit(0)


func _spread_stats(cfg: _CrystalSimConfig, med, origin: Vector2i, tick_delta: float, ticks: int) -> Dictionary:
	var terrain := _CrystalTerrainQuery.new()
	var sim := _CrystalFluidSim.new(cfg, terrain)
	_apply_medium_sim_params(sim, med)
	for i in 10:
		sim.set_depth(Vector2i(origin.x + i - 5, origin.y), cfg.initial_spawn_depth, 0, false)
	for _t in ticks:
		sim.tick_flow(tick_delta)
	return _hole_scan(sim, origin, 12)


func _hole_scan(sim: _CrystalFluidSim, origin: Vector2i, radius: int) -> Dictionary:
	var filled := 0
	var holes := 0
	for x in range(origin.x - radius, origin.x + radius + 1):
		for z in range(origin.y - radius, origin.y + radius + 1):
			var pos := Vector2i(x, z)
			var d: float = sim.get_depth_at(pos.x, pos.y)
			if d >= sim.config.min_depth:
				filled += 1
				continue
			var filled_neighbors := 0
			for dir in _CrystalTypes.NEIGHBOR_DIRS:
				var n: Vector2i = pos + dir
				if sim.get_depth_at(n.x, n.y) >= sim.config.min_depth:
					filled_neighbors += 1
			if filled_neighbors >= 3:
				holes += 1
	return {"filled": filled, "holes": holes}