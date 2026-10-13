extends SceneTree
## Crystal on standing water is queryable and presentation marks wet cells.


const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalPresentation = preload("res://crystal/crystal_presentation.gd")
const _CrystalFluidSim = preload("res://crystal/crystal_fluid_sim.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")


func _init() -> void:
	var failed := false
	var pres_src := (_CrystalPresentation as GDScript).source_code
	if "is_wet" not in pres_src:
		push_error("presentation must mark wet crystal cells")
		failed = true
	else:
		print("OK presentation sets is_wet")
	var layer_src := (load("res://crystal/crystal_chunk_layer.gd") as GDScript).source_code
	if "is_wet" not in layer_src:
		push_error("chunk layer must flatten wet crystal")
		failed = true
	else:
		print("OK chunk layer flattens wet crawl")
	var hud_src := (load("res://ui/game_overlay.gd") as GDScript).source_code
	if "wet crawl" not in hud_src:
		push_error("HUD must show wet crawl when crystal sits on water")
		failed = true
	else:
		print("OK HUD wet crawl bit")

	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	_ChannelRegistry.reset()
	var terrain := _CrystalTerrainQuery.new()
	var heights := {}
	var tiles := {}
	for x in 6:
		for z in 6:
			heights[Vector2i(x, z)] = 10.0
			tiles[Vector2i(x, z)] = _VoxelTypes.GRASSLAND
	tiles[Vector2i(2, 2)] = _VoxelTypes.RIVER
	terrain.test_base_heights = heights
	terrain.test_tiles = tiles
	var wet: float = terrain.get_standing_water_level(Vector2i(2, 2))
	var dry: float = terrain.get_standing_water_level(Vector2i(4, 4))
	if wet < 0.05:
		push_error("river tile must count as standing water, got %.3f" % wet)
		failed = true
	elif dry >= 0.05:
		push_error("grass must not count as standing water")
		failed = true
	else:
		print("OK standing water river=%.2f grass=%.2f" % [wet, dry])

	var cfg := _CrystalSimConfig.create_default()
	var sim := _CrystalFluidSim.new(cfg, terrain)
	sim.set_depth(Vector2i(2, 2), 0.8, 0, false)
	sim.set_depth(Vector2i(4, 4), 0.8, 0, false)
	var pres := _CrystalPresentation.new()
	pres.fluid = sim
	pres.sim_config = cfg
	var wet_cell = pres._make_render_cell(Vector2i(2, 2), 0.8, 0)
	var dry_cell = pres._make_render_cell(Vector2i(4, 4), 0.8, 0)
	if not bool(wet_cell.is_wet):
		push_error("crystal on river must be is_wet")
		failed = true
	elif bool(dry_cell.is_wet):
		push_error("crystal on grass must not be is_wet")
		failed = true
	else:
		print("OK wet/dry render cells")

	if failed:
		quit(1)
	print("All crystal wet-crawl tests OK")
	quit(0)
