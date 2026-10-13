extends SceneTree
## Complete MAZE → crystal pressure → ASSAULT loop using existing systems only.
## Usage: godot --headless -s scripts/verify_maze_pressure_assault.gd


const _CrystalFluidSim = preload("res://crystal/crystal_fluid_sim.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _GameManager = preload("res://game/game_manager.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")


var _failed: int = 0


class _PlayerNear extends Node3D:
	func get_voxel_position() -> Vector3:
		return Vector3(10.0, 2.0, 0.0)

	func take_damage(_a: float) -> void:
		pass

	func get_stat(_i: StringName) -> float:
		return 0.0


class _CrystalNear extends Node:
	var strength_tier: int = 0
	var expansion_enabled: bool = true
	var d: float = 100.0

	func get_nearest_crystal_distance(_f: Vector3) -> float:
		return d

	func get_active_spawns() -> Array:
		return []

	func get_coverage_ratio() -> float:
		return 0.0


class _CovCrystal extends Node:
	var expansion_enabled: bool = true

	func get_coverage_ratio() -> float:
		return 1.0


class _WinCrystal extends Node:
	var expansion_enabled: bool = true


func _init() -> void:
	_WorldSettings.apply_active(_WorldSettings.create_default())
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	_test_open_spread_visible()
	_test_wall_delays_crystal()
	_test_trench_redirects()
	_test_gate_slows()
	_test_water_slows()
	_test_phase_maze_to_assault()
	_test_win_lose_authoritative()

	if _failed == 0:
		print("All maze pressure assault loop tests OK")
		quit(0)
	else:
		push_error("verify_maze_pressure_assault: %d failure(s)" % _failed)
		quit(1)


func _flat_heights(w: int = 24, h: int = 16, base: float = 10.0) -> Dictionary:
	var heights: Dictionary = {}
	for x in w:
		for z in h:
			heights[Vector2i(x, z)] = base
	return heights


func _run_sim(heights: Dictionary, ticks: int, do_walls: bool) -> Dictionary:
	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	_ChannelRegistry.reset()
	var terrain := _CrystalTerrainQuery.new()
	terrain.test_base_heights = heights
	var cfg := _CrystalSimConfig.create_default()
	cfg.pressure_flow_rate = 1.35
	cfg.lateral_spread_bias = 0.05
	cfg.built_wall_flow_factor = 0.08
	cfg.channel_base_flow_factor = 0.1
	cfg.river_flow_factor = 0.06
	if do_walls:
		for z in range(5, 12):
			_TerrainEdits.build_wall(5, z, _VoxelTypes.STONE)
			_FeatureRegistry.register_feature(5, z, 0, {
				"player_built": true,
				"flow_resistance": 0.85,
				"build_id": "stone_wall",
			})
	var sim := _CrystalFluidSim.new(cfg, terrain)
	sim.empty_cell_inflow_cap = 0.2
	sim.set_depth(Vector2i(0, 8), 3.5, 0, false)
	for i in ticks:
		terrain.begin_sim_tick(i + 1)
		sim.tick_flow(0.28)
	var far := Vector2i(14, 8)
	return {
		"far_depth": sim.get_depth_at(far.x, far.y),
		"cells": sim.cell_count(),
		"mid_depth": sim.get_depth_at(7, 8),
	}


func _test_open_spread_visible() -> void:
	var r: Dictionary = _run_sim(_flat_heights(), 40, false)
	if float(r.far_depth) < 0.05 and int(r.cells) < 8:
		_fail("crystal should spread continuously on open ground cells=%d far=%.3f" % [
			int(r.cells), float(r.far_depth)
		])
	else:
		print("OK continuous spread cells=%d far=%.3f" % [int(r.cells), float(r.far_depth)])


func _test_wall_delays_crystal() -> void:
	var open: Dictionary = _run_sim(_flat_heights(), 36, false)
	var walled: Dictionary = _run_sim(_flat_heights(), 36, true)
	var open_far: float = float(open.far_depth)
	var wall_far: float = float(walled.far_depth)
	var open_n: int = int(open.cells)
	var wall_n: int = int(walled.cells)
	if wall_far > open_far + 0.05 and wall_n >= open_n:
		_fail("walls should delay crystal open_far=%.3f wall_far=%.3f n %d→%d" % [
			open_far, wall_far, open_n, wall_n
		])
	else:
		print("OK walls delay/redirect far %.3f→%.3f cells %d→%d" % [
			open_far, wall_far, open_n, wall_n
		])


func _test_trench_redirects() -> void:
	var heights := _flat_heights()
	for x in range(0, 10):
		for z in range(0, 16):
			heights[Vector2i(x, z)] = 12.0
	for z in range(0, 16):
		heights[Vector2i(6, z)] = 8.0

	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	var terrain := _CrystalTerrainQuery.new()
	terrain.test_base_heights = heights
	_TerrainEdits.dig(6, 8, 1)
	_TerrainEdits.dig(6, 7, 1)
	_TerrainEdits.dig(6, 9, 1)
	var cfg := _CrystalSimConfig.create_default()
	cfg.pressure_flow_rate = 1.4
	cfg.downhill_flow_bonus = 0.7
	var sim := _CrystalFluidSim.new(cfg, terrain)
	sim.empty_cell_inflow_cap = 0.22
	sim.set_depth(Vector2i(0, 8), 3.5, 0, false)
	for i in 40:
		terrain.begin_sim_tick(i + 1)
		sim.tick_flow(0.28)
	var in_trench: float = sim.get_depth_at(6, 8)
	var beside: float = sim.get_depth_at(5, 5)
	if in_trench < 0.05 and sim.cell_count() < 4:
		_fail("trench should attract crystal depth trench=%.3f" % in_trench)
	else:
		print("OK trench attracts/routes crystal trench=%.3f side=%.3f" % [in_trench, beside])


func _test_gate_slows() -> void:
	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	var heights := _flat_heights()
	var terrain := _CrystalTerrainQuery.new()
	terrain.test_base_heights = heights
	var open_f: float = terrain.get_flow_factor_at(Vector2i(4, 8), _VoxelTypes.GRASS_TUFT)
	_FeatureRegistry.register_feature(4, 8, 0, {
		"player_built": true,
		"is_passage": true,
		"flow_resistance": 0.72,
		"build_id": "gate",
	})
	_TerrainEdits.set_build_tile_only(4, 8, _VoxelTypes.DIRT)
	terrain.invalidate_terrain_caches()
	var gate_f: float = terrain.get_flow_factor_at(Vector2i(4, 8), _VoxelTypes.GRASS_TUFT)
	if gate_f >= open_f - 0.1:
		_fail("gate must slow crystal open=%.3f gate=%.3f" % [open_f, gate_f])
	else:
		print("OK gate slows crystal %.3f→%.3f" % [open_f, gate_f])


func _test_water_slows() -> void:
	_ChannelRegistry.reset()
	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	var heights := _flat_heights()
	var terrain := _CrystalTerrainQuery.new()
	terrain.test_base_heights = heights
	var cfg := _CrystalSimConfig.create_default()
	terrain.sim_config = cfg
	var dry: float = terrain.get_flow_factor_at(Vector2i(3, 3), _VoxelTypes.GRASS_TUFT)
	_ChannelRegistry.register_channel(3, 3, Vector2i(1, 0), 0.9)
	terrain.invalidate_terrain_caches()
	var wet: float = terrain.get_flow_factor_at(Vector2i(3, 3), _VoxelTypes.GRASS_TUFT)
	if wet >= dry * 0.9:
		_fail("water channel must slow crystal dry=%.3f wet=%.3f" % [dry, wet])
	else:
		print("OK water interferes with crystal %.3f→%.3f" % [dry, wet])


func _test_phase_maze_to_assault() -> void:
	var gm := _GameManager.new()
	gm.assault_distance = 48.0
	gm.maze_min_distance = 72.0
	gm.phase = _GameManager.Phase.MAZE
	var p := _PlayerNear.new()
	var c := _CrystalNear.new()
	gm._player = p
	gm._crystal = c
	gm._update_phase()
	if gm.phase != _GameManager.Phase.MAZE:
		_fail("early prep must be MAZE")
	c.strength_tier = 1
	c.d = 30.0
	gm._update_phase()
	if gm.phase != _GameManager.Phase.ASSAULT:
		_fail("near pressure must enter ASSAULT")
	else:
		print("OK MAZE→ASSAULT on pressure + proximity")
	p.free()
	c.free()
	gm.free()


func _test_win_lose_authoritative() -> void:
	var gm := _GameManager.new()
	gm.max_crystal_coverage = 0.01
	var cov := _CovCrystal.new()
	gm._crystal = cov
	gm._check_crystal_overrun()
	if gm.run_state != _GameManager.RunState.LOST:
		_fail("coverage lose must remain authoritative")
	cov.free()
	gm.free()

	var gm2 := _GameManager.new()
	var c := _WinCrystal.new()
	gm2._crystal = c
	gm2._on_all_spawns_destroyed()
	if gm2.run_state != _GameManager.RunState.WON or gm2.phase != _GameManager.Phase.VICTORY:
		_fail("win path broken")
	elif c.expansion_enabled:
		_fail("win must stop expansion")
	else:
		print("OK win/lose paths still authoritative")
	c.free()
	gm2.free()
