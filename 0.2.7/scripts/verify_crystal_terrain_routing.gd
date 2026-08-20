extends SceneTree
## Unit proof: dig/build wall edits change subsequent crystal spread routing.

const _CrystalFluidSim = preload("res://crystal/crystal_fluid_sim.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")


func _init() -> void:
	_TerrainEdits.reset()
	_WorldSettings.apply_active(_WorldSettings.create_default())

	var baseline := _run_sim_ticks(36, &"none")
	_TerrainEdits.reset()
	var dug := _run_sim_ticks(36, &"dig")
	_TerrainEdits.reset()
	var walled := _run_sim_ticks(36, &"wall")

	var basin := Vector2i(7, 10)
	var choke := Vector2i(5, 10)
	var base_basin: float = baseline.depths.get(basin, 0.0)
	var dug_basin: float = dug.depths.get(basin, 0.0)
	var wall_basin: float = walled.depths.get(basin, 0.0)

	if baseline.frontier_hash == dug.frontier_hash and baseline.frontier_hash == walled.frontier_hash:
		push_error("terrain edits did not change frontier sets")
		quit(1)
		return

	var dig_ok: bool = dug_basin > base_basin + 0.05
	var wall_ok: bool = walled.frontier_hash != baseline.frontier_hash or absf(wall_basin - base_basin) > 0.05
	if not dig_ok:
		push_error("dig basin should attract more crystal base=%.3f dug=%.3f" % [base_basin, dug_basin])
		quit(1)
		return
	if not wall_ok:
		push_error("build_wall should change frontier routing")
		quit(1)
		return

	print(
		"OK routing dig basin %.3f→%.3f wall basin %.3f choke=%.3f baseline cells=%d dug=%d wall=%d"
		% [
			base_basin, dug_basin, wall_basin, walled.depths.get(choke, 0.0),
			baseline.frontier.size(), dug.frontier.size(), walled.frontier.size(),
		]
	)
	print("All crystal terrain routing tests OK")
	quit(0)


func _run_sim_ticks(ticks: int, edit_mode: StringName) -> Dictionary:
	_TerrainEdits.reset()
	var terrain := _CrystalTerrainQuery.new()
	terrain.test_base_heights = _flat_field()
	var cfg := _CrystalSimConfig.create_default()
	cfg.pressure_flow_rate = 1.5
	cfg.lateral_spread_bias = 0.04
	cfg.built_wall_flow_factor = 0.05
	var sim := _CrystalFluidSim.new(cfg, terrain)
	sim.empty_cell_inflow_cap = 0.18

	var source := Vector2i(0, 10)
	sim.set_depth(source, 3.0, 0, false)

	match edit_mode:
		&"dig":
			_TerrainEdits.dig(7, 10, 2)
		&"wall":
			_TerrainEdits.build_wall(5, 10, _VoxelTypes.STONE)

	for _i in ticks:
		terrain.begin_sim_tick(_i + 1)
		sim.tick_flow(0.28)

	var frontier: Dictionary = {}
	var depths: Dictionary = {}
	for pos_variant in sim.depth.keys():
		var pos: Vector2i = pos_variant
		var d: float = float(sim.depth[pos])
		depths[pos] = d
		if d >= cfg.min_depth:
			frontier[pos] = d

	var keys: Array = frontier.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y
	)
	var hash_parts: PackedStringArray = PackedStringArray()
	for pos in keys:
		hash_parts.append("%d,%d:%.2f" % [pos.x, pos.y, frontier[pos]])

	return {
		"frontier": frontier,
		"frontier_hash": "|".join(hash_parts),
		"depths": depths,
	}


func _flat_field() -> Dictionary:
	var heights: Dictionary = {}
	for x in 16:
		for z in 20:
			heights[Vector2i(x, z)] = 10.0
	return heights