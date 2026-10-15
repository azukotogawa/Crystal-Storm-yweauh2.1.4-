extends SceneTree

const _GameConfig = preload("res://config/game_config.gd")
const _Registry = preload("res://config/spawn_point_registry.gd")
const _Def = preload("res://config/spawn_point_def.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _Fluid = preload("res://crystal/crystal_fluid_sim.gd")
const _TerrainQuery = preload("res://crystal/crystal_terrain_query.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL " + msg)


func _run() -> void:
	_check_config()
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
