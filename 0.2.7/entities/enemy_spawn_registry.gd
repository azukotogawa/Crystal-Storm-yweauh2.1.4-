class_name EnemySpawnRegistry
extends RefCounted

const _EnemySpawnDef = preload("res://config/enemy_spawn_def.gd")

static var _defs: Dictionary = {}


static func reset() -> void:
	_defs.clear()


static func ensure_builtins() -> void:
	if not _defs.is_empty():
		return
	_register(_make(&"crystal_mite", &"crystal_mite", 10.0, 22.0, Color(0.72, 0.2, 0.95)))
	_register(_make(&"farm_bomber", &"farm_bomber", 12.0, 32.0, Color(0.95, 0.55, 0.2), 1.2))
	_register(_make(&"crystal_stag", &"crystal_stag", 14.0, 24.0, Color(0.55, 0.25, 0.9), 1.1))
	_register(_make(&"thornling", &"thornling", 7.0, 14.0, Color(0.3, 0.75, 0.35), 0.9))
	_register(_make(&"corrupted_beast", &"corrupted_beast", 9.0, 26.0, Color(0.45, 0.18, 0.55), 1.0))
	_register(_make(&"shard_guard", &"shard_guard", 8.0, 18.0, Color(0.82, 0.35, 1.0), 0.8, 1))


static func register_all(defs: Array) -> void:
	for def in defs:
		if def is _EnemySpawnDef:
			_register(def)


static func get_def(id: StringName) -> _EnemySpawnDef:
	return _defs.get(id)


static func pick_weighted(ids: Array[StringName], tier: int) -> StringName:
	var pool: Array[StringName] = []
	var weights: Array[float] = []
	for enemy_id in ids:
		var def: _EnemySpawnDef = get_def(enemy_id)
		if def == null:
			continue
		if tier < def.min_crystal_tier:
			continue
		pool.append(enemy_id)
		weights.append(def.spawn_weight)
	if pool.is_empty():
		return &""
	var total := 0.0
	for w in weights:
		total += w
	var roll := randf() * total
	for i in pool.size():
		roll -= weights[i]
		if roll <= 0.0:
			return pool[i]
	return pool.back()


static func _register(def: _EnemySpawnDef) -> void:
	_defs[def.id] = def


static func _make(
	id: StringName,
	brain_id: StringName,
	speed: float,
	damage: float,
	tint: Color,
	weight: float = 1.0,
	min_tier: int = 0
) -> _EnemySpawnDef:
	var d := _EnemySpawnDef.new()
	d.id = id
	d.display_name = str(id)
	d.brain_config_id = brain_id
	d.move_speed = speed
	d.contact_damage = damage
	d.tint = tint
	d.spawn_weight = weight
	d.min_crystal_tier = min_tier
	return d