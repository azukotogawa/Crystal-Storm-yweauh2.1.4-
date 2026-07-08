class_name EntityBrainRegistry
extends RefCounted

const _EntityBrainConfig = preload("res://config/entity_brain_config.gd")

static var _defs: Dictionary = {}


static func reset() -> void:
	_defs.clear()


static func ensure_builtins() -> void:
	if not _defs.is_empty():
		return
	_register(_make(&"rabbit", "Rabbit", _EntityBrainConfig.BehaviorProfile.PASSIVE_HERBIVORE, 7.0, 14.0))
	_register(_make(&"deer", "Deer", _EntityBrainConfig.BehaviorProfile.PASSIVE_HERBIVORE, 9.0, 18.0))
	_register(_make(&"boar", "Boar", _EntityBrainConfig.BehaviorProfile.PASSIVE_HERBIVORE, 8.0, 10.0, 28.0, 4.0))
	_register(_make(&"bird", "Bird", _EntityBrainConfig.BehaviorProfile.PASSIVE_HERBIVORE, 11.0, 8.0))

	var militia := _make(&"town_militia", "Militia", _EntityBrainConfig.BehaviorProfile.TOWN_MILITIA, 9.0, 6.0)
	militia.max_health = 45.0
	militia.contact_damage = 8.0
	militia.defend_radius = 20.0
	militia.chase_distance = 14.0
	_register(militia)

	_register(_enemy_brain(&"crystal_mite", "Crystal Mite", _EntityBrainConfig.BehaviorProfile.CRYSTAL_STALKER, 10.0, 16.0, 18.0))
	_register(_enemy_brain(&"farm_bomber", "Farm Bomber", _EntityBrainConfig.BehaviorProfile.SUICIDE_BOMBER, 12.0, 6.0, 28.0, 32.0))
	_register(_enemy_brain(&"crystal_stag", "Crystal Stag", _EntityBrainConfig.BehaviorProfile.CRYSTAL_STALKER, 14.0, 22.0, 24.0))
	_register(_enemy_brain(&"thornling", "Thornling", _EntityBrainConfig.BehaviorProfile.SHARD_GUARD, 7.0, 8.0, 20.0, 14.0))
	_register(_enemy_brain(&"corrupted_beast", "Corrupted Beast", _EntityBrainConfig.BehaviorProfile.CRYSTAL_STALKER, 9.0, 12.0, 30.0, 26.0))
	var guard := _enemy_brain(&"shard_guard", "Shard Guard", _EntityBrainConfig.BehaviorProfile.SHARD_GUARD, 8.0, 6.0, 16.0, 18.0)
	guard.patrol_radius = 10.0
	guard.max_health = 55.0
	_register(guard)


static func register_all(defs: Array) -> void:
	for def in defs:
		if def is _EntityBrainConfig:
			_register(def)


static func get_def(id: StringName) -> _EntityBrainConfig:
	return _defs.get(id)


static func _register(def: _EntityBrainConfig) -> void:
	_defs[def.id] = def


static func _make(
	id: StringName,
	label: String,
	profile: int,
	speed: float,
	wander: float,
	health: float = 18.0,
	flee: float = 6.0
) -> _EntityBrainConfig:
	var d := _EntityBrainConfig.new()
	d.id = id
	d.display_name = label
	d.behavior_profile = profile
	d.move_speed = speed
	d.wander_radius = wander
	d.max_health = health
	d.flee_distance = flee
	d.avoids_crystal = true
	return d


static func _enemy_brain(
	id: StringName,
	label: String,
	profile: int,
	speed: float,
	chase: float,
	health: float,
	damage: float = 20.0
) -> _EntityBrainConfig:
	var d := _EntityBrainConfig.new()
	d.id = id
	d.display_name = label
	d.behavior_profile = profile
	d.disposition = _EntityBrainConfig.Disposition.AGGRESSIVE
	d.move_speed = speed
	d.chase_distance = chase
	d.max_health = health
	d.contact_damage = damage
	d.avoids_crystal = false
	d.feeds_crystal_on_death = false
	if profile == _EntityBrainConfig.BehaviorProfile.SUICIDE_BOMBER:
		d.detonate_on_contact = true
		d.detonate_radius = 2.8
	return d