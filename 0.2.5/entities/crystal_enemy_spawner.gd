class_name CrystalEnemySpawner
extends Node

const _CrystalEnemy = preload("res://entities/crystal_enemy.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

@export var spawn_interval: float = 8.0
@export var max_active: int = 24
@export var spawn_near_player_min: float = 18.0
@export var spawn_near_player_max: float = 42.0
@export var require_crystal_depth: float = 0.2

var _timer: float = 0.0
var _active: Array[Node3D] = []
var _crystal: CrystalManager
var _player: Node3D
var _world: InfiniteNoiseWorld


func _ready() -> void:
	add_to_group("crystal_enemy_spawner")
	call_deferred("_bind")


func _bind() -> void:
	_crystal = get_tree().get_first_node_in_group("crystal_manager")
	_player = get_tree().get_first_node_in_group("player")
	_world = get_tree().get_first_node_in_group("world")


func _process(delta: float) -> void:
	_prune_active()
	if _crystal == null or _player == null:
		return
	if not _crystal.has_method("get_evolution"):
		return
	var evolution = _crystal.get_evolution()
	if evolution == null or evolution.unlocked_enemies.is_empty():
		return
	if _active.size() >= max_active:
		return

	_timer += delta
	if _timer < spawn_interval:
		return
	_timer = 0.0

	var col := _player_column_pos()
	var depth := _crystal.get_depth_at(floori(col.x), floori(col.y))
	if depth < require_crystal_depth:
		var near := _crystal.get_nearest_crystal_distance(_player.global_position)
		if near > spawn_near_player_max:
			return

	var enemy_id: StringName = evolution.unlocked_enemies[_rng_index(evolution.unlocked_enemies.size())]
	_spawn_enemy(enemy_id)


func _spawn_enemy(enemy_id: StringName) -> void:
	var spawn_pos := _pick_spawn_pos()
	if spawn_pos == Vector3.ZERO:
		return
	var enemy: _CrystalEnemy = _CrystalEnemy.new()
	enemy.setup(enemy_id, _player, _tint_for(enemy_id))
	enemy.move_speed = _speed_for(enemy_id)
	enemy.contact_damage = _damage_for(enemy_id)
	enemy.global_position = spawn_pos
	get_tree().current_scene.add_child(enemy)
	_active.append(enemy)


func _pick_spawn_pos() -> Vector3:
	if _crystal == null or _player == null or _world == null:
		return Vector3.ZERO
	var col := _player_column_pos()
	var px := col.x
	var pz := col.y
	for _attempt in 16:
		var angle := randf() * TAU
		var dist := randf_range(spawn_near_player_min, spawn_near_player_max)
		var wx := int(floor(px + cos(angle) * dist))
		var wz := int(floor(pz + sin(angle) * dist))
		if _crystal.get_depth_at(wx, wz) < require_crystal_depth:
			continue
		var y := TerrainRamps.walkable_height(_world, float(wx) + 0.5, float(wz) + 0.5)
		return Vector3(float(wx) + 0.5, y, float(wz) + 0.5)
	return Vector3.ZERO


func get_active_count() -> int:
	_prune_active()
	return _active.size()


func _prune_active() -> void:
	var kept: Array[Node3D] = []
	for e in _active:
		if is_instance_valid(e):
			kept.append(e)
	_active = kept


func _player_column_pos() -> Vector2:
	if _player and _player.has_method("get_voxel_position"):
		var v: Vector3 = _player.get_voxel_position()
		return Vector2(v.x, v.z)
	var ws = _WorldSettings.get_active()
	return Vector2(
		ws.world_to_column(_player.global_position.x),
		ws.world_to_column(_player.global_position.z)
	)


func _rng_index(size: int) -> int:
	return randi() % maxi(size, 1)


func _speed_for(id: StringName) -> float:
	match id:
		&"farm_bomber":
			return 12.0
		&"crystal_stag":
			return 14.0
		&"corrupted_beast":
			return 9.0
		_:
			return 10.0


func _damage_for(id: StringName) -> float:
	match id:
		&"farm_bomber":
			return 32.0
		&"shard_guard":
			return 18.0
		_:
			return 22.0


func _tint_for(id: StringName) -> Color:
	match id:
		&"farm_bomber":
			return Color(0.95, 0.55, 0.2)
		&"crystal_stag":
			return Color(0.55, 0.25, 0.9)
		&"thornling":
			return Color(0.3, 0.75, 0.35)
		_:
			return Color(0.72, 0.2, 0.95)