class_name GameManager
extends Node

const _GameConfig = preload("res://config/game_config.gd")
const _StatIds = preload("res://stats/stat_ids.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _Progression = preload("res://systems/progression_service.gd")
const _BurnLook = preload("res://config/burn_pool_look.gd")
const _BurnWarn = preload("res://helpers/burn_pool_warn.gd")

const DEATH_ONLY_LOSS := true

enum Phase { MAZE, ASSAULT, VICTORY }
enum RunState { PLAYING, WON, LOST }

signal phase_changed(new_phase: Phase)
signal run_state_changed(new_state: RunState)

@export var assault_distance: float = 48.0
@export var maze_min_distance: float = 72.0
@export var max_crystal_coverage: float = 0.72
@export var crystal_damage_per_second: float = 28.0
@export var town_fall_power_surge: float = 40.0

var phase: Phase = Phase.MAZE
var run_state: RunState = RunState.PLAYING
var last_loss_reason: String = ""
var victory_reason: String = ""
var run_started_msec: int = 0
var spawns_destroyed: int = 0
var crystal_cells_broken: int = 0
var enemies_killed: int = 0
var blocks_mined: int = 0
var blocks_placed: int = 0
var structures_placed: int = 0
var ruins_discovered: int = 0
var pois_discovered: int = 0
var relics_taken: int = 0
var deaths: int = 0
var boss_defeated: bool = false
var _stats_bound: bool = false
var _structure_xp_bound: bool = false
var _discovery_xp_bound: bool = false
var fallen_towns: int = 0
var last_town_penalty: String = ""
var coverage_warning: String = ""
var crystal_touch_note: String = ""
var _coverage_warned: bool = false
var _crystal_touch_noted: bool = false
var _town_penalty_bound: bool = false

var _player: Node3D
var _crystal
var _world: InfiniteNoiseWorld
var _burn_left: float = -1.0
var _burn_glow: Node3D
var _burn_look: BurnPoolLook


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
	if not _structure_xp_bound or not _discovery_xp_bound:
		_bind_xp_sources()
	_update_phase()
	_check_crystal_overrun()
	if _player and _crystal:
		_apply_crystal_damage(delta)
	if profiler and profiler.has_method("end"):
		profiler.end("game_manager")


func _update_phase() -> void:
	if _player == null or phase == Phase.VICTORY:
		return
	var next: Phase = Phase.MAZE
	if _crystal != null and int(_crystal.strength_tier) >= 1:
		var dist: float = _distance_to_crystal_pressure()
		if phase == Phase.ASSAULT:
			if dist <= maze_min_distance:
				next = Phase.ASSAULT
		elif dist <= assault_distance:
			next = Phase.ASSAULT
	if next != phase:
		phase = next
		phase_changed.emit(phase)


func _distance_to_crystal_pressure() -> float:
	if _player == null:
		return INF
	var col := _player_column_xz()
	var from := Vector3(col.x, 0.0, col.y)
	if _crystal != null and _crystal.has_method("get_nearest_crystal_distance"):
		var d: float = float(_crystal.get_nearest_crystal_distance(from))
		if d < INF * 0.5:
			return d
	if _crystal != null and _crystal.has_method("get_active_spawns"):
		for spawn in _crystal.get_active_spawns():
			if spawn != null and bool(spawn.get("is_boss")):
				var bp: Vector2i = spawn.world_pos
				return col.distance_to(Vector2(float(bp.x) + 0.5, float(bp.y) + 0.5))
	return col.length()


func _check_crystal_overrun() -> void:
	if _crystal == null or not _crystal.has_method("get_coverage_ratio"):
		return
	var ratio: float = float(_crystal.get_coverage_ratio())
	if ratio < max_crystal_coverage:
		return
	if DEATH_ONLY_LOSS:
		_note_coverage_pressure()
		return
	_set_lost("The crystal consumed the map.")


func coverage_hud_note(ratio: float) -> String:
	if not DEATH_ONLY_LOSS or ratio < max_crystal_coverage:
		return ""
	return "over cap"


func _note_coverage_pressure() -> void:
	if _coverage_warned:
		return
	_coverage_warned = true
	coverage_warning = "Crystal coverage is past the cap."
	if not is_inside_tree():
		return
	var overlay = get_tree().get_first_node_in_group("game_overlay")
	if overlay and overlay.has_method("_show_toast"):
		overlay.call("_show_toast", coverage_warning)


func _bind_town_penalty() -> void:
	var town_defense = get_tree().get_first_node_in_group("town_defense_manager")
	if town_defense == null or not town_defense.has_signal("town_fallen"):
		return
	if not town_defense.town_fallen.is_connected(_on_town_fallen):
		town_defense.town_fallen.connect(_on_town_fallen)
	_town_penalty_bound = true


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
	if not is_inside_tree():
		if not DEATH_ONLY_LOSS:
			_set_lost("%s fell." % town_name)
		return
	var overlay = get_tree().get_first_node_in_group("game_overlay")
	if overlay and overlay.has_method("_show_toast"):
		overlay.call("_show_toast", last_town_penalty)
	if not DEATH_ONLY_LOSS:
		_set_lost("%s fell." % town_name)


func _apply_crystal_damage(delta: float) -> void:
	if phase != Phase.ASSAULT:
		_end_burn_warn()
		return
	if not _player.has_method("take_damage"):
		_end_burn_warn()
		return
	var col2 := _player_column_xz()
	var wx := floori(col2.x)
	var wz := floori(col2.y)
	var depth: float = _crystal.get_depth_at(wx, wz)
	if depth < 0.25:
		_end_burn_warn()
		return
	var wind := _burn_telegraph_sec()
	if _burn_left < 0.0:
		_burn_left = wind
		_show_burn_warn()
		if _burn_left > 0.0:
			return
	_burn_left = maxf(_burn_left - delta, 0.0)
	_paint_burn_warn(wind)
	if _burn_left > 0.0:
		return
	var resist := 0.0
	if _player.has_method("get_stat"):
		resist = _player.get_stat(_StatIds.CRYSTAL_RESISTANCE)
	var dmg := crystal_damage_per_second * depth * delta * (1.0 - clampf(resist, 0.0, 0.95))
	# Field damage is a burn, not a hit. It must not grant or respect i-frames.
	if "damage_source_hint" in _player:
		_player.damage_source_hint = &"crystal_field"
	_player.take_damage(dmg)


func _burn_telegraph_sec() -> float:
	var feel := get_node_or_null("/root/GameFeel")
	if feel == null or not feel.has_method("enemy_telegraph"):
		return 0.0
	return maxf(float(feel.enemy_telegraph("burn_pool")), 0.0)


func _show_burn_warn() -> void:
	if _burn_glow != null and is_instance_valid(_burn_glow):
		_paint_burn_warn(_burn_telegraph_sec())
		return
	_burn_glow = _BurnWarn.attach(self)
	_paint_burn_warn(_burn_telegraph_sec())


func _paint_burn_warn(wind: float) -> void:
	if _burn_glow == null or not is_instance_valid(_burn_glow):
		return
	if _player == null:
		return
	var look := _active_burn_look()
	var vs: float = _WorldSettings.get_active().voxel_scale
	var feet := _player.global_position
	var urgent := 1.0
	if wind > 0.0 and _burn_left > 0.0:
		urgent = clampf(1.0 - _burn_left / wind, 0.0, 1.0)
	var cells := _burn_cells_under(feet, vs, look.cover_radius_columns)
	_BurnWarn.paint(_burn_glow, look, feet, cells, vs, urgent)


func _active_burn_look() -> BurnPoolLook:
	if _burn_look == null:
		_burn_look = _BurnLook.load_active()
	return _burn_look


func _burn_cells_under(feet: Vector3, vs: float, reach_columns: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var col2 := _player_column_xz()
	var stand := Vector2i(floori(col2.x), floori(col2.y))
	var reach := maxf(reach_columns, 0.0) * vs
	var span := maxi(ceili(reach_columns), 1)
	for dz in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var cell := Vector2i(stand.x + dx, stand.y + dz)
			if cell != stand and not _disc_hits_cell(feet, vs, reach, cell):
				continue
			if cell != stand and not _cell_is_pool(cell):
				continue
			out.append(cell)
	return out


func _cell_is_pool(cell: Vector2i) -> bool:
	if _crystal == null or not _crystal.has_method("get_depth_at"):
		return false
	return float(_crystal.get_depth_at(cell.x, cell.y)) >= 0.25


func _disc_hits_cell(feet: Vector3, vs: float, reach: float, cell: Vector2i) -> bool:
	var min_x := float(cell.x) * vs
	var max_x := min_x + vs
	var min_z := float(cell.y) * vs
	var max_z := min_z + vs
	var x := clampf(feet.x, min_x, max_x)
	var z := clampf(feet.z, min_z, max_z)
	return Vector2(x - feet.x, z - feet.z).length() <= reach + 0.001


func _end_burn_warn() -> void:
	_burn_left = -1.0
	if _burn_glow != null and is_instance_valid(_burn_glow):
		_burn_glow.visible = false


func _on_all_spawns_destroyed() -> void:
	if _GameConfig.SINGLE_CRYSTAL:
		print("[Game] Victory — the crystal was destroyed.")
		victory_reason = "crystal"
		_enter_victory()
		_set_won()
		return
	print("[Game] Victory — all crystal spawn points destroyed.")
	if victory_reason == "":
		victory_reason = "spawns"
	_enter_victory()
	_set_won()


func _enter_victory() -> void:
	if phase != Phase.VICTORY:
		phase = Phase.VICTORY
		phase_changed.emit(phase)


func notify_boss_defeated() -> void:
	if run_state != RunState.PLAYING:
		return
	boss_defeated = true
	if _GameConfig.SINGLE_CRYSTAL:
		print("[Game] The boss fell.")
		return
	victory_reason = "boss"
	print("[Game] Victory — the origin warden fell.")
	if phase != Phase.VICTORY:
		phase = Phase.VICTORY
		phase_changed.emit(phase)
	_set_won()


func _on_crystal_touched_player() -> void:
	if run_state != RunState.PLAYING:
		return
	if DEATH_ONLY_LOSS:
		_note_crystal_touch()
		return
	_set_lost("The crystal overwhelmed you.")


func _note_crystal_touch() -> void:
	if _crystal_touch_noted:
		return
	_crystal_touch_noted = true
	crystal_touch_note = "The crystal is on you. Step out."
	if not is_inside_tree():
		return
	var overlay = get_tree().get_first_node_in_group("game_overlay")
	if overlay and overlay.has_method("_show_toast"):
		overlay.call("_show_toast", crystal_touch_note)


func _on_player_died() -> void:
	note_death()
	_set_lost("You died.")


func note_spawn_destroyed() -> void:
	spawns_destroyed += 1


func note_crystal_broken(count: int = 1) -> void:
	crystal_cells_broken += maxi(count, 0)


func note_enemy_killed(tier: int = 0) -> void:
	enemies_killed += 1
	_grant_xp(_Progression.xp_for_kill(tier))


func note_crystal_damaged(amount: float, broken: bool = false) -> void:
	if broken:
		note_crystal_broken(1)
	_grant_xp(_Progression.xp_for_crystal_hit(amount, broken))


func note_blocks_mined(count: int = 1) -> void:
	var n := maxi(count, 0)
	if n == 0:
		return
	blocks_mined += n
	_grant_xp(_Progression.XP_BLOCK_MINED * n)


func note_blocks_placed(count: int = 1) -> void:
	blocks_placed += maxi(count, 0)


func note_structure_placed() -> void:
	structures_placed += 1
	_grant_xp(_Progression.XP_STRUCTURE_PLACED)


func note_ruin_discovered() -> void:
	ruins_discovered += 1
	_grant_xp(_Progression.XP_RUIN_DISCOVERED)


func note_poi_discovered() -> void:
	pois_discovered += 1
	_grant_xp(_Progression.XP_POI_DISCOVERED)


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
	var level := 1
	var xp_now := 0
	var svc = _Progression.get_active()
	if svc == null and is_inside_tree():
		svc = get_tree().get_first_node_in_group("progression_service")
	if svc:
		level = maxi(int(svc.level), 1)
		xp_now = maxi(int(svc.xp), 0)
	return {
		"outcome": outcome,
		"time_sec": elapsed,
		"spawns_destroyed": spawns_destroyed,
		"boss_defeated": boss_defeated or victory_reason == "boss",
		"crystal_broken": crystal_cells_broken,
		"enemies_killed": enemies_killed,
		"relics_taken": relics_taken,
		"deaths": deaths,
		"victory_reason": victory_reason,
		"loss_reason": last_loss_reason,
		"level": level,
		"xp": xp_now,
		"xp_to_next": _Progression.xp_to_advance(level),
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


func _on_crystal_mass_stat(_pos: Vector3, amount: float, broken: bool) -> void:
	note_crystal_damaged(amount, broken)


func _bind_xp_sources() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if not _structure_xp_bound:
		var player = tree.get_first_node_in_group("player")
		var weapon = player.get_node_or_null("WeaponController") if player else null
		if weapon and weapon.has_signal("structure_built"):
			if not weapon.structure_built.is_connected(_on_structure_placed_stat):
				weapon.structure_built.connect(_on_structure_placed_stat)
			_structure_xp_bound = true
	if not _discovery_xp_bound:
		var living = tree.get_first_node_in_group("living_world_director")
		if living == null:
			return
		if living.has_signal("ruin_discovered") and not living.ruin_discovered.is_connected(_on_ruin_discovered_stat):
			living.ruin_discovered.connect(_on_ruin_discovered_stat)
		if living.has_signal("poi_discovered") and not living.poi_discovered.is_connected(_on_poi_discovered_stat):
			living.poi_discovered.connect(_on_poi_discovered_stat)
		_discovery_xp_bound = true


func _on_structure_placed_stat(build_id: StringName, _world_pos: Vector3) -> void:
	if build_id == &"repair":
		return
	note_structure_placed()


func _on_ruin_discovered_stat(_ruin_name: String, _center: Vector2i, _power_bonus: float) -> void:
	note_ruin_discovered()


func _on_poi_discovered_stat(_poi_name: String) -> void:
	note_poi_discovered()


func _grant_xp(amount: int) -> void:
	if amount <= 0:
		return
	var svc = _Progression.get_active()
	if svc == null and is_inside_tree():
		svc = get_tree().get_first_node_in_group("progression_service")
	if svc and svc.has_method("add_xp"):
		svc.add_xp(amount)


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
