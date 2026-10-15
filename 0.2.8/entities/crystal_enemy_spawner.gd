class_name CrystalEnemySpawner
extends Node

const _CrystalEnemy = preload("res://entities/crystal_enemy.gd")
const _EnemySpawnRegistry = preload("res://entities/enemy_spawn_registry.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _WorldVisualCoords = preload("res://helpers/world_visual_coords.gd")


signal enemy_spawned(enemy_id: StringName, world_pos: Vector2i)
signal enemy_killed(enemy_id: StringName, world_pos: Vector2i, player_killed: bool)

@export var spawn_interval: float = 8.0
@export var max_active: int = 24
@export var spawn_near_player_min: float = 3.0
@export var spawn_near_player_max: float = 10.0
@export var require_crystal_depth: float = 0.2
@export var assault_spawn_mult: float = 1.6
@export var spawn_grace_sec: float = 28.0

var _timer: float = 0.0
var _grace_elapsed: float = 0.0
var _active: Array[Node3D] = []
var _crystal: CrystalManager
var _player: Node3D
var _world: InfiniteNoiseWorld
var _game_manager: GameManager
var _first_spawn_announced: bool = false
var _guarded_spawn_ids: Dictionary = {}
var _guardian_timer: float = 0.0


func _ready() -> void:
	add_to_group("crystal_enemy_spawner")
	_EnemySpawnRegistry.ensure_builtins()
	call_deferred("_bind")


func _bind() -> void:
	_crystal = get_tree().get_first_node_in_group("crystal_manager")
	_player = get_tree().get_first_node_in_group("player")
	_world = get_tree().get_first_node_in_group("world")
	_game_manager = get_tree().get_first_node_in_group("game_manager")
	if _crystal and _crystal.has_method("get_evolution"):
		var evo = _crystal.get_evolution()
		if evo and not evo.enemy_unlocked.is_connected(_on_enemy_unlocked):
			evo.enemy_unlocked.connect(_on_enemy_unlocked)


func _process(delta: float) -> void:
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("enemy_spawner")
	_prune_active()
	if _crystal == null or _player == null:
		if profiler and profiler.has_method("end"):
			profiler.end("enemy_spawner")
		return
	_grace_elapsed += delta
	var in_grace := _grace_elapsed < spawn_grace_sec
	_tick_guardians(delta, in_grace)
	if in_grace:
		if profiler and profiler.has_method("end"):
			profiler.end("enemy_spawner")
		return
	var evolution = _crystal.get_evolution() if _crystal.has_method("get_evolution") else null
	if evolution == null or evolution.unlocked_enemies.is_empty():
		if profiler and profiler.has_method("end"):
			profiler.end("enemy_spawner")
		return
	if _active.size() >= max_active:
		if profiler and profiler.has_method("end"):
			profiler.end("enemy_spawner")
		return

	var interval := spawn_interval
	if _game_manager and _game_manager.phase == GameManager.Phase.ASSAULT:
		interval /= assault_spawn_mult
	interval /= _spawn_pressure_mult()
	interval /= _biome_mob_mult()

	_timer += delta
	if _timer < interval:
		if profiler and profiler.has_method("end"):
			profiler.end("enemy_spawner")
		return
	_timer = 0.0

	var col := _player_column_pos()
	var depth := _crystal.get_depth_at(floori(col.x), floori(col.y))
	if depth < require_crystal_depth:
		# Column-space distance (depth map is keyed by column, not world units).
		var near_col := _nearest_crystal_column_distance(col)
		if near_col > spawn_near_player_max:
			if profiler and profiler.has_method("end"):
				profiler.end("enemy_spawner")
			return

	var tier: int = _crystal.strength_tier if "strength_tier" in _crystal else 0
	var enemy_id: StringName = _EnemySpawnRegistry.pick_weighted(evolution.unlocked_enemies, tier)
	if enemy_id == &"":
		enemy_id = evolution.unlocked_enemies[0]
	_spawn_enemy(enemy_id)
	if profiler and profiler.has_method("end"):
		profiler.end("enemy_spawner")


func _on_enemy_unlocked(enemy_id: StringName) -> void:
	# Don't dump a death burst during early orientation grace.
	if _grace_elapsed < spawn_grace_sec:
		return
	var def = _EnemySpawnRegistry.get_def(enemy_id)
	var burst := 1
	if _crystal and _crystal.has_method("get_evolution"):
		var evo = _crystal.get_evolution()
		for entry in evo.unlock_table:
			if entry.enemy_id == enemy_id:
				burst = maxi(int(entry.spawn_burst), 1)
				break
	for _i in burst:
		if _active.size() >= max_active:
			break
		_spawn_enemy(enemy_id)


func spawn_enemy_now(enemy_id: StringName = &"") -> bool:
	_bind()
	if _crystal == null or _player == null:
		return false
	var evolution = _crystal.get_evolution() if _crystal.has_method("get_evolution") else null
	if enemy_id == &"":
		if evolution == null or evolution.unlocked_enemies.is_empty():
			return false
		var tier: int = _crystal.strength_tier if "strength_tier" in _crystal else 0
		enemy_id = _EnemySpawnRegistry.pick_weighted(evolution.unlocked_enemies, tier)
		if enemy_id == &"":
			enemy_id = evolution.unlocked_enemies[0]
	var before: int = _active.size()
	_spawn_enemy(enemy_id)
	_prune_active()
	return _active.size() > before


func spawn_enemy_at_column(enemy_id: StringName, wx: int, wz: int, patrol: Vector2i = Vector2i.ZERO) -> bool:
	_bind()
	if _player == null:
		return false
	if enemy_id == &"":
		enemy_id = &"crystal_mite"
	var spawn_def = _EnemySpawnRegistry.get_def(enemy_id)
	if spawn_def == null:
		return false
	if _active.size() >= max_active:
		return false
	var spawn_pos := _world_pos_for_column(wx, wz)
	if spawn_pos == Vector3.ZERO:
		return false
	var enemy: _CrystalEnemy = _CrystalEnemy.new()
	var patrol_cell := patrol if patrol != Vector2i.ZERO else Vector2i(wx, wz)
	var parent := _enemy_parent()
	parent.add_child(enemy)
	enemy.global_position = spawn_pos
	enemy.setup(enemy_id, _player, spawn_def, patrol_cell)
	if enemy.has_method("sync_spatial_index"):
		enemy.sync_spatial_index()
	if enemy.has_signal("killed") and not enemy.killed.is_connected(_on_enemy_killed):
		enemy.killed.connect(_on_enemy_killed)
	_active.append(enemy)
	enemy_spawned.emit(enemy_id, Vector2i(wx, wz))
	_first_spawn_announced = true
	return true


func _spawn_enemy(enemy_id: StringName) -> void:
	var spawn_pos := _pick_spawn_pos()
	if spawn_pos == Vector3.ZERO:
		return
	var spawn_def = _EnemySpawnRegistry.get_def(enemy_id)
	var enemy: _CrystalEnemy = _CrystalEnemy.new()
	var patrol := Vector2i.ZERO
	if _crystal:
		var spawns = _crystal.get_active_spawns()
		for s in spawns:
			if s.is_boss:
				patrol = s.world_pos
				break
		if patrol == Vector2i.ZERO and not spawns.is_empty():
			patrol = spawns[0].world_pos
	var parent := _enemy_parent()
	parent.add_child(enemy)
	enemy.global_position = spawn_pos
	enemy.setup(enemy_id, _player, spawn_def, patrol)
	if enemy.has_method("sync_spatial_index"):
		enemy.sync_spatial_index()
	if enemy.has_signal("killed") and not enemy.killed.is_connected(_on_enemy_killed):
		enemy.killed.connect(_on_enemy_killed)
	_active.append(enemy)
	var ws = _WorldSettings.get_active()
	var col := Vector2i(
		floori(ws.world_to_column(spawn_pos.x)),
		floori(ws.world_to_column(spawn_pos.z))
	)
	enemy_spawned.emit(enemy_id, col)
	_first_spawn_announced = true


func _on_enemy_killed(enemy_id: StringName, world_pos: Vector2i, player_killed: bool) -> void:
	_prune_active()
	enemy_killed.emit(enemy_id, world_pos, player_killed)


func _pick_spawn_pos() -> Vector3:
	if _crystal == null or _player == null or _world == null:
		return Vector3.ZERO
	var col := _player_column_pos()
	var px := col.x
	var pz := col.y
	var pos := _sample_crystal_ring(px, pz, spawn_near_player_min, spawn_near_player_max, 24)
	if pos != Vector3.ZERO:
		return pos
	pos = _sample_crystal_ring(px, pz, 1.0, spawn_near_player_max, 48)
	if pos != Vector3.ZERO:
		return pos
	return _scan_crystal_near_player(px, pz, int(ceil(spawn_near_player_max)))


func _sample_crystal_ring(px: float, pz: float, dmin: float, dmax: float, attempts: int) -> Vector3:
	for _attempt in attempts:
		var angle := randf() * TAU
		var dist := randf_range(dmin, dmax)
		var wx := int(floor(px + cos(angle) * dist))
		var wz := int(floor(pz + sin(angle) * dist))
		if _crystal.get_depth_at(wx, wz) < require_crystal_depth:
			continue
		return _world_pos_for_column(wx, wz)
	return Vector3.ZERO


func _scan_crystal_near_player(px: float, pz: float, max_r: int) -> Vector3:
	var pcx := int(floor(px))
	var pcz := int(floor(pz))
	for r in range(1, maxi(max_r, 2) + 1):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var wx := pcx + dx
				var wz := pcz + dz
				if _crystal.get_depth_at(wx, wz) < require_crystal_depth:
					continue
				return _world_pos_for_column(wx, wz)
	return Vector3.ZERO


func _world_pos_for_column(wx: int, wz: int) -> Vector3:
	var col_x := float(wx) + 0.5
	var col_z := float(wz) + 0.5
	var y := TerrainRamps.walkable_height(_world, col_x, col_z)
	return _WorldVisualCoords.column_to_world_pos(col_x, y, col_z)


func _enemy_parent() -> Node:
	var visuals = get_tree().get_first_node_in_group("world_visuals_root")
	if visuals and visuals.has_method("get_entities_root"):
		return visuals.get_entities_root()
	var scene := get_tree().current_scene
	return scene if scene != null else self


func export_enemies() -> Array:
	_prune_active()
	var out: Array = []
	for enemy in _active:
		if not is_instance_valid(enemy):
			continue
		var row := {
			"enemy_id": str(enemy.enemy_id),
			"x": enemy.global_position.x,
			"y": enemy.global_position.y,
			"z": enemy.global_position.z,
			"health": enemy.health,
		}
		if enemy.has_meta("guard_spawn_id"):
			row["guard_spawn_id"] = int(enemy.get_meta("guard_spawn_id"))
		out.append(row)
	return out


func import_enemies(rows: Array) -> void:
	if rows.is_empty():
		return
	_guarded_spawn_ids.clear()
	_guardian_timer = 1.0
	_prune_active()
	for enemy in _active:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_active.clear()
	if _player == null:
		_bind()
	for row in rows:
		if not row is Dictionary:
			continue
		var enemy_id: StringName = StringName(str(row.get("enemy_id", "crystal_mite")))
		var spawn_def = _EnemySpawnRegistry.get_def(enemy_id)
		var enemy: _CrystalEnemy = _CrystalEnemy.new()
		var parent := _enemy_parent()
		parent.add_child(enemy)
		enemy.global_position = Vector3(
			float(row.get("x", 0.0)),
			float(row.get("y", 1.0)),
			float(row.get("z", 0.0))
		)
		enemy.setup(enemy_id, _player, spawn_def)
		if row.has("health"):
			enemy.health = float(row.health)
		if row.has("guard_spawn_id"):
			var guard_id := int(row["guard_spawn_id"])
			enemy.set_meta("guard_spawn_id", guard_id)
			var heart = _column_for_spawn_id(guard_id)
			if heart is Vector2i and enemy.has_method("bind_heart"):
				enemy.bind_heart(heart)
		if enemy.has_method("sync_spatial_index"):
			enemy.sync_spatial_index()
		_active.append(enemy)


func get_active_count() -> int:
	_prune_active()
	return _active.size()


func _prune_active() -> void:
	var kept: Array[Node3D] = []
	for e in _active:
		if is_instance_valid(e):
			kept.append(e)
	_active = kept


func _tick_guardians(delta: float, in_grace: bool) -> void:
	if _game_manager == null:
		_game_manager = get_tree().get_first_node_in_group("game_manager")
	if _game_manager == null or _game_manager.run_state != GameManager.RunState.PLAYING:
		return
	_sync_warden_alive()
	if in_grace:
		return
	_guardian_timer += delta
	if _guardian_timer < 1.0:
		return
	_guardian_timer = 0.0
	_try_spawn_guardians()


func _column_for_spawn_id(spawn_id: int) -> Variant:
	if _crystal == null:
		_bind()
	if _crystal == null or not _crystal.has_method("get_active_spawns"):
		return null
	for spawn in _crystal.get_active_spawns():
		if int(spawn.id) == spawn_id:
			return spawn.world_pos
	return null


func _sync_warden_alive() -> void:
	if _crystal == null or not _crystal.has_method("set_origin_warden_alive"):
		return
	var alive := false
	for enemy in _active:
		if not is_instance_valid(enemy):
			continue
		if enemy.get("enemy_id") != &"origin_warden":
			continue
		if float(enemy.get("health")) > 0.0:
			alive = true
			break
	_crystal.set_origin_warden_alive(alive)


func _try_spawn_guardians() -> void:
	if _world == null:
		_world = get_tree().get_first_node_in_group("world")
	if _world == null or _crystal == null or not _crystal.has_method("get_active_spawns"):
		return
	var spawns: Array = _crystal.get_active_spawns()
	if spawns.is_empty():
		return
	_claim_living_guardians(spawns)
	for spawn in spawns:
		var sid := int(spawn.id)
		if _guarded_spawn_ids.has(sid):
			continue
		if _active.size() >= max_active:
			return
		var kind: StringName = &"origin_warden" if bool(spawn.is_boss) else &"spawn_elite"
		if not spawn_enemy_at_column(kind, spawn.world_pos.x, spawn.world_pos.y, spawn.world_pos):
			continue
		var enemy: Node = _active[_active.size() - 1]
		enemy.set_meta("guard_spawn_id", sid)
		if enemy.has_method("bind_heart"):
			enemy.bind_heart(spawn.world_pos)
		_guarded_spawn_ids[sid] = true


func _claim_living_guardians(spawns: Array) -> void:
	var boss_id := -999999
	var open: Array[int] = []
	for spawn in spawns:
		var sid := int(spawn.id)
		if _guarded_spawn_ids.has(sid):
			continue
		if bool(spawn.is_boss):
			boss_id = sid
		else:
			open.append(sid)
	for enemy in _active:
		if not is_instance_valid(enemy) or float(enemy.get("health")) <= 0.0:
			continue
		var eid = enemy.get("enemy_id")
		if eid == &"origin_warden" and boss_id != -999999 and not _guarded_spawn_ids.has(boss_id):
			_guarded_spawn_ids[boss_id] = true
			enemy.set_meta("guard_spawn_id", boss_id)
		elif eid == &"spawn_elite":
			var tagged := -999999
			if enemy.has_meta("guard_spawn_id"):
				tagged = int(enemy.get_meta("guard_spawn_id"))
			if tagged != -999999:
				_guarded_spawn_ids[tagged] = true
				open.erase(tagged)
			elif not open.is_empty():
				var take: int = open[0]
				open.remove_at(0)
				_guarded_spawn_ids[take] = true
				enemy.set_meta("guard_spawn_id", take)


func _spawn_pressure_mult() -> float:
	if _crystal == null or not _crystal.has_method("get_spawn_progress"):
		return 1.0
	var prog: Dictionary = _crystal.get_spawn_progress()
	var total: int = int(prog.get("total", 0))
	var active: int = int(prog.get("active", 0))
	if total <= 0:
		return 1.0
	var destroyed_ratio: float = float(total - active) / float(total)
	return 1.0 + destroyed_ratio * 1.25


func _biome_mob_mult() -> float:
	if _world == null or _crystal == null or _crystal.sim_config == null:
		return 1.0
	if not _world.has_method("get_biome") or not _crystal.sim_config.has_method("biome_mob_mult"):
		return 1.0
	var col := _player_column_pos()
	var biome: Dictionary = _world.get_biome(col.x, 0.0, col.y)
	return maxf(_crystal.sim_config.biome_mob_mult(str(biome.get("name", ""))), 0.25)


func _player_column_pos() -> Vector2:
	if _player and _player.has_method("get_voxel_position"):
		var v: Vector3 = _player.get_voxel_position()
		return Vector2(v.x, v.z)
	var ws = _WorldSettings.get_active()
	return Vector2(
		ws.world_to_column(_player.global_position.x),
		ws.world_to_column(_player.global_position.z)
	)


func _nearest_crystal_column_distance(col: Vector2) -> float:
	if _crystal == null:
		return INF
	var pcx := int(floor(col.x))
	var pcz := int(floor(col.y))
	var best := INF
	var max_r := maxi(int(ceil(spawn_near_player_max)) + 4, 8)
	for r in range(0, max_r + 1):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				if _crystal.get_depth_at(pcx + dx, pcz + dz) < require_crystal_depth:
					continue
				var d := Vector2(float(dx), float(dz)).length()
				best = minf(best, d)
		if best < INF:
			return best
	return best