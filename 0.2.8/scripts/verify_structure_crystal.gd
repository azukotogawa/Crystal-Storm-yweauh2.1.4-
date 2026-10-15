extends SceneTree

const _Integrity = preload("res://helpers/structure_integrity.gd")
const _Features = preload("res://world/feature_registry.gd")
const _Fluid = preload("res://crystal/crystal_fluid_sim.gd")
const _Terrain = preload("res://crystal/crystal_terrain_query.gd")
const _Config = preload("res://config/crystal_sim_config.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL " + msg)


func _run() -> void:
	_test_spread_goes_around()
	_test_block_factor_is_config()
	_test_passage_stays_open()
	_test_erode_rate_is_config()
	_test_manager_uses_config()
	if _failed == 0:
		print("All structure crystal tests OK")
		quit(0)
	else:
		push_error("verify_structure_crystal: %d failure(s)" % _failed)
		quit(1)


func _test_spread_goes_around() -> void:
	_clear()
	var wall := Vector2i(5, 5)
	_Integrity.bind(&"wall_segment", wall, [{"at": Vector3i(5, 0, 5), "role": "wall"}])
	var blocked = _spread_from(Vector2i(4, 5), 0.0)
	var min_d: float = blocked.config.min_depth
	if float(blocked.depth.get(wall, 0.0)) >= min_d:
		_fail("crystal entered the structure cell depth=%.3f" % float(blocked.depth.get(wall, 0.0)))
		return
	if float(blocked.depth.get(Vector2i(6, 5), 0.0)) < min_d:
		_fail("crystal did not reach the far side of the structure")
		return
	if float(blocked.depth.get(Vector2i(5, 4), 0.0)) < min_d and float(blocked.depth.get(Vector2i(5, 6), 0.0)) < min_d:
		_fail("crystal did not grow along the side of the structure")
		return
	_clear()
	var open = _spread_from(Vector2i(4, 5), 0.0)
	if float(open.depth.get(wall, 0.0)) < open.config.min_depth:
		_fail("the same cell must accept crystal when it is not a structure")
		return
	print("OK crystal grows around a structure cell and not through it")


func _test_block_factor_is_config() -> void:
	_clear()
	var wall := Vector2i(5, 5)
	_Integrity.bind(&"wall_segment", wall, [{"at": Vector3i(5, 0, 5), "role": "wall"}])
	var cfg := _Config.create_default()
	if not is_equal_approx(cfg.structure_block_flow_factor, 0.0):
		_fail("structure block flow factor must default to 0")
		return
	var terrain := _Terrain.new()
	terrain.sim_config = cfg
	terrain.begin_sim_tick(1)
	var blocked: float = terrain.get_flow_factor_at(wall, _VoxelTypes.GRASS_TUFT)
	var open: float = terrain.get_flow_factor_at(Vector2i(4, 5), _VoxelTypes.GRASS_TUFT)
	if not is_equal_approx(blocked, 0.0) or open <= 0.2:
		_fail("structure flow blocked=%.3f open=%.3f" % [blocked, open])
		return
	cfg.structure_block_flow_factor = 0.4
	terrain.begin_sim_tick(2)
	var slowed: float = terrain.get_flow_factor_at(wall, _VoxelTypes.GRASS_TUFT)
	if not is_equal_approx(slowed, 0.4):
		_fail("structure block flow factor config was %.3f" % slowed)
		return
	print("OK structure cells use the config block flow factor")


func _test_passage_stays_open() -> void:
	_clear()
	_Integrity.bind(&"gate", Vector2i(2, 2), [{"at": Vector3i(2, 0, 2), "role": "passage"}])
	var cfg := _Config.create_default()
	var terrain := _Terrain.new()
	terrain.sim_config = cfg
	terrain.begin_sim_tick(1)
	var factor: float = terrain.get_flow_factor_at(Vector2i(2, 2), _VoxelTypes.GRASS_TUFT)
	if factor <= 0.05:
		_fail("a structure passage must not hard-block crystal factor=%.3f" % factor)
		return
	print("OK a structure passage stays open to crystal")


func _test_erode_rate_is_config() -> void:
	_clear()
	var wall := Vector2i(8, 8)
	_Integrity.bind(&"wall_segment", wall, [{"at": Vector3i(8, 0, 8), "role": "wall"}])
	var cfg := _Config.create_default()
	if not is_equal_approx(cfg.structure_erode_rate, 1.0):
		_fail("structure erode rate must default to 1 HP per second")
		return
	var sim := _Fluid.new(cfg, _Terrain.new())
	sim.set_depth(Vector2i(7, 8), cfg.initial_spawn_depth, 1, false)
	var before := int(_Integrity.record_at(wall).get("structure_hp", 0))
	_Integrity.erode_pressed(sim, cfg.min_depth, cfg.structure_erode_rate * 0.4, null)
	_Integrity.erode_pressed(sim, cfg.min_depth, cfg.structure_erode_rate * 0.4, null)
	if int(_Integrity.record_at(wall).get("structure_hp", 0)) != before:
		_fail("two short presses must bank erosion without spending a hit point")
		return
	_Integrity.erode_pressed(sim, cfg.min_depth, cfg.structure_erode_rate * 0.4, null)
	if int(_Integrity.record_at(wall).get("structure_hp", 0)) != before - 1:
		_fail("the config rate must spend 1 HP after one second of contact")
		return
	cfg.structure_erode_rate = 0.0
	var held := int(_Integrity.record_at(wall).get("structure_hp", 0))
	_Integrity.erode_pressed(sim, cfg.min_depth, cfg.structure_erode_rate * 1.0, null)
	if int(_Integrity.record_at(wall).get("structure_hp", 0)) != held:
		_fail("a zero erode rate must not damage the structure")
		return
	sim.set_depth(Vector2i(7, 8), 0.0, 1, false)
	cfg.structure_erode_rate = 4.0
	_Integrity.erode_pressed(sim, cfg.min_depth, cfg.structure_erode_rate * 1.0, null)
	if int(_Integrity.record_at(wall).get("structure_hp", 0)) != held:
		_fail("crystal that is not touching the structure must not erode it")
		return
	print("OK crystal erodes a pressed structure at the config rate")


func _test_manager_uses_config() -> void:
	var crystal := str((load("res://crystal/crystal_manager.gd") as GDScript).source_code)
	var terrain := str((load("res://crystal/crystal_terrain_query.gd") as GDScript).source_code)
	if "erode_pressed" not in crystal or "structure_erode_rate" not in crystal:
		_fail("crystal spread must erode structures at structure_erode_rate")
		return
	if "_structure_block_factor" not in terrain or "structure_block_flow_factor" not in terrain:
		_fail("crystal spread must read the structure block flow factor")
		return
	print("OK crystal spread blocks on structure cells and erodes from the config")


func _spread_from(origin: Vector2i, block_factor: float):
	var cfg := _Config.create_default()
	cfg.structure_block_flow_factor = block_factor
	var terrain := _Terrain.new()
	terrain.sim_config = cfg
	var sim := _Fluid.new(cfg, terrain)
	sim.max_new_cells_per_tick = 0
	sim.set_depth(origin, cfg.initial_spawn_depth, 1, false)
	for _i in 36:
		terrain.begin_sim_tick(_i + 1)
		sim.tick_flow(0.25)
	return sim


func _clear() -> void:
	_Features.reset()
	_Integrity.reset()
