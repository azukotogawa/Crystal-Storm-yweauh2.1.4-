extends SceneTree
func _init() -> void:
	var Fluid = load("res://crystal/crystal_fluid_sim.gd")
	var Terrain = load("res://crystal/crystal_terrain_query.gd")
	var Cfg = load("res://config/crystal_sim_config.gd")
	var sizes := [2000, 8000, 16000, 25000]
	for n_target in sizes:
		_bench_one(Fluid, Terrain, Cfg, n_target, true)
		_bench_one(Fluid, Terrain, Cfg, n_target, false)
	quit(0)

func _bench_one(Fluid, Terrain, Cfg, n_target: int, soa_on: bool) -> void:
	var cfg = Cfg.create_default()
	cfg.flow_substeps = 1
	var tq = Terrain.new()
	var r_max: int = int(ceil(sqrt(float(n_target)))) + 2
	for x in range(-r_max, r_max + 1):
		for z in range(-r_max, r_max + 1):
			tq.test_base_heights[Vector2i(x, z)] = 40.0
	OS.set_environment("CRYSTALSTORM_CRYSTAL_DEPTH_SOA", "1" if soa_on else "0")
	var f = Fluid.new(cfg, tq)
	f._refresh_soa_hot()
	f.flow_budget_us = 0
	f.max_cells_per_tick = 0
	var placed := 0
	var r := 0
	while placed < n_target and r < 400:
		for z in range(-r, r + 1):
			for x in range(-r, r + 1):
				if maxi(absi(x), absi(z)) != r:
					continue
				f.set_depth(Vector2i(x, z), 0.7, 0, false)
				placed += 1
				if placed >= n_target:
					break
			if placed >= n_target:
				break
		r += 1
	tq.begin_sim_tick(1)
	# warm
	for _w in 5:
		f.tick_flow(0.05)
	var ticks := 40
	var t0 := Time.get_ticks_usec()
	for _i in ticks:
		f.tick_flow(0.05)
	var us: int = Time.get_ticks_usec() - t0
	var per: float = float(us) / float(ticks)
	var fps_eq: float = 1000000.0 / maxf(per, 1.0)
	print("TFLOW soa=%s n=%d depth=%d ticks=%d total_us=%d per_us=%.1f fluid_fps_eq=%.1f" % [
		"ON" if soa_on else "OFF", n_target, f.depth.size(), ticks, us, per, fps_eq])