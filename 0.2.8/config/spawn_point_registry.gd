class_name SpawnPointRegistry
extends RefCounted

const _SpawnPointDef = preload("res://config/spawn_point_def.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")

static var _defs: Dictionary = {}


static func reset() -> void:
	_defs.clear()


static func ensure_builtins() -> void:
	if not _defs.is_empty():
		return
	_register(_make(
		&"origin_boss",
		"Origin Heart",
		_CrystalTypes.SpawnKind.ORIGIN,
		500.0,
		true,
		3.2,
		0.0,
		0.0
	))
	_register(_make(
		&"ruin_miniboss",
		"Ruin Shard",
		_CrystalTypes.SpawnKind.RUIN,
		120.0,
		false,
		1.1,
		0.12,
		8.0
	))
	_register(_make(
		&"artifact_node",
		"Artifact Node",
		_CrystalTypes.SpawnKind.ARTIFACT,
		80.0,
		false,
		0.7,
		0.08,
		5.0
	))


static func register_all(defs: Array) -> void:
	for def in defs:
		if def is _SpawnPointDef:
			_register(def)


static func get_def(id: StringName) -> _SpawnPointDef:
	return _defs.get(id)


static func get_def_for_kind(kind: int) -> _SpawnPointDef:
	for def in _defs.values():
		if def.spawn_kind == kind:
			return def
	return null


static func _register(def: _SpawnPointDef) -> void:
	_defs[def.id] = def


static func _make(
	id: StringName,
	label: String,
	kind: int,
	health: float,
	boss: bool,
	emit: float,
	weaken: float,
	drain: float
) -> _SpawnPointDef:
	var d := _SpawnPointDef.new()
	d.id = id
	d.display_name = label
	d.spawn_kind = kind
	d.max_health = health
	d.is_boss = boss
	d.emit_rate = emit
	d.weaken_factor = weaken
	d.power_drain = drain
	return d