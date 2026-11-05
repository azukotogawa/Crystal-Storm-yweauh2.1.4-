extends SceneTree
func _init() -> void:
	var Fluid = load("res://crystal/crystal_fluid_sim.gd")
	var Terrain = load("res://crystal/crystal_terrain_query.gd")
	var Cfg = load("res://config/crystal_sim_config.gd")
	var cfg = Cfg.create_default()
	cfg.flow_substeps = 1
	var tq_a = Terrain.new()
	var tq_b = Terrain.new()
	for x in range(-24, 25):
		for z in range(-24, 25):
			tq_a.test_base_heights[Vector2i(x, z)] = 40.0
			tq_b.test_base_heights[Vector2i(x, z)] = 40.0
	OS.set_environment("CRYSTALSTORM_CRYSTAL_DEPTH_SOA", "1")
	var a = Fluid.new(cfg, tq_a)
	a._refresh_soa_hot()
	OS.set_environment("CRYSTALSTORM_CRYSTAL_DEPTH_SOA", "0")
	var b = Fluid.new(cfg, tq_b)
	b._refresh_soa_hot()
	print("SOA_MODE a_hot=%s b_hot=%s" % [str(a._soa_hot), str(b._soa_hot)])
	a.flow_budget_us = 0
	b.flow_budget_us = 0
	a.max_cells_per_tick = 0
	b.max_cells_per_tick = 0
	for r in range(0, 16):
		for z in range(-r, r + 1):
			for x in range(-r, r + 1):
				if maxi(absi(x), absi(z)) != r:
					continue
				a.set_depth(Vector2i(x, z), 0.65, 0, false)
				b.set_depth(Vector2i(x, z), 0.65, 0, false)
	print("SOA_SEED a_cells=%d a_soa=%d b_cells=%d" % [a.depth.size(), a.depth_soa.size(), b.depth.size()])
	tq_a.begin_sim_tick(1)
	tq_b.begin_sim_tick(1)
	for _i in 20:
		a.tick_flow(0.05)
		b.tick_flow(0.05)
	var bad := 0
	var checked := 0
	if a.depth.size() != b.depth.size():
		print("SOA_FLOW size_mismatch a=%d b=%d" % [a.depth.size(), b.depth.size()])
		bad += 100000
	for pos_v in a.depth.keys():
		var pos: Vector2i = pos_v
		checked += 1
		var da: float = float(a.depth[pos])
		var db: float = float(b.depth.get(pos, -1.0))
		var ga: float = a.get_depth_at(pos.x, pos.y)
		if absf(da - db) > 0.0001 or absf(da - ga) > 0.0001:
			bad += 1
		if a._seq.has(pos):
			var sq: int = int(a._seq[pos])
			if sq < 0 or sq >= a.depth_soa.size() or absf(float(a.depth_soa[sq]) - da) > 0.0001:
				bad += 1
	print("SOA_FLOW a_cells=%d b_cells=%d checked=%d bad=%d soa_size=%d" % [a.depth.size(), b.depth.size(), checked, bad, a.depth_soa.size()])
	quit(0 if bad == 0 and checked > 0 else 1)