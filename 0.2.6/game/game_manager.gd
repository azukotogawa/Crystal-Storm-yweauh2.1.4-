class_name GameManager
extends Node

const _GameConfig = preload("res://config/game_config.gd")
const _StatIds = preload("res://stats/stat_ids.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

enum Phase { MAZE, ASSAULT, VICTORY }
enum RunState { PLAYING, WON, LOST }

signal phase_changed(new_phase: Phase)
signal run_state_changed(new_state: RunState)

@export var assault_distance: float = 140.0
@export var maze_min_distance: float = 200.0
@export var max_crystal_coverage: float = 0.72
@export var crystal_damage_per_second: float = 28.0

var phase: Phase = Phase.MAZE
var run_state: RunState = RunState.PLAYING

var _player: Node3D
var _crystal: CrystalManager
var _world: InfiniteNoiseWorld


func _ready() -> void:
	add_to_group("game_manager")
	call_deferred("_bind")


func apply_game_config(cfg: _GameConfig) -> void:
	if cfg == null:
		return
	assault_distance = cfg.assault_distance
	maze_min_distance = cfg.maze_min_distance
	crystal_damage_per_second = cfg.crystal_damage_per_second
	var town_defense = get_tree().get_first_node_in_group("town_defense_manager")
	if town_defense and "fall_depth" in town_defense:
		town_defense.fall_depth = cfg.town_fall_depth
	if cfg.crystal_sim:
		max_crystal_coverage = cfg.crystal_sim.max_coverage_ratio


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_crystal = get_tree().get_first_node_in_group("crystal_manager")
	_world = get_tree().get_first_node_in_group("world")

	if _crystal:
		_crystal.all_spawns_destroyed.connect(_on_all_spawns_destroyed)
		_crystal.crystal_touched_player.connect(_on_crystal_touched_player)

	if _player and _player.has_signal("died"):
		_player.died.connect(_on_player_died)


func _process(delta: float) -> void:
	if run_state != RunState.PLAYING:
		return
	_update_phase()
	_check_crystal_overrun()
	_check_towns_lost()
	if _player and _crystal:
		_apply_crystal_damage(delta)


func _update_phase() -> void:
	if _player == null or phase == Phase.VICTORY:
		return
	var col := _player_column_xz()
	var dist: float = col.length()
	# Maze phase at origin (building/digging); assault when crystal has tiered up and player is near.
	var next: Phase = Phase.MAZE
	if _crystal and _crystal.strength_tier >= 1 and dist <= assault_distance:
		next = Phase.ASSAULT
	if next != phase:
		phase = next
		phase_changed.emit(phase)


func _check_crystal_overrun() -> void:
	if _crystal == null or not _crystal.has_method("get_coverage_ratio"):
		return
	if _crystal.get_coverage_ratio() >= max_crystal_coverage:
		_set_lost("The crystal consumed the map.")


func _check_towns_lost() -> void:
	var town_defense = get_tree().get_first_node_in_group("town_defense_manager")
	if town_defense and town_defense.has_method("is_any_town_fallen"):
		if town_defense.is_any_town_fallen():
			_set_lost("A settlement fell to the crystal.")


func _apply_crystal_damage(delta: float) -> void:
	if phase != Phase.ASSAULT:
		return
	if not _player.has_method("take_damage"):
		return
	var col2 := _player_column_xz()
	var wx := floori(col2.x)
	var wz := floori(col2.y)
	var depth: float = _crystal.get_depth_at(wx, wz)
	if depth < 0.25:
		return
	var resist := 0.0
	if _player.has_method("get_stat"):
		resist = _player.get_stat(_StatIds.CRYSTAL_RESISTANCE)
	var dmg := crystal_damage_per_second * depth * delta * (1.0 - clampf(resist, 0.0, 0.95))
	_player.take_damage(dmg)


func _on_all_spawns_destroyed() -> void:
	print("[Game] Victory — all crystal spawn points destroyed.")
	if phase != Phase.VICTORY:
		phase = Phase.VICTORY
		phase_changed.emit(phase)
	_set_won()


func _on_crystal_touched_player() -> void:
	_set_lost("The crystal overwhelmed you.")


func _on_player_died() -> void:
	_set_lost("You died.")


func _set_won() -> void:
	if run_state == RunState.WON:
		return
	run_state = RunState.WON
	if _crystal:
		_crystal.expansion_enabled = false
	run_state_changed.emit(run_state)


func _player_column_xz() -> Vector2:
	if _player and _player.has_method("get_voxel_position"):
		var v: Vector3 = _player.get_voxel_position()
		return Vector2(v.x, v.z)
	var ws = _WorldSettings.get_active()
	return Vector2(
		ws.world_to_column(_player.global_position.x),
		ws.world_to_column(_player.global_position.z)
	)


func _set_lost(reason: String = "") -> void:
	if run_state == RunState.LOST:
		return
	run_state = RunState.LOST
	if _crystal:
		_crystal.expansion_enabled = false
	run_state_changed.emit(run_state)
	if reason != "":
		print("Run lost: ", reason)


func restart_run() -> void:
	get_tree().reload_current_scene()