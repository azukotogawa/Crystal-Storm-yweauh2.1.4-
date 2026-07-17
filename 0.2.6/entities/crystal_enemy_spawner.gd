class_name CrystalEnemySpawner
extends Node

const _CrystalEnemy = preload("res://entities/crystal_enemy.gd")
const _EnemySpawnRegistry = preload("res://entities/enemy_spawn_registry.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _WorldVisualCoords = preload("res://helpers/world_visual_coords.gd")


@export var spawn_interval: float = 8.0
@export var max_active: int = 24
## Prefer near-frontier spawns so early-run crystal rings (~few columns) can host mites.
@export var spawn_near_player_min: float = 3.0
@export var spawn_near_player_max: float = 36.0
@export var require_crystal_depth: float = 0.2
@export var assault_spawn_mult: float = 1.6

var _timer: float = 0.0
var _active: Array[Node3D] = []
var _crystal: CrystalManager
var _player: Node3D
var _world: InfiniteNoiseWorld
var _game_manager: GameManager


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
	_prune_active()
	if _crystal == null or _player == null:
		return
	var evolution = _crystal.get_evolution() if _crystal.has_method("get_evolution") else null
	if evolution == null or evolution.unlocked_enemies.is_empty():
		return
	if _active.size() >= max_active:
		return

	var interval := spawn_interval
	if _game_manager and _game_manager.phase == GameManager.Phase.ASSAULT:
		interval /= assault_spawn_mult
	interval /= _spawn_pressure_mult()

	_timer += delta
	if _timer < interval:
		return
	_timer = 0.0

	var col := _player_column_pos()
	var depth := _crystal.get_depth_at(floori(col.x), floori(col.y))
	if depth < require_crystal_depth:
		# Column-space distance (depth map is keyed by column, not world units).
		var near_col := _nearest_crystal_column_distance(col)
		if near_col > spawn_near_player_max:
			return

	var tier: int = _crystal.strength_tier if "strength_tier" in _crystal else 0
	var enemy_id: StringName = _EnemySpawnRegistry.pick_weighted(evolution.unlocked_enemies, tier)
	if enemy_id == &"":
		enemy_id = evolution.unlocked_enemies[0]
	_spawn_enemy(enemy_id)


func _on_enemy_unlocked(enemy_id: StringName) -> void:
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


## Production spawn entry used by _process and unlock bursts.
## Returns true when an enemy was added to the tree.
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
	# Order matters for Spatial Query: position before setup (setup indexes spatial).
	parent.add_child(enemy)
	enemy.global_position = spawn_pos
	enemy.setup(enemy_id, _player, spawn_def, patrol)
	if enemy.has_method("sync_spatial_index"):
		enemy.sync_spatial_index()
	_active.append(enemy)


func _pick_spawn_pos() -> Vector3:
	if _crystal == null or _player == null or _world == null:
		return Vector3.ZERO
	var col := _player_column_pos()
	var px := col.x
	var pz := col.y
	# Random samples in the preferred ring (defaults allow early-run crystal rings).
	var pos := _sample_crystal_ring(px, pz, spawn_near_player_min, spawn_near_player_max, 24)
	if pos != Vector3.ZERO:
		return pos
	# Fallback: any crystal cell near the player (frontier often sits inside min ring).
	pos = _sample_crystal_ring(px, pz, 1.0, spawn_near_player_max, 48)
	if pos != Vector3.ZERO:
		return pos
	# Last resort: scan expanding Chebyshev rings for a crystal-depth column.
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
		out.append({
			"enemy_id": str(enemy.enemy_id),
			"x": enemy.global_position.x,
			"y": enemy.global_position.y,
			"z": enemy.global_position.z,
			"health": enemy.health,
		})
	return out


func import_enemies(rows: Array) -> void:
	if rows.is_empty():
		return
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
		# Position before setup so spatial index samples final placement.
		parent.add_child(enemy)
		enemy.global_position = Vector3(
			float(row.get("x", 0.0)),
			float(row.get("y", 1.0)),
			float(row.get("z", 0.0))
		)
		enemy.setup(enemy_id, _player, spawn_def)
		if row.has("health"):
			enemy.health = float(row.health)
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


func _player_column_pos() -> Vector2:
	if _player and _player.has_method("get_voxel_position"):
		var v: Vector3 = _player.get_voxel_position()
		return Vector2(v.x, v.z)
	var ws = _WorldSettings.get_active()
	return Vector2(
		ws.world_to_column(_player.global_position.x),
		ws.world_to_column(_player.global_position.z)
	)


## Chebyshev/Euclidean column distance to nearest crystal-depth cell near the player.
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