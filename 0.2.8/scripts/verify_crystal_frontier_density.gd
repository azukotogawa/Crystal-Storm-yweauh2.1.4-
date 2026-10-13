extends SceneTree
## Regression: crystal spread should not leave persistent checkerboard holes in the fluid envelope.


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
	var cfg := _CrystalSimConfig.create_default()
	var terrain := _CrystalTerrainQuery.new()
	var origin := Vector2i(20, 20)
	var tick_delta := 1.0 / maxf(float(med.crystal_sim_hz), 1.0)

	var sim := _CrystalFluidSim.new(cfg, terrain)
	_apply_medium_sim_params(sim, med)

	# Line seed matches spread_limits; delta must match MEDIUM crystal_sim_hz (0.18 stalls spread).
	for i in 10:
		sim.set_depth(Vector2i(origin.x + i - 5, origin.y), cfg.initial_spawn_depth, 0, false)

	for _t in 48:
		sim.tick_flow(tick_delta)

	var min_x := origin.x - 12
	var max_x := origin.x + 12
	var min_z := origin.y - 12
	var max_z := origin.y + 12
	var holes := 0
	var filled := 0
	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
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

	if filled < 20:
		push_error(
			"spread too small filled=%d after 48 ticks delta=%.3f"
			% [filled, tick_delta]
		)
		failed = true
	elif holes > maxi(6, filled / 8):
		push_error(
			"checkerboard holes=%d filled=%d (empty cells with 3+ filled neighbors)"
			% [holes, filled]
		)
		failed = true
	else:
		print("OK crystal envelope holes=%d filled=%d cap=%d" % [
			holes, filled, med.max_crystal_new_cells_per_tick
		])

	if failed:
		print("Crystal frontier density FAILED")
		quit(1)
		return
	print("All crystal frontier density tests OK")
	quit(0)