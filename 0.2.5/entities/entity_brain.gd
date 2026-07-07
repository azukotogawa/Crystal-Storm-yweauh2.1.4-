class_name EntityBrain
extends RefCounted

const _EntityBrainConfig = preload("res://config/entity_brain_config.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _CrystalFluidSim = preload("res://crystal/crystal_fluid_sim.gd")

enum State { IDLE, WANDER, FLEE, CHASE, DEAD }

var config: _EntityBrainConfig
var state: State = State.IDLE
var home_pos: Vector2i = Vector2i.ZERO
var target_pos: Vector2i = Vector2i.ZERO
var state_timer: float = 0.0

var _query: _CrystalTerrainQuery


func _init(p_config: _EntityBrainConfig, p_query: _CrystalTerrainQuery) -> void:
	config = p_config
	_query = p_query


func reset_at(pos: Vector2i) -> void:
	home_pos = pos
	target_pos = pos
	state = State.IDLE
	state_timer = 0.0


func tick(delta: float, self_pos: Vector2i, player_pos: Vector2i, crystal_sim: _CrystalFluidSim) -> Vector2i:
	state_timer += delta
	match state:
		State.IDLE:
			if _should_flee_crystal(self_pos, crystal_sim):
				state = State.FLEE
			elif _player_near(self_pos, player_pos, config.flee_distance):
				state = State.FLEE
			elif state_timer > 1.5:
				state = State.WANDER
				_pick_wander_target()
				state_timer = 0.0
		State.WANDER:
			if _should_flee_crystal(self_pos, crystal_sim) or _player_near(self_pos, player_pos, config.flee_distance):
				state = State.FLEE
			elif self_pos == target_pos or state_timer > 4.0:
				state = State.IDLE
				state_timer = 0.0
		State.FLEE:
			target_pos = _away_from(self_pos, player_pos)
			if not _should_flee_crystal(self_pos, crystal_sim) and state_timer > 2.0:
				state = State.IDLE
				state_timer = 0.0
		State.CHASE:
			target_pos = player_pos
			if not _player_near(self_pos, player_pos, config.chase_distance):
				state = State.IDLE
				state_timer = 0.0
	return target_pos


func _should_flee_crystal(pos: Vector2i, crystal_sim: _CrystalFluidSim) -> bool:
	if not config.avoids_crystal or crystal_sim == null:
		return false
	return crystal_sim.get_depth_at(pos.x, pos.y) >= config.crystal_flee_depth


func _player_near(self_pos: Vector2i, player_pos: Vector2i, radius: float) -> bool:
	return Vector2(self_pos).distance_to(Vector2(player_pos)) <= radius


func _pick_wander_target() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(home_pos) + str(Time.get_ticks_msec()))
	var angle := rng.randf_range(0.0, TAU)
	var dist := rng.randf_range(2.0, config.wander_radius)
	target_pos = home_pos + Vector2i(
		int(round(cos(angle) * dist)),
		int(round(sin(angle) * dist))
	)


func _away_from(self_pos: Vector2i, threat_pos: Vector2i) -> Vector2i:
	var dir := Vector2(self_pos - threat_pos)
	if dir.length_squared() < 0.01:
		dir = Vector2(1, 0)
	return self_pos + Vector2i(int(sign(dir.x) * 3), int(sign(dir.y) * 3))