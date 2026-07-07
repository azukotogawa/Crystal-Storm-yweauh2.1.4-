class_name EntityBrain
extends RefCounted

const _EntityBrainConfig = preload("res://config/entity_brain_config.gd")
const _CrystalFluidSim = preload("res://crystal/crystal_fluid_sim.gd")
const _EntityNavigation = preload("res://entities/entity_navigation.gd")

enum State {
	IDLE,
	WANDER,
	FLEE_CRYSTAL,
	FLEE_THREAT,
	CHASE,
	DEFEND,
	PATROL,
	SUICIDE_CHARGE,
	RETURN_HOME,
}

var config: _EntityBrainConfig
var state: State = State.IDLE
var home_pos: Vector2i = Vector2i.ZERO
var defend_center: Vector2i = Vector2i.ZERO
var patrol_anchor: Vector2i = Vector2i.ZERO
var target_cell: Vector2i = Vector2i.ZERO
var state_timer: float = 0.0
var attack_timer: float = 0.0


func _init(p_config: _EntityBrainConfig) -> void:
	config = p_config


func reset_at(pos: Vector2i, defend: Vector2i = Vector2i.ZERO, patrol: Vector2i = Vector2i.ZERO) -> void:
	home_pos = pos
	defend_center = defend if defend != Vector2i.ZERO else pos
	patrol_anchor = patrol if patrol != Vector2i.ZERO else pos
	target_cell = pos
	state = State.IDLE
	state_timer = 0.0
	attack_timer = 0.0


func tick(
	delta: float,
	self_pos: Vector2i,
	player_pos: Vector2i,
	crystal_sim: _CrystalFluidSim,
	crystal_depth_nearby: float = 0.0
) -> Vector2i:
	state_timer += delta
	attack_timer = maxf(attack_timer - delta, 0.0)

	match config.behavior_profile:
		_EntityBrainConfig.BehaviorProfile.SUICIDE_BOMBER:
			_tick_suicide(delta, self_pos, player_pos)
		_EntityBrainConfig.BehaviorProfile.SHARD_GUARD:
			_tick_shard_guard(delta, self_pos, player_pos, crystal_sim)
		_EntityBrainConfig.BehaviorProfile.CRYSTAL_STALKER:
			_tick_crystal_stalker(delta, self_pos, player_pos, crystal_depth_nearby)
		_EntityBrainConfig.BehaviorProfile.TOWN_MILITIA:
			_tick_town_militia(delta, self_pos, player_pos, crystal_sim)
		_:
			_tick_passive(delta, self_pos, player_pos, crystal_sim)

	return target_cell


func wants_attack(self_pos: Vector2i, player_pos: Vector2i) -> bool:
	if config.contact_damage <= 0.0 or attack_timer > 0.0:
		return false
	var dist := Vector2(self_pos).distance_to(Vector2(player_pos))
	if dist > 1.45:
		return false
	attack_timer = config.attack_cooldown
	return true


func should_detonate(self_pos: Vector3, target_pos: Vector3) -> bool:
	if not config.detonate_on_contact:
		return false
	return self_pos.distance_to(target_pos) <= config.detonate_radius


func _tick_passive(
	delta: float,
	self_pos: Vector2i,
	player_pos: Vector2i,
	crystal_sim: _CrystalFluidSim
) -> void:
	match state:
		State.IDLE:
			if _crystal_threat(self_pos, crystal_sim):
				state = State.FLEE_CRYSTAL
				target_cell = _EntityNavigation.flee_cell(self_pos, _nearest_crystal_cell(self_pos, crystal_sim), 4)
			elif _near(player_pos, self_pos, config.flee_distance):
				state = State.FLEE_THREAT
				target_cell = _EntityNavigation.flee_cell(self_pos, player_pos, 4)
			elif state_timer > 1.8:
				state = State.WANDER
				_pick_wander_target()
				state_timer = 0.0
		State.WANDER:
			if _crystal_threat(self_pos, crystal_sim) or _near(player_pos, self_pos, config.flee_distance):
				state = State.FLEE_THREAT if _near(player_pos, self_pos, config.flee_distance) else State.FLEE_CRYSTAL
				target_cell = _EntityNavigation.flee_cell(self_pos, player_pos if state == State.FLEE_THREAT else self_pos, 4)
			elif self_pos == target_cell or state_timer > 5.0:
				state = State.RETURN_HOME
				target_cell = home_pos
				state_timer = 0.0
		State.FLEE_CRYSTAL, State.FLEE_THREAT:
			var threat := player_pos if state == State.FLEE_THREAT else _nearest_crystal_cell(self_pos, crystal_sim)
			target_cell = _EntityNavigation.flee_cell(self_pos, threat, 4)
			if state_timer > 2.5 and not _crystal_threat(self_pos, crystal_sim) and not _near(player_pos, self_pos, config.flee_distance):
				state = State.IDLE
				state_timer = 0.0
		State.RETURN_HOME:
			target_cell = home_pos
			if self_pos == home_pos or state_timer > 4.0:
				state = State.IDLE
				state_timer = 0.0
		_:
			state = State.IDLE


