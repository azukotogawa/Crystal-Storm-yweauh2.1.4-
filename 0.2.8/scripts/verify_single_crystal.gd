extends SceneTree

const _GameConfig = preload("res://config/game_config.gd")
const _Registry = preload("res://config/spawn_point_registry.gd")
const _Def = preload("res://config/spawn_point_def.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _Fluid = preload("res://crystal/crystal_fluid_sim.gd")
const _TerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _Ctrl = preload("res://crystal/spawn_point_controller.gd")
const _Spawn = preload("res://crystal/crystal_spawn_point.gd")
const _CrystalManager = preload("res://crystal/crystal_manager.gd")
const _GameManager = preload("res://game/game_manager.gd")
const _Weapon = preload("res://weapons/weapon_controller.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _SimConfig = preload("res://config/crystal_sim_config.gd")
const _Overlay = preload("res://ui/game_overlay.gd")
const _Summary = preload("res://ui/run_summary_panel.gd")
const _Map = preload("res://systems/topographical_map_builder.gd")
const _CombatFx = preload("res://systems/combat_visual_feedback.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL " + msg)


func _run() -> void:
	_check_config()
	_check_ui()
	_check_emission()
	_check_damage_victory()
	if _failed == 0:
		await _check_save_round_trip()
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


func _check_ui() -> void:
	var lines: String = _Overlay.build_single_crystal_objective_lines(
		"Maze", 120.0, 500.0, 0.1, 4, "Nearest spawn: NE  10c", true
	)
	if "Destroy the crystal" not in lines or "120/500" not in lines or "Boss warning" not in lines:
		_fail("objective lines missing crystal goal, hp, or boss warning: %s" % lines)
		return
	if "Spawns:" in lines or "sealed" in lines.to_lower() or "Nearest spawn" in lines:
		_fail("objective lines still mention spawns or a seal: %s" % lines)
		return
	var quiet: String = _Overlay.build_single_crystal_objective_lines(
		"Maze", 500.0, 500.0, 0.0, 0, "", false
	)
	if "Boss warning" in quiet or "Spawns" in quiet:
		_fail("quiet objective should not warn or count spawns: %s" % quiet)
		return
	var summary: String = _Summary.format_summary({
		"outcome": "win",
		"victory_reason": "crystal",
		"time_sec": 3.0,
		"spawns_destroyed": 1,
		"boss_defeated": true,
		"crystal_broken": 2,
		"enemies_killed": 1,
		"relics_taken": 0,
		"deaths": 0,
	})
	if "Crystal destroyed: yes" not in summary or "Boss defeated: yes" not in summary:
		_fail("run summary missing crystal win lines: %s" % summary)
		return
	if "Spawns destroyed" in summary or "sealed" in summary.to_lower():
		_fail("run summary still counts spawns: %s" % summary)
		return
	if _Map.marker_kind_for_spawn(false) != 5 or _Map.marker_kind_for_spawn(true) != 5:
		_fail("map marker is not the single crystal")
		return
	if _CombatFx.crystal_break_sfx() != "crystal_shatter":
		_fail("crystal break still uses a spawn cue")
		return
	print("OK single crystal objective, summary, map marker, break cue")


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


func _check_damage_victory() -> void:
	_Registry.ensure_builtins()
	var origin = _Registry.get_def(&"origin_boss")
	var ruin = _Registry.get_def(&"ruin_miniboss")
	var sealed = _Spawn.from_def(1, Vector2i(0, 0), origin)
	var side = _Spawn.from_def(2, Vector2i(30, 0), ruin)
	var ctrl = _Ctrl.new()
	ctrl.origin_warden_alive = true
	ctrl.set_spawns([sealed, side])
	var sealed_before: float = sealed.health
	ctrl.damage_spawn_at_world(sealed.world_pos, 25.0, 2.0)
	if sealed.health >= sealed_before - 0.01:
		_fail("damage_spawn_at_world missed a sealed crystal")
		return
	if not sealed.active:
		_fail("chip damage destroyed the sealed crystal")
		return
	if not side.active or side.health < ruin.max_health - 0.01:
		_fail("seal bypass hit a different spawn")
		return
	print("OK damage ignores seal hp %.0f→%.0f" % [sealed_before, sealed.health])

	var crystal_def = _Def.resolved_crystal()
	var cell := Vector2i(6, 6)
	var spawn = _Spawn.from_def(1, cell, crystal_def)
	if spawn.health != _Def.RELEASED_CRYSTAL_HEALTH:
		_fail("placed crystal health %.0f" % spawn.health)
		return
	var weapon_src := (_Weapon as GDScript).source_code
	if "damage_spawn_at_world" not in weapon_src or "boss_sealed" in weapon_src or "can_damage_spawn" in weapon_src:
		_fail("weapon_controller must hit damage_spawn_at_world with no seal check")
		return
	var cm := _CrystalManager.new()
	cm.harness_setup_spawns([spawn])
	var gm := _GameManager.new()
	gm._crystal = cm
	cm.all_spawns_destroyed.connect(gm._on_all_spawns_destroyed)
	var sword: Dictionary = _ItemTypes.get_def("wooden_sword")
	var chip: float = float(sword.get("damage", 0.0))
	var reach: float = float(sword.get("range", 2.0))
	var before: float = spawn.health
	cm.damage_spawn_at_world(cell, chip, reach)
	if gm.run_state != _GameManager.RunState.PLAYING or gm.phase == _GameManager.Phase.VICTORY:
		_fail("one weapon hit ended the run")
		gm.free()
		cm.free()
		return
	if spawn.health >= before - chip + 0.01:
		_fail("weapon damage_spawn_at_world missed the crystal")
		gm.free()
		cm.free()
		return
	if not cm.damage_spawn_at_world(cell, spawn.health, reach):
		_fail("killing blow missed the crystal")
		gm.free()
		cm.free()
		return
	if spawn.active:
		_fail("crystal still active after the killing blow")
		gm.free()
		cm.free()
		return
	if gm.victory_reason != "crystal":
		_fail("victory_reason expected crystal got %s" % gm.victory_reason)
		gm.free()
		cm.free()
		return
	if gm.phase != _GameManager.Phase.VICTORY:
		_fail("phase expected VICTORY")
		gm.free()
		cm.free()
		return
	if gm.run_state != _GameManager.RunState.WON:
		_fail("run_state expected WON")
		gm.free()
		cm.free()
		return
	print("OK crystal damage to victory hp %.0f→%.0f reason=%s" % [before, spawn.health, gm.victory_reason])
	gm.free()
	cm.free()


func _finish() -> void:
	if _failed == 0:
		print("All single crystal tests OK")
		quit(0)
	else:
		push_error("verify_single_crystal: %d failure(s)" % _failed)
		quit(1)


func _check_save_round_trip() -> bool:
	_Registry.ensure_builtins()
	var crystal := _CrystalManager.new()
	root.add_child(crystal)
	crystal.cancel_bootstrap()
	crystal.set_process(false)
	await process_frame
	await process_frame
	var crystal_def = _Def.resolved_crystal()
	var cell := Vector2i(12, -8)
	var spawn = _Spawn.from_def(7, cell, crystal_def)
	crystal.harness_setup_spawns([spawn])
	spawn.health = 80.0
	crystal.set_boss_spawned(true)
	var terrain = _TerrainQuery.new()
	crystal._sim = _Fluid.new(_SimConfig.create_default(), terrain)
	crystal._initialized = true
	var saved: Dictionary = crystal.export_state()
	var rows: Array = saved.get("spawns", [])
	var ok := true
	if rows.size() != 1:
		_fail("save expected 1 crystal row, got %d" % rows.size())
		ok = false
	elif absf(float(rows[0].get("health", -1.0)) - 80.0) > 0.01:
		_fail("save row health %.1f" % float(rows[0].get("health", -1.0)))
		ok = false
	elif not bool(rows[0].get("boss_spawned", false)):
		_fail("save row lost boss_spawned")
		ok = false
	elif absf(float(saved.get("crystal_health", -1.0)) - 80.0) > 0.01:
		_fail("save crystal_health %.1f" % float(saved.get("crystal_health", -1.0)))
		ok = false
	elif not bool(saved.get("boss_spawned", false)):
		_fail("save lost boss_spawned")
		ok = false
	if ok:
		spawn.health = 500.0
		crystal.set_boss_spawned(false)
		crystal.import_state(saved)
		var loaded: Array = crystal.get_active_spawns()
		if loaded.size() != 1:
			_fail("round trip expected 1 crystal, got %d" % loaded.size())
			ok = false
		elif loaded[0].world_pos != cell:
			_fail("round trip cell %s" % loaded[0].world_pos)
			ok = false
		elif absf(loaded[0].health - 80.0) > 0.01:
			_fail("round trip health %.1f" % loaded[0].health)
			ok = false
		elif not crystal.is_boss_spawned():
			_fail("round trip lost boss_spawned")
			ok = false
		elif String(loaded[0].def_id) != "released_crystal" or loaded[0].is_boss:
			_fail("round trip crystal id %s boss=%s" % [String(loaded[0].def_id), loaded[0].is_boss])
			ok = false
	if ok:
		var legacy := {
			"boss_spawned": true,
			"spawns": [
				{
					"id": 1,
					"x": 3,
					"z": 4,
					"kind": int(_CrystalTypes.SpawnKind.ORIGIN),
					"health": 140.0,
					"max_health": 500.0,
					"active": true,
					"is_boss": true,
					"def_id": "origin_boss",
					"display_name": "Origin Heart",
				},
				{
					"id": 2,
					"x": 40,
					"z": 40,
					"kind": int(_CrystalTypes.SpawnKind.RUIN),
					"health": 42.0,
					"max_health": 120.0,
					"active": true,
					"is_boss": false,
					"def_id": "ruin_miniboss",
					"display_name": "Ruin Shard",
				},
				{
					"id": 3,
					"x": -30,
					"z": 20,
					"kind": int(_CrystalTypes.SpawnKind.ARTIFACT),
					"health": 80.0,
					"max_health": 80.0,
					"active": true,
					"is_boss": false,
					"def_id": "artifact_node",
					"display_name": "Artifact Node",
				},
			],
		}
		crystal.import_state(legacy)
		var migrated: Array = crystal._spawn_points
		if migrated.size() != 1:
			_fail("multi-spawn save kept %d rows" % migrated.size())
			ok = false
		elif migrated[0].world_pos != Vector2i(3, 4):
			_fail("migration dropped the origin cell %s" % migrated[0].world_pos)
			ok = false
		elif absf(migrated[0].health - 140.0) > 0.01:
			_fail("migration health %.1f" % migrated[0].health)
			ok = false
		elif String(migrated[0].def_id) != "released_crystal" or migrated[0].is_boss:
			_fail("migration did not keep the origin as the crystal")
			ok = false
		elif not crystal.is_boss_spawned():
			_fail("migration lost boss_spawned")
			ok = false
		else:
			for item in migrated:
				if item.kind == _CrystalTypes.SpawnKind.RUIN or item.kind == _CrystalTypes.SpawnKind.ARTIFACT:
					_fail("migration kept a secondary spawn")
					ok = false
					break
	if ok:
		crystal.import_state({
			"boss_spawned": false,
			"spawns": [
				{
					"id": 2,
					"x": 9,
					"z": 9,
					"kind": int(_CrystalTypes.SpawnKind.RUIN),
					"health": 10.0,
					"max_health": 120.0,
					"active": true,
					"is_boss": false,
					"def_id": "ruin_miniboss",
				},
			],
		})
		if crystal._spawn_points.size() != 0:
			_fail("secondary-only save kept %d rows" % crystal._spawn_points.size())
			ok = false
		elif crystal.is_boss_spawned():
			_fail("secondary-only save kept boss_spawned")
			ok = false
	if ok:
		print("OK save round trip health=80 boss_spawned and origin migration")
	crystal.free()
	return ok


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
