extends SceneTree

const _CrystalFluidSim = preload("res://crystal/crystal_fluid_sim.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")

func _init() -> void:
	var failed := false

	var cm_scr: GDScript = load("res://chunks/chunk_manager.gd") as GDScript
	if cm_scr == null or cm_scr.reload() != OK:
		push_error("FAIL chunk_manager compile")
		failed = true
	else:
		print("OK chunk_manager compiles")

	var cm: Node = cm_scr.new() as Node
	if cm == null or not cm.has_method("is_world_cell_loaded") or not cm.has_method("world_to_chunk_coord"):
		push_error("ChunkManager missing loaded-chunk helpers")
		failed = true
	else:
		print("OK ChunkManager loaded-chunk API")

	var sim := _CrystalFluidSim.new(_CrystalSimConfig.create_default(), _CrystalTerrainQuery.new())
	sim.max_new_cells_per_tick = 8
	sim.is_cell_active = func(pos: Vector2i) -> bool:
		return pos.x >= 0 and pos.x < 16 and pos.y >= 0 and pos.y < 16

	for i in 8:
		sim.set_depth(Vector2i(i, 8), 1.2, 0, false)

	var before: int = sim.cell_count()
	for _t in 12:
		sim.tick_flow(0.15)
	var after: int = sim.cell_count()

	var leaked := false
	for pos_variant in sim.depth.keys():
		var pos: Vector2i = pos_variant
		if pos.x < 0 or pos.x >= 16 or pos.y < 0 or pos.y >= 16:
			leaked = true
			break
	if leaked:
		push_error("crystal flow leaked outside active bounds")
		failed = true
	else:
		print("OK crystal flow bounded growth=", after - before, " cells=", after)

	var perf = load("res://config/performance_quality_config.gd").apply_preset(1)
	if not perf.crystal_sim_loaded_chunks_only:
		push_error("MEDIUM should keep crystal_sim_loaded_chunks_only")
		failed = true
	else:
		print("OK MEDIUM crystal_sim_loaded_chunks_only")

	if failed:
		quit(1)
	print("All loaded-chunk bound tests OK")
	quit(0)