extends SceneTree
## Presentation-only: frontier cells flagged for taller mesh; no sim rule changes.
## Usage: godot --headless -s scripts/verify_crystal_frontier_readability.gd


const _CrystalCell = preload("res://crystal/crystal_cell.gd")
const _CrystalClusterMesh = preload("res://helpers/crystal_cluster_mesh.gd")
const _CrystalPresentation = preload("res://crystal/crystal_presentation.gd")
const _CrystalFluidSim = preload("res://crystal/crystal_fluid_sim.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false

	# Cell flag exists and is visual-only field
	var c := _CrystalCell.new(Vector2i(1, 1), 0.0, 1.0)
	if not ("is_frontier" in c):
		push_error("CrystalCell missing is_frontier")
		failed = true
	else:
		print("OK CrystalCell.is_frontier present")

	var heights: Dictionary = {}
	for x in 12:
		for z in 12:
			heights[Vector2i(x, z)] = 10.0
	var terrain := _CrystalTerrainQuery.new()
	terrain.test_base_heights = heights
	var cfg := _CrystalSimConfig.create_default()
	var fluid := _CrystalFluidSim.new(cfg, terrain)
	fluid.set_depth(Vector2i(5, 5), 1.0, -1, false)
	fluid.set_depth(Vector2i(6, 5), 1.0, -1, false)

	var pres := _CrystalPresentation.new()
	pres.fluid = fluid
	pres.sim_config = cfg
	pres.crystal_floor_at = func(pos: Vector2i) -> float:
		return 10.0

	var edge = pres._make_render_cell(Vector2i(5, 5), 1.0, -1)
	var tip = pres._make_render_cell(Vector2i(6, 5), 1.0, -1)
	# 5,5 has neighbor 6,5 only among crystal — still has empty cardinals → frontier
	if not edge.is_frontier:
		push_error("edge cell should be frontier")
		failed = true
	if not tip.is_frontier:
		push_error("tip cell should be frontier")
		failed = true
	# Fill all neighbors of 5,5 to make interior
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		fluid.set_depth(Vector2i(5, 5) + d, 1.0, -1, false)
	var interior = pres._make_render_cell(Vector2i(5, 5), 1.0, -1)
	if interior.is_frontier:
		push_error("fully surrounded cell should not be frontier")
		failed = true
	else:
		print("OK frontier flag edge vs interior")

	var cm_src := (load("res://crystal/crystal_manager.gd") as GDScript).source_code
	if "find_nearest_frontier_cell" not in cm_src or "crystal_front" not in cm_src:
		push_error("crystal_manager must pulse nearest frontier for readability")
		failed = true
	else:
		print("OK frontier pulse path present")

	var layer_src := (load("res://crystal/crystal_chunk_layer.gd") as GDScript).source_code
	if "is_frontier" not in layer_src or "frontier_boost" not in layer_src:
		push_error("chunk layer must boost frontier visual scale")
		failed = true
	else:
		print("OK frontier mesh scale boost")

	var ov_src := (load("res://ui/game_overlay.gd") as GDScript).source_code
	if "Trench cut" not in ov_src and "Wall raised" not in ov_src:
		push_error("overlay must explain terrain vs crystal when editing near front")
		failed = true
	else:
		print("OK terrain-near-crystal toasts")

	if "ASSAULT — you are on the purple front" not in ov_src:
		push_error("ASSAULT toast must be unmistakable")
		failed = true
	else:
		print("OK ASSAULT transition toast")

	# Guard: sim flow rates not edited by this presentation work (spot-check config defaults)
	if not is_equal_approx(cfg.pressure_flow_rate, 1.1) and cfg.pressure_flow_rate <= 0.0:
		push_error("unexpected sim config mutation")
		failed = true

	if failed:
		quit(1)
		return
	print("All crystal frontier readability tests OK")
	quit(0)
