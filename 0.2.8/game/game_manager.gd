class_name GameManager
extends Node

const _GameConfig = preload("res://config/game_config.gd")
const _StatIds = preload("res://stats/stat_ids.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

enum Phase { MAZE, ASSAULT, VICTORY }
enum RunState { PLAYING, WON, LOST }

signal phase_changed(new_phase: Phase)
signal run_state_changed(new_state: RunState)

## Enter ASSAULT when within this distance of crystal fluid (or origin boss if no fluid yet).
@export var assault_distance: float = 48.0
## Leave ASSAULT / stay in MAZE when farther than this (hysteresis so phase does not flicker).
@export var maze_min_distance: float = 72.0
@export var max_crystal_coverage: float = 0.72
@export var crystal_damage_per_second: float = 28.0
## Fallen towns are a penalty, not a loss. This much crystal power is added once.
@export var town_fall_power_surge: float = 40.0

var phase: Phase = Phase.MAZE
var run_state: RunState = RunState.PLAYING
## Last terminal loss reason for UI / verifies (empty while playing or after win).
var last_loss_reason: String = ""
## "boss" when the origin warden dies. "spawns" when every heart is destroyed.
var victory_reason: String = ""
## Run summary counters. Updated on signals, not by scanning the tree.
var run_started_msec: int = 0
var spawns_destroyed: int = 0
var crystal_cells_broken: int = 0
var enemies_killed: int = 0
var relics_taken: int = 0
var deaths: int = 0
var _stats_bound: bool = false
## How many settlements have fallen this run (penalty already applied).
var fallen_towns: int = 0
## Last town-fall penalty line for the HUD and probes.
var last_town_penalty: String = ""
var _town_penalty_bound: bool = false

var _player: Node3D
## Duck-typed crystal façade (CrystalManager in production; stubs in verifies).
var _crystal
var _world: InfiniteNoiseWorld


func _ready() -> void:
	add_to_group("game_manager")
	if run_started_msec <= 0:
		run_started_msec = Time.get_ticks_msec()
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
	if "town_fall_power_surge" in cfg:
		town_fall_power_surge = float(cfg.town_fall_power_surge)


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_crystal = get_tree().get_first_node_in_group("crystal_manager")
	_world = get_tree().get_first_node_in_group("world")

	if _crystal:
		_crystal.all_spawns_destroyed.connect(_on_all_spawns_destroyed)
		_crystal.crystal_touched_player.connect(_on_crystal_touched_player)

	if _player and _player.has_signal("died"):
		_player.died.connect(_on_player_died)
	_bind_run_stats()


func _process(delta: float) -> void:
	if run_state != RunState.PLAYING:
		return
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("game_manager")
	if not _town_penalty_bound:
		_bind_town_penalty()
	_update_phase()
	_check_crystal_overrun()
	if _player and _crystal:
		_apply_crystal_damage(delta)
	if profiler and profiler.has_method("end"):
		profiler.end("game_manager")


func _update_phase() -> void:
	if _player == null or phase == Phase.VICTORY:
		return
	# MAZE = prepare with terrain; ASSAULT = close enough to fight the crystal mass.
	# Tier 0 always MAZE so early dig/build has breathing room before pressure fights back.
	var next: Phase = Phase.MAZE
	if _crystal != null and int(_crystal.strength_tier) >= 1:
		var dist: float = _distance_to_crystal_pressure()
		if phase == Phase.ASSAULT:
			# Hysteresis: stay in fight until you pull back past maze_min_distance.
			if dist <= maze_min_distance:
				next = Phase.ASSAULT
		elif dist <= assault_distance:
			next = Phase.ASSAULT
	if next != phase:
		phase = next
		phase_changed.emit(phase)


## Distance to nearest crystal fluid; falls back to origin boss / map origin doorstep.
func _distance_to_crystal_pressure() -> float:
	if _player == null:
		return INF
	var col := _player_column_xz()
	var from := Vector3(col.x, 0.0, col.y)
	if _crystal != null and _crystal.has_method("get_nearest_crystal_distance"):
		var d: float = float(_crystal.get_nearest_crystal_distance(from))
		if d < INF * 0.5:
			return d
	# No fluid yet: distance to the origin boss (a map corner, relocated onto land).
	if _crystal != null and _crystal.has_method("get_active_spawns"):
		for spawn in _crystal.get_active_spawns():
			if spawn != null and bool(spawn.get("is_boss")):
				var bp: Vector2i = spawn.world_pos
				return col.distance_to(Vector2(float(bp.x) + 0.5, float(bp.y) + 0.5))
	return col.length()


func _check_crystal_overrun() -> void:
	if _crystal == null or not _crystal.has_method("get_coverage_ratio"):
		return
	if _crystal.get_coverage_ratio() >= max_crystal_coverage:
		_set_lost("The crystal consumed the map.")


func _bind_town_penalty() -> void:
	var town_defense = get_tree().get_first_node_in_group("town_defense_manager")
	if town_defense == null or not town_defense.has_signal("town_fallen"):
		return
	if not town_defense.town_fallen.is_connected(_on_town_fallen):
		town_defense.town_fallen.connect(_on_town_fallen)
	_town_penalty_bound = true


## A fallen town is expected. The crystal surges and that town's defenders are gone.
## The run continues until coverage or death.
func _on_town_fallen(town_name: String, center: Vector2i) -> void:
	if run_state != RunState.PLAYING:
		return
	fallen_towns += 1
	var surge := maxf(town_fall_power_surge, 0.0)
	if _crystal and _crystal.has_method("grant_feed_power"):
		_crystal.grant_feed_power(surge)
	var lost := 0
	var entity_mgr = get_tree().get_first_node_in_group("entity_manager")
	if entity_mgr and entity_mgr.has_method("dismiss_town_defenders"):
		lost = int(entity_mgr.dismiss_town_defenders(center))
	last_town_penalty = "%s fell — crystal +%.0f power, %d defenders lost" % [town_name, surge, lost]
	print("[Game] Town penalty: ", last_town_penalty)
	var overlay = get_tree().get_first_node_in_group("game_overlay")
	if overlay and overlay.has_method("_show_toast"):
		overlay.call("_show_toast", last_town_penalty)


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
	# Field damage is a burn, not a hit. It must not grant or respect i-frames.
	if "damage_source_hint" in _player:
		_player.damage_source_hint = &"crystal_field"
	_player.take_damage(dmg)


func _on_all_spawns_destroyed() -> void:
	print("[Game] Victory — all crystal spawn points destroyed.")
	if victory_reason == "":
		victory_reason = "spawns"
	if phase != Phase.VICTORY:
		phase = Phase.VICTORY
		phase_changed.emit(phase)
	_set_won()


## The origin warden's death ends the run. Loss conditions are unchanged.
## The origin heart stays sealed while that warden lives (see SpawnPointController).
func notify_boss_defeated() -> void:
	if run_state != RunState.PLAYING:
		return
	victory_reason = "boss"
	print("[Game] Victory — the origin warden fell.")
	if phase != Phase.VICTORY:
		phase = Phase.VICTORY
		phase_changed.emit(phase)
	_set_won()


func _on_crystal_touched_player() -> void:
	_set_lost("The crystal overwhelmed you.")


func _on_player_died() -> void:
	note_death()
	_set_lost("You died.")


func note_spawn_destroyed() -> void:
	spawns_destroyed += 1


func note_crystal_broken(count: int = 1) -> void:
	crystal_cells_broken += maxi(count, 0)


func note_enemy_killed() -> void:
	enemies_killed += 1


func note_relic_taken() -> void:
	relics_taken += 1


func note_death() -> void:
	deaths += 1


func run_summary() -> Dictionary:
	var elapsed := 0.0
	if run_started_msec > 0:
		elapsed = maxf(0.0, float(Time.get_ticks_msec() - run_started_msec) / 1000.0)
	var outcome := "playing"
	if run_state == RunState.WON:
		outcome = "win"
	elif run_state == RunState.LOST:
		outcome = "loss"
	return {
		"outcome": outcome,
		"time_sec": elapsed,
		"spawns_destroyed": spawns_destroyed,
		"boss_defeated": victory_reason == "boss",
		"crystal_broken": crystal_cells_broken,
		"enemies_killed": enemies_killed,
		"relics_taken": relics_taken,
		"deaths": deaths,
		"victory_reason": victory_reason,
		"loss_reason": last_loss_reason,
	}


func _bind_run_stats() -> void:
	if _stats_bound:
		return
	_stats_bound = true
	if _crystal and _crystal.has_signal("spawn_destroyed") and not _crystal.spawn_destroyed.is_connected(_on_spawn_destroyed_stat):
		_crystal.spawn_destroyed.connect(_on_spawn_destroyed_stat)
	if _crystal and _crystal.has_signal("crystal_mass_hit") and not _crystal.crystal_mass_hit.is_connected(_on_crystal_mass_stat):
		_crystal.crystal_mass_hit.connect(_on_crystal_mass_stat)
	var relics = get_tree().get_first_node_in_group("relic_manager") if get_tree() else null
	if relics and relics.has_signal("relic_equipped") and not relics.relic_equipped.is_connected(_on_relic_equipped_stat):
		relics.relic_equipped.connect(_on_relic_equipped_stat)
		if relics_taken == 0 and "equipped" in relics and relics.equipped is Array:
			relics_taken = (relics.equipped as Array).size()


func _on_spawn_destroyed_stat(_spawn) -> void:
	note_spawn_destroyed()


func _on_crystal_mass_stat(_pos: Vector3, _amount: float, broken: bool) -> void:
	if broken:
		note_crystal_broken(1)


func _on_relic_equipped_stat(_relic_id: StringName) -> void:
	note_relic_taken()


func _set_won() -> void:
	if run_state == RunState.WON or run_state == RunState.LOST:
		return
	run_state = RunState.WON
	last_loss_reason = ""
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
	if run_state == RunState.LOST or run_state == RunState.WON:
		return
	run_state = RunState.LOST
	last_loss_reason = reason
	if _crystal:
		_crystal.expansion_enabled = false
	run_state_changed.emit(run_state)
	if reason != "":
		print("Run lost: ", reason)


func is_run_playing() -> bool:
	return run_state == RunState.PLAYING


func restart_run() -> void:
	get_tree().reload_current_scene()