func _tick_town_militia(
	delta: float,
	self_pos: Vector2i,
	player_pos: Vector2i,
	crystal_sim: _CrystalFluidSim
) -> void:
	var town_dist := Vector2(self_pos).distance_to(Vector2(defend_center))
	var crystal_near_town := _crystal_near(defend_center, crystal_sim, config.defend_radius)

	match state:
		State.IDLE, State.DEFEND:
			if crystal_near_town and _near(player_pos, defend_center, config.chase_distance * 1.5):
				state = State.CHASE
				target_cell = player_pos
			elif crystal_near_town:
				state = State.DEFEND
				target_cell = _patrol_point(defend_center, config.defend_radius * 0.6)
			elif town_dist > config.defend_radius:
				state = State.RETURN_HOME
				target_cell = defend_center
			elif state_timer > 2.0:
				state = State.PATROL
				target_cell = _patrol_point(defend_center, config.defend_radius * 0.55)
				state_timer = 0.0
		State.PATROL:
			if crystal_near_town:
				state = State.DEFEND
				target_cell = _patrol_point(defend_center, config.defend_radius * 0.6)
			elif self_pos == target_cell or state_timer > 4.0:
				state = State.IDLE
				state_timer = 0.0
		State.CHASE:
			target_cell = player_pos
			if not crystal_near_town or not _near(player_pos, self_pos, config.chase_distance):
				state = State.DEFEND
				state_timer = 0.0
		State.RETURN_HOME:
			target_cell = defend_center
			if town_dist <= 2.0:
				state = State.IDLE
				state_timer = 0.0
		_:
			state = State.IDLE


func _tick_suicide(_delta: float, self_pos: Vector2i, player_pos: Vector2i) -> void:
	state = State.SUICIDE_CHARGE
	target_cell = player_pos
	if not _near(player_pos, self_pos, config.chase_distance * 1.5):
		target_cell = self_pos


func _tick_shard_guard(
	delta: float,
	self_pos: Vector2i,
	player_pos: Vector2i,
	crystal_sim: _CrystalFluidSim
) -> void:
	match state:
		State.IDLE, State.PATROL:
			if _near(player_pos, patrol_anchor, config.chase_distance):
				state = State.CHASE
				target_cell = player_pos
			elif state_timer > 2.5:
				state = State.PATROL
				target_cell = _patrol_point(patrol_anchor, config.patrol_radius)
				state_timer = 0.0
		State.CHASE:
			target_cell = player_pos
			if not _near(player_pos, patrol_anchor, config.chase_distance * 1.2):
				state = State.PATROL
				target_cell = _patrol_point(patrol_anchor, config.patrol_radius)
				state_timer = 0.0
		State.FLEE_CRYSTAL:
			target_cell = _EntityNavigation.flee_cell(self_pos, _nearest_crystal_cell(self_pos, crystal_sim), 3)
		_:
			state = State.PATROL
			target_cell = _patrol_point(patrol_anchor, config.patrol_radius)


func _tick_crystal_stalker(
	delta: float,
	self_pos: Vector2i,
	player_pos: Vector2i,
	crystal_depth_nearby: float
) -> void:
	if crystal_depth_nearby >= config.crystal_hunt_min_depth and _near(player_pos, self_pos, config.chase_distance):
		state = State.CHASE
		target_cell = player_pos
	elif state == State.CHASE:
		if not _near(player_pos, self_pos, config.chase_distance * 1.1):
			state = State.PATROL
			target_cell = _patrol_point(home_pos, config.patrol_radius)
			state_timer = 0.0
	else:
		match state:
			State.IDLE:
				if state_timer > 1.5:
					state = State.PATROL
					target_cell = _patrol_point(home_pos, config.patrol_radius)
					state_timer = 0.0
			State.PATROL:
				if self_pos == target_cell or state_timer > 3.5:
					state = State.IDLE
					state_timer = 0.0
			_:
				state = State.IDLE


func _pick_wander_target() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(home_pos) + str(Time.get_ticks_msec()))
	var angle := rng.randf_range(0.0, TAU)
	var dist := rng.randf_range(2.0, config.wander_radius)
	target_cell = home_pos + Vector2i(
		int(round(cos(angle) * dist)),
		int(round(sin(angle) * dist))
	)


func _patrol_point(anchor: Vector2i, radius: float) -> Vector2i:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(anchor) + str(state_timer))
	var angle := rng.randf_range(0.0, TAU)
	var dist := rng.randf_range(2.0, radius)
	return anchor + Vector2i(int(round(cos(angle) * dist)), int(round(sin(angle) * dist)))


func _crystal_threat(pos: Vector2i, crystal_sim: _CrystalFluidSim) -> bool:
	if not config.avoids_crystal or crystal_sim == null:
		return false
	return crystal_sim.get_depth_at(pos.x, pos.y) >= config.crystal_flee_depth


func _crystal_near(center: Vector2i, crystal_sim: _CrystalFluidSim, radius: float) -> bool:
	if crystal_sim == null:
		return false
	var r := int(ceil(radius))
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			if Vector2(dx, dz).length() > radius:
				continue
			if crystal_sim.get_depth_at(center.x + dx, center.y + dz) >= config.crystal_flee_depth:
				return true
	return false


func _nearest_crystal_cell(pos: Vector2i, crystal_sim: _CrystalFluidSim) -> Vector2i:
	if crystal_sim == null:
		return pos
	var best := pos
	var best_depth := 0.0
	for dx in range(-4, 5):
		for dz in range(-4, 5):
			var cell := pos + Vector2i(dx, dz)
			var depth := crystal_sim.get_depth_at(cell.x, cell.y)
			if depth > best_depth:
				best_depth = depth
				best = cell
	return best if best_depth > 0.0 else pos


func _near(a: Vector2i, b: Vector2i, radius: float) -> bool:
	return Vector2(a).distance_to(Vector2(b)) <= radius