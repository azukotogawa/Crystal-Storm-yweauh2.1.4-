extends SceneTree

const _BossBrain = preload("res://entities/boss_brain.gd")
const _Spawner = preload("res://entities/crystal_enemy_spawner.gd")
const _CrystalManager = preload("res://crystal/crystal_manager.gd")
const _GameManager = preload("res://game/game_manager.gd")
const _Def = preload("res://config/spawn_point_def.gd")
const _Spawn = preload("res://crystal/crystal_spawn_point.gd")
const _Registry = preload("res://config/spawn_point_registry.gd")

var _failed: int = 0
var _boss_cells: Array[Vector2i] = []


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL " + msg)


func _run() -> void:
	_check_ratio()
	if _failed == 0:
		await _check_spawn()
	_finish()


func _check_ratio() -> void:
	if not is_equal_approx(_BossBrain.BOSS_SPAWN_HEALTH_RATIO, 0.25):
		_fail("BOSS_SPAWN_HEALTH_RATIO expected 0.25")
		return
	if not _BossBrain.spawns_at_health_ratio(0.25):
		_fail("25%% health must spawn the boss")
		return
	if not _BossBrain.spawns_at_health_ratio(0.0):
		_fail("empty crystal health must count as the boss line")
		return
	if _BossBrain.spawns_at_health_ratio(0.2501):
		_fail("health above 25%% must not spawn the boss")
		return
	print("OK boss spawn ratio %.2f" % _BossBrain.BOSS_SPAWN_HEALTH_RATIO)


func _check_spawn() -> void:
	_Registry.ensure_builtins()
	var crystal := _CrystalManager.new()
	root.add_child(crystal)
	var player := Node3D.new()
	player.add_to_group("player")
	root.add_child(player)
	var gm := _GameManager.new()
	root.add_child(gm)
	var spawner := _Spawner.new()
	spawner.enemy_spawned.connect(_on_enemy_spawned)
	root.add_child(spawner)
	await process_frame
	await process_frame
	var crystal_def = _Def.resolved_crystal()
	var cell := Vector2i(10, -4)
	var spawn = _Spawn.from_def(1, cell, crystal_def)
	crystal.harness_setup_spawns([spawn])
	var line: float = spawn.max_health * _BossBrain.BOSS_SPAWN_HEALTH_RATIO
	crystal.damage_spawn_at_world(cell, spawn.health - (line + 1.0), 2.5)
	if spawn.health <= line:
		_fail("setup chip crossed the boss line hp=%.1f" % spawn.health)
		return
	if not get_nodes_in_group("origin_boss").is_empty():
		_fail("boss spawned above 25%%")
		return
	print("OK no boss above the line hp=%.1f" % spawn.health)

	crystal.damage_spawn_at_world(cell, spawn.health - spawn.max_health * _BossBrain.BOSS_SPAWN_HEALTH_RATIO, 2.5)
	var bosses := get_nodes_in_group("origin_boss")
	if bosses.size() != 1:
		_fail("expected one boss at 25%%, got %d" % bosses.size())
		return
	var boss: Node = bosses[0]
	boss.set_physics_process(false)
	boss.set_process(false)
	if str(boss.get("enemy_id")) != "origin_warden":
		_fail("boss id is %s" % str(boss.get("enemy_id")))
		return
	if int(boss.get("boss_phase")) != 1:
		_fail("boss brain did not start phase 1")
		return
	if _boss_cells.size() != 1:
		_fail("boss spawn signal count %d" % _boss_cells.size())
		return
	var dist := Vector2(_boss_cells[0]).distance_to(Vector2(cell))
	if dist > 3.0:
		_fail("boss spawned %.1f columns from the crystal" % dist)
		return
	print("OK boss once at %s dist=%.1f hp=%.1f" % [_boss_cells[0], dist, spawn.health])

	var before: float = spawn.health
	crystal.set_origin_warden_alive(true)
	crystal.damage_spawn_at_world(cell, 10.0, 2.5)
	if spawn.health > before - 9.0 or not spawn.active:
		_fail("crystal health stuck at %.1f while the boss lived" % spawn.health)
		return
	if gm.phase == _GameManager.Phase.VICTORY or gm.run_state != _GameManager.RunState.PLAYING:
		_fail("chipping the crystal ended the run")
		return
	if get_nodes_in_group("origin_boss").size() != 1:
		_fail("a second boss spawned")
		return
	print("OK crystal still damageable hp=%.1f" % spawn.health)

	boss.take_damage(100000.0, &"sword")
	if gm.run_state != _GameManager.RunState.PLAYING or gm.phase == _GameManager.Phase.VICTORY:
		_fail("boss death set victory")
		return
	if str(gm.victory_reason) == "boss":
		_fail("boss death set victory_reason")
		return
	var mid: Dictionary = gm.run_summary()
	if not bool(mid.get("boss_defeated", false)) or str(mid.get("outcome", "")) != "playing":
		_fail("boss death was not a playing-run stat")
		return
	print("OK boss death is a stat")

	if not crystal.damage_spawn_at_world(cell, spawn.health, 2.5):
		_fail("killing blow missed the crystal")
		return
	if gm.victory_reason != "crystal" or gm.phase != _GameManager.Phase.VICTORY or gm.run_state != _GameManager.RunState.WON:
		_fail("crystal death did not win reason=%s" % gm.victory_reason)
		return
	if not bool(gm.run_summary().get("boss_defeated", false)):
		_fail("win summary dropped boss_defeated")
		return
	print("OK crystal destruction still wins")


func _on_enemy_spawned(enemy_id: StringName, world_pos: Vector2i) -> void:
	if enemy_id == &"origin_warden":
		_boss_cells.append(world_pos)


func _finish() -> void:
	if _failed == 0:
		print("All crystal boss spawn tests OK")
		quit(0)
	else:
		push_error("verify_crystal_boss_spawn: %d failure(s)" % _failed)
		quit(1)
