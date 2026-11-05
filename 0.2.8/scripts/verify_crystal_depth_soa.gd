extends SceneTree
func _init() -> void:
	var Fluid = load("res://crystal/crystal_fluid_sim.gd")
	var Terrain = load("res://crystal/crystal_terrain_query.gd")
	var Cfg = load("res://config/crystal_sim_config.gd")
	OS.set_environment("CRYSTALSTORM_CRYSTAL_DEPTH_SOA", "1")
	var cfg = Cfg.create_default()
	var tq = Terrain.new()
	for x in range(-20, 21):
		for z in range(-20, 21):
			tq.test_base_heights[Vector2i(x, z)] = 40.0
	var f = Fluid.new(cfg, tq)
	f.flow_budget_us = 0
	f.max_cells_per_tick = 0
	for r in range(0, 12):
		for z in range(-r, r + 1):
			for x in range(-r, r + 1):
				if maxi(absi(x), absi(z)) != r:
					continue
				f.set_depth(Vector2i(x, z), 0.6, 0, false)
	tq.begin_sim_tick(1)
	for _i in 10:
		f.tick_flow(0.05)
	var bad := 0
	var checked := 0
	for pos_v in f.depth.keys():
		var pos: Vector2i = pos_v
		var d_dict: float = float(f.depth[pos])
		var d_get: float = f.get_depth_at(pos.x, pos.y)
		checked += 1
		if absf(d_dict - d_get) > 0.0001:
			bad += 1
		if f._seq.has(pos):
			var sq: int = int(f._seq[pos])
			if sq < 0 or sq >= f.depth_soa.size() or absf(float(f.depth_soa[sq]) - d_dict) > 0.0001:
				bad += 1
	print("SOA_ID cells=%d checked=%d bad=%d soa_size=%d next_seq=%d" % [f.depth.size(), checked, bad, f.depth_soa.size(), f._next_seq])
	quit(0 if bad == 0 and checked > 0 else 1)