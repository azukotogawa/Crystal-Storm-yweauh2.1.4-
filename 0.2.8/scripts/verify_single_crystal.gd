extends SceneTree

const _GameConfig = preload("res://config/game_config.gd")
const _Registry = preload("res://config/spawn_point_registry.gd")
const _Def = preload("res://config/spawn_point_def.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _Fluid = preload("res://crystal/crystal_fluid_sim.gd")
const _TerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _Ctrl = preload("res://crystal/spawn_point_controller.gd")
const _Spawn = preload("res://crystal/crystal_spawn_point.gd")
const _SimConfig = preload("res://config/crystal_sim_config.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL " + msg)


func _run() -> void:
	_check_config()
	_check_emission()
	if _failed == 0:
		await _check_world_start()
	_finish()


func _check_config() -> void:
	if not _GameConfig.SINGLE_CRYSTAL:
		_fail("SINGLE_CRYSTAL must default on")
		return
	var one = _Def.resolved_crystal()
	if one == null:
		_fail("SpawnPointDef did not return the crystal")
		return
	if one.max_health != _Def.RELEASED_CRYSTAL_HEALTH:
		_fail("crystal health expected %.0f got %.0f" % [_Def.RELEASED_CRYSTAL_HEALTH, one.max_health])
		return
	if one.position_rule != _Def.POSITION_RULE_ORIGIN_CELL:
		_fail("crystal position rule expected origin_cell")
		return
	var defs: Array = _Registry.active_defs()
	if defs.size() != 1:
		_fail("registry expected one crystal def, got %d" % defs.size())
		return
	if defs[0] == null or defs[0].id != one.id or defs[0].max_health != one.max_health:
		_fail("registry crystal def does not match SpawnPointDef")
		return
	if String(defs[0].position_rule) != String(one.position_rule):
		_fail("registry crystal def missing position rule")
		return
	var legacy: Array = _Registry.defs_for(false)
	if legacy.size() != 3:
		_fail("legacy multi-spawn defs not reachable, got %d" % legacy.size())
		return
	var ids: PackedStringArray = PackedStringArray()
	for item in legacy:
		if item == null:
			_fail("legacy def missing")
			return
		ids.append(String(item.id))
	if not ids.has("origin_boss") or not ids.has("ruin_miniboss") or not ids.has("artifact_node"):
		_fail("legacy defs missing a spawn id")
		return
	if _Registry.get_def(&"origin_boss") == null or _Registry.get_def(&"released_crystal") == null:
		_fail("registry dropped a crystal def")
		return
	print("OK one crystal health=%.0f rule=%s" % [one.max_health, String(one.position_rule)])


func _check_emission() -> void:
	_Registry.ensure_builtins()
	var origin = _Registry.get_def(&"origin_boss")
	var ruin = _Registry.get_def(&"ruin_miniboss")
	var art = _Registry.get_def(&"artifact_node")
	var spawns: Array = [
		_Spawn.from_def(1, Vector2i(0, 0), origin),
		_Spawn.from_def(2, Vector2i(80, 0), ruin),
		_Spawn.from_def(3, Vector2i(0, 90), ruin),
		_Spawn.from_def(4, Vector2i(-70, 40), art),
	]
	var cfg = _SimConfig.create_default()
	var terrain = _TerrainQuery.new()
	terrain.sim_config = cfg
	var sim = _Fluid.new(cfg, terrain)
	for spawn in spawns:
		sim.set_depth(spawn.world_pos, 1.0, spawn.id, false)
	sim.tick_emitters(spawns, 1.0, 1.0)
	var expected := 6.1
	var got: float = sim.get_depth_at(0, 0)
	if absf(got - (1.0 + expected)) > 0.05:
		_fail("one emitter depth %.3f expected %.3f" % [got, 1.0 + expected])
		return
	if absf(sim.get_depth_at(80, 0) - 1.0) > 0.001:
		_fail("secondary ruin emitter still ran")
		return
	if absf(sim.get_depth_at(0, 90) - 1.0) > 0.001:
		_fail("second ruin emitter still ran")
		return
	if absf(sim.get_depth_at(-70, 40) - 1.0) > 0.001:
		_fail("artifact emitter still ran")
		return
	spawns[0].active = false
	sim.set_depth(spawns[1].world_pos, 1.0, spawns[1].id, false)
	sim.tick_emitters(spawns, 1.0, 1.0)
	var ruin_depth: float = sim.get_depth_at(80, 0)
	if absf(ruin_depth - (1.0 + expected)) > 0.05:
		_fail("fallback emitter depth %.3f expected %.3f" % [ruin_depth, 1.0 + expected])
		return
	var gated: Array = [
		_Spawn.from_def(1, Vector2i(0, 0), origin),
		_Spawn.from_def(2, Vector2i(40, 40), ruin),
		_Spawn.from_def(3, Vector2i(-30, 20), art),
	]
	var ctrl = _Ctrl.new()
	ctrl.set_spawns(gated)
	if ctrl.count_active_non_boss() != 0:
		_fail("single crystal still counts secondary spawns")
		return
	var prog: Dictionary = ctrl.get_progress()
	if bool(prog.get("boss_sealed", true)):
		_fail("boss_sealed still set with one crystal")
		return
	if not ctrl.can_damage_spawn(gated[0]):
		_fail("origin spawn stayed sealed")
		return
	var weaken_before: float = ctrl.emit_weaken_mult
	ctrl.damage_spawn_at_world(gated[1].world_pos, 500.0, 2.0)
	if absf(ctrl.emit_weaken_mult - weaken_before) > 0.001:
		_fail("weaken_factor still reduced emission")
		return
	print("OK one emitter pressure=%.1f secondaries unchanged" % expected)


func _finish() -> void:
	if _failed == 0:
		print("All single crystal tests OK")
		quit(0)
	else:
		push_error("verify_single_crystal: %d failure(s)" % _failed)
		quit(1)


func _check_world_start() -> bool:
	var world := InfiniteNoiseWorld.new()
	world.apply_seed(1)
	root.add_child(world)
	var crystal := CrystalManager.new()
	crystal.world = world
	root.add_child(crystal)
	var terrain = _TerrainQuery.new()
	terrain.world = world
	crystal._sim = _Fluid.new(crystal.sim_config, terrain)
	var origin: Vector2i = crystal.pick_origin_spawn_cell()
	crystal._initialize_spawns()
	await process_frame
	await process_frame
	var active: Array = crystal.get_active_spawns()
	var ok := true
	if active.size() != 1:
		_fail("world start expected 1 active crystal, got %d" % active.size())
		ok = false
	elif active[0].world_pos != origin:
		_fail("crystal cell %s is not origin %s" % [active[0].world_pos, origin])
		ok = false
	elif String(active[0].def_id) != "released_crystal":
		_fail("placed crystal id %s" % String(active[0].def_id))
		ok = false
	elif active[0].is_boss:
		_fail("placed crystal is still a boss")
		ok = false
	elif crystal._spawn_points.size() != 1:
		_fail("world start placed %d spawns" % crystal._spawn_points.size())
		ok = false
	else:
		for spawn in crystal._spawn_points:
			if spawn.kind == _CrystalTypes.SpawnKind.RUIN or spawn.kind == _CrystalTypes.SpawnKind.ARTIFACT:
				_fail("ruin or artifact spawn placed in single crystal mode")
				ok = false
				break
	if ok:
		print("OK world start one crystal at %s" % origin)
	crystal.cancel_bootstrap()
	await process_frame
	crystal.free()
	world.free()
	return ok
