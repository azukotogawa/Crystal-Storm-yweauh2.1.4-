extends SceneTree

const _SpawnPointRegistry = preload("res://config/spawn_point_registry.gd")
const _SpawnPointController = preload("res://crystal/spawn_point_controller.gd")
const _CrystalSpawnPoint = preload("res://crystal/crystal_spawn_point.gd")
const _CrystalManager = preload("res://crystal/crystal_manager.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalFluidSim = preload("res://crystal/crystal_fluid_sim.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _GameConfig = preload("res://config/game_config.gd")
const _SpawnPointDef = preload("res://config/spawn_point_def.gd")
const _GameManager = preload("res://game/game_manager.gd")
const _ConfigJsonIO = preload("res://systems/config_json_io.gd")
const _EnemySpawnRegistry = preload("res://entities/enemy_spawn_registry.gd")

var _failed := false
var _evidence: PackedStringArray = PackedStringArray()


func _init() -> void:
	_run_all()
	_write_evidence()
	if _failed:
		print("Spawn goal tests FAILED")
		quit(1)
	else:
		print("All spawn goal tests OK")
		quit(0)


func _run_all() -> void:
	_compile_check()
	_test_game_config_spawn_defaults()
	_test_json_spawn_roundtrip()
	if _GameConfig.SINGLE_CRYSTAL:
		_test_one_crystal_damage_and_victory()
		_test_one_crystal_save_roundtrip()
		_test_one_crystal_manager_damage()
	else:
		_test_controller_boss_gate_and_victory()
		_test_controller_save_roundtrip()
		_test_crystal_manager_damage_path()
	_test_emit_weaken_in_tick_emitters()
	_test_game_manager_victory_phase()
	_test_game_manager_coverage_lose()
	_test_full_game_spawn_defaults()


func _compile_check() -> void:
	var paths := [
		"res://crystal/spawn_point_controller.gd",
		"res://crystal/crystal_manager.gd",
		"res://config/game_config.gd",
		"res://systems/config_json_io.gd",
		"res://game/game_manager.gd",
		"res://entities/crystal_enemy_spawner.gd",
	]
	for path in paths:
		var scr: GDScript = load(path) as GDScript
		if scr == null or scr.reload() != OK:
			_fail("compile " + path)
		else:
			_log("OK compile " + path)


func _test_game_config_spawn_defaults() -> void:
	var cfg = _GameConfig.create_default()
	if cfg.spawn_points.is_empty():
		_fail("GameConfig.spawn_points empty after ensure_defaults")
		return
	if _GameConfig.SINGLE_CRYSTAL:
		var active: Array = _SpawnPointRegistry.active_defs()
		if active.size() != 1 or active[0] == null or active[0].id != &"released_crystal":
			_fail("active defs should be the one released crystal")
			return
		if absf(float(active[0].max_health) - _SpawnPointDef.RELEASED_CRYSTAL_HEALTH) > 0.01:
			_fail("released crystal health expected %.0f" % _SpawnPointDef.RELEASED_CRYSTAL_HEALTH)
			return
		if _SpawnPointRegistry.defs_for(false).size() != 3:
			_fail("flag-off defs should keep origin, ruin, and artifact")
			return
		_log("OK one crystal active id=%s health=%.0f" % [String(active[0].id), float(active[0].max_health)])
		return
	if cfg.spawn_points.size() < 3:
		_fail("GameConfig.spawn_points expected >= 3 builtins")
		return
	var has_boss := false
	for def in cfg.spawn_points:
		if def.is_boss:
			has_boss = true
	if not has_boss:
		_fail("GameConfig.spawn_points missing boss def")
		return
	_log("OK GameConfig spawn_points count=%d" % cfg.spawn_points.size())


func _test_json_spawn_roundtrip() -> void:
	var cfg = _GameConfig.create_default()
	var path := "user://test_spawn_config_roundtrip.json"
	var err := _ConfigJsonIO.export_game_config(cfg, path)
	if err != OK:
		_fail("JSON export failed err=%s" % err)
		return
	var imported = _ConfigJsonIO.import_game_config(path)
	if imported == null:
		_fail("JSON import returned null")
		return
	if imported.spawn_points.is_empty():
		_fail("JSON import lost spawn_points")
		return
	_log("OK JSON spawn_points roundtrip count=%d" % imported.spawn_points.size())


func _released_at(spawn_id: int, cell: Vector2i) -> CrystalSpawnPoint:
	return _CrystalSpawnPoint.from_def(spawn_id, cell, _SpawnPointDef.make_released())


func _make_test_spawns() -> Array:
	_SpawnPointRegistry.ensure_builtins()
	var boss_def = _SpawnPointRegistry.get_def(&"origin_boss")
	var ruin_def = _SpawnPointRegistry.get_def(&"ruin_miniboss")
	var art_def = _SpawnPointRegistry.get_def(&"artifact_node")
	return [
		_CrystalSpawnPoint.from_def(1, Vector2i.ZERO, boss_def),
		_CrystalSpawnPoint.from_def(2, Vector2i(40, 40), ruin_def),
		_CrystalSpawnPoint.from_def(3, Vector2i(-30, 20), art_def),
	]


func _test_one_crystal_damage_and_victory() -> void:
	var beside := _SpawnPointController.new()
	var heart := _released_at(1, Vector2i.ZERO)
	var ruin_def = _SpawnPointRegistry.get_def(&"ruin_miniboss")
	var ruin := _CrystalSpawnPoint.from_def(2, Vector2i(40, 40), ruin_def)
	beside.set_spawns([heart, ruin])
	var progress: Dictionary = beside.get_progress()
	if bool(progress.get("boss_sealed", false)):
		_fail("one crystal must not seal while a ruin remains")
		return
	var before: float = heart.health
	beside.damage_spawn_at_world(heart.world_pos, 25.0, 2.0)
	if heart.health >= before - 0.01:
		_fail("one crystal must take damage beside a ruin")
		return
	beside.damage_spawn_at_world(ruin.world_pos, 500.0, 2.0)
	if beside.emit_weaken_mult < 1.0:
		_fail("ruin destroy must not weaken the one crystal")
		return

	var ctrl := _SpawnPointController.new()
	var crystal := _released_at(1, Vector2i.ZERO)
	ctrl.set_spawns([crystal])
	var state := {"victory": false}
	ctrl.all_spawns_destroyed.connect(func(): state.victory = true)
	ctrl.damage_spawn_at_world(crystal.world_pos, crystal.health, 2.0)
	if not state.victory:
		_fail("destroying the one crystal should fire all_spawns_destroyed")
		return
	if ctrl.get_active_spawns().size() != 0:
		_fail("no active crystal after it is destroyed")
		return
	_log("OK one crystal damage and victory")


func _test_one_crystal_save_roundtrip() -> void:
	var ctrl := _SpawnPointController.new()
	var crystal := _released_at(1, Vector2i.ZERO)
	crystal.health = 80.0
	var ruin := _CrystalSpawnPoint.from_def(2, Vector2i(40, 40), _SpawnPointRegistry.get_def(&"ruin_miniboss"))
	ruin.health = 42.0
	ctrl.set_spawns([crystal, ruin])
	ctrl.boss_spawned = true
	ctrl.last_destroyed_label = "Crystal"
	var rows: Array = ctrl.export_spawn_rows()
	if rows.size() != 1:
		_fail("one crystal save should keep a single row, got %d" % rows.size())
		return
	if absf(float(rows[0].get("health", -1.0)) - 80.0) > 0.001:
		_fail("one crystal save lost health")
		return
	if not bool(rows[0].get("boss_spawned", false)):
		_fail("one crystal save lost boss_spawned")
		return
	var meta: Dictionary = ctrl.export_meta()
	if absf(float(meta.get("crystal_health", -1.0)) - 80.0) > 0.001 or not bool(meta.get("boss_spawned", false)):
		_fail("one crystal meta lost health or boss_spawned")
		return
	if str(meta.get("last_destroyed_label", "")) != "Crystal":
		_fail("one crystal meta lost last_destroyed_label")
		return
	var legacy: Array = [
		{"kind": int(_CrystalTypes.SpawnKind.ORIGIN), "def_id": "origin_boss", "is_boss": true, "health": 140.0},
		{"kind": int(_CrystalTypes.SpawnKind.RUIN), "def_id": "ruin_miniboss", "is_boss": false, "health": 42.0},
	]
	var kept: Array = ctrl.keep_origin_save_rows(legacy)
	if kept.size() != 1 or absf(float(kept[0].get("health", -1.0)) - 140.0) > 0.001:
		_fail("multi-spawn save should keep only the origin row")
		return
	_log("OK one crystal save row health=80")


func _test_one_crystal_manager_damage() -> void:
	var cm := _CrystalManager.new()
	var crystal := _released_at(1, Vector2i.ZERO)
	cm.harness_setup_spawns([crystal])
	var state := {"victory": false}
	cm.all_spawns_destroyed.connect(func(): state.victory = true)
	var before: float = crystal.health
	cm.damage_spawn_at_world(crystal.world_pos, 40.0, 2.0)
	if crystal.health >= before - 0.01:
		_fail("CrystalManager should damage the one crystal with no seal")
		return
	if state.victory:
		_fail("a chip of crystal health must not win")
		return
	if not cm.damage_spawn_at_world(crystal.world_pos, crystal.health, 2.0):
		_fail("CrystalManager should destroy the one crystal")
		return
	if not state.victory:
		_fail("CrystalManager should win when the one crystal is destroyed")
		return
	_log("OK CrystalManager one crystal victory")


func _test_controller_boss_gate_and_victory() -> void:
	var ctrl := _SpawnPointController.new()
	var spawns := _make_test_spawns()
	ctrl.set_spawns(spawns)

	var state := {"victory": false}
	ctrl.all_spawns_destroyed.connect(func(): state.victory = true)

	var boss: CrystalSpawnPoint = spawns[0]
	if ctrl.damage_spawn_at_world(boss.world_pos, 999.0, 2.0):
		_fail("boss should be sealed while minibosses remain")
		return
	if ctrl.count_active_non_boss() == 0:
		_fail("non-boss spawns should still be active")
		return
	_log("OK boss gate blocked early damage")

	var ruin: CrystalSpawnPoint = spawns[1]
	var art: CrystalSpawnPoint = spawns[2]
	ctrl.damage_spawn_at_world(ruin.world_pos, 500.0, 2.0)
	ctrl.damage_spawn_at_world(art.world_pos, 500.0, 2.0)
	if ctrl.count_active_non_boss() > 0:
		_fail("non-boss spawns should be destroyed")
		return
	var weaken_before_boss: float = ctrl.emit_weaken_mult
	if weaken_before_boss >= 1.0:
		_fail("emit weaken should drop after non-boss kills")
		return

	ctrl.damage_spawn_at_world(boss.world_pos, 999.0, 2.0)
	if not state.victory:
		_fail("all_spawns_destroyed should fire after boss kill")
		return
	if ctrl.get_active_spawns().size() != 0:
		_fail("no active spawns after victory sequence")
		return
	_log("OK controller victory path emit x%.2f" % ctrl.emit_weaken_mult)


func _test_controller_save_roundtrip() -> void:
	var ctrl := _SpawnPointController.new()
	var spawns := _make_test_spawns()
	spawns[1].health = 42.0
	spawns[1].active = true
	ctrl.set_spawns(spawns)
	ctrl.emit_weaken_mult = 0.88
	ctrl.last_destroyed_label = "Ruin Shard"

	var rows: Array = ctrl.export_spawn_rows()
	var meta: Dictionary = ctrl.export_meta()
	var restored := _SpawnPointController.new()
	var rebuilt: Array = []
	_SpawnPointRegistry.ensure_builtins()
	for row in rows:
		var def_id: StringName = StringName(str(row.get("def_id", "")))
		var def = _SpawnPointRegistry.get_def(def_id)
		var spawn: CrystalSpawnPoint
		if def:
			spawn = _CrystalSpawnPoint.from_def(int(row.id), Vector2i(int(row.x), int(row.z)), def)
		else:
			spawn = _CrystalSpawnPoint.new(
				int(row.id), Vector2i(int(row.x), int(row.z)),
				int(row.kind), float(row.max_health), bool(row.is_boss)
			)
		spawn.health = float(row.health)
		spawn.active = bool(row.active)
		rebuilt.append(spawn)
	restored.set_spawns(rebuilt)
	restored.import_meta(meta)

	if absf(restored.emit_weaken_mult - 0.88) > 0.001:
		_fail("save roundtrip lost emit_weaken_mult")
		return
	if restored.last_destroyed_label != "Ruin Shard":
		_fail("save roundtrip lost last_destroyed_label")
		return
	if absf(rebuilt[1].health - 42.0) > 0.001:
		_fail("save roundtrip lost partial health")
		return
	_log("OK controller save roundtrip health=%.0f emit x%.2f" % [rebuilt[1].health, restored.emit_weaken_mult])


func _test_crystal_manager_damage_path() -> void:
	var cm := _CrystalManager.new()
	var spawns := _make_test_spawns()
	cm.harness_setup_spawns(spawns)

	var mgr_state := {"victory": false}
	cm.all_spawns_destroyed.connect(func(): mgr_state.victory = true)

	var boss: CrystalSpawnPoint = spawns[0]
	if cm.damage_spawn_at_world(boss.world_pos, 500.0, 2.0):
		_fail("CrystalManager should respect boss gate")
		return

	for s in spawns:
		if s.is_boss:
			continue
		cm.damage_spawn_at_world(s.world_pos, 500.0, 2.0)

	cm.damage_spawn_at_world(boss.world_pos, 500.0, 2.0)
	if not mgr_state.victory:
		_fail("CrystalManager.damage_spawn_at_world should trigger victory")
		return
	_log("OK CrystalManager.damage_spawn_at_world victory")


func _test_emit_weaken_in_tick_emitters() -> void:
	var cfg = _CrystalSimConfig.create_default()
	var tq = _CrystalTerrainQuery.new()
	var sim = _CrystalFluidSim.new(cfg, tq)
	_SpawnPointRegistry.ensure_builtins()
	var spawn = _CrystalSpawnPoint.from_def(9, Vector2i(5, 5), _SpawnPointRegistry.get_def(&"origin_boss"))
	var list: Array = [spawn]
	sim.set_depth(spawn.world_pos, 1.0, spawn.id)
	sim.tick_emitters(list, 1.0, 0.5)
	var depth_weak: float = sim.get_depth_at(spawn.world_pos.x, spawn.world_pos.y)
	sim.set_depth(spawn.world_pos, 1.0, spawn.id)
	sim.tick_emitters(list, 1.0, 1.0)
	var depth_full: float = sim.get_depth_at(spawn.world_pos.x, spawn.world_pos.y)
	if depth_weak >= depth_full:
		_fail("tick_emitters weaken mult should reduce emit depth gain")
		return
	_log("OK tick_emitters weaken depth weak=%.3f full=%.3f" % [depth_weak, depth_full])


func _test_game_manager_victory_phase() -> void:
	var gm = _GameManager.new()
	gm._on_all_spawns_destroyed()
	if gm.run_state != _GameManager.RunState.WON:
		_fail("GameManager should set RunState.WON")
		return
	if gm.phase != _GameManager.Phase.VICTORY:
		_fail("GameManager should set Phase.VICTORY")
		return
	if _GameConfig.SINGLE_CRYSTAL and gm.victory_reason != "crystal":
		_fail("one crystal victory_reason expected crystal got %s" % gm.victory_reason)
		return
	_log("OK GameManager Phase.VICTORY + RunState.WON")


func _test_game_manager_coverage_lose() -> void:
	var gm = _GameManager.new()
	gm.max_crystal_coverage = 0.01
	var cm := _CrystalManager.new()
	cm.covered_cells = 50000
	gm._crystal = cm
	gm._check_crystal_overrun()
	if gm.run_state != _GameManager.RunState.PLAYING or gm.coverage_warning == "":
		_fail("coverage overrun must warn and keep PLAYING")
		return
	_log("OK coverage over max stays PLAYING")


func _test_full_game_spawn_defaults() -> void:
	var cfg = _CrystalSimConfig.create_default()
	if _GameConfig.SINGLE_CRYSTAL:
		if _SpawnPointRegistry.active_defs().size() != 1:
			_fail("full game should place one crystal")
			return
		_log("OK one crystal run; ruin=%d artifact=%d stay as pressure scale only" % [cfg.ruin_spawn_count, cfg.artifact_spawn_count])
		return
	if cfg.ruin_spawn_count < 1 or cfg.artifact_spawn_count < 1:
		_fail("full game needs ruin and artifact spawn counts")
		return
	_log("OK full game spawn defaults ruin=%d artifact=%d" % [cfg.ruin_spawn_count, cfg.artifact_spawn_count])


func _log(msg: String) -> void:
	print(msg)
	_evidence.append(msg)


func _fail(msg: String) -> void:
	push_error(msg)
	_evidence.append("FAIL: " + msg)
	_failed = true


func _write_evidence() -> void:
	var path := "/tmp/grok-goal-fbabd0fc2e6e/implementer/launch.log"
	var text := "Spawn goal verification evidence\n" + "\n".join(_evidence) + "\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)