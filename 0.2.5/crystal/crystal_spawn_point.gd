class_name CrystalSpawnPoint
extends RefCounted

const _SpawnPointDef = preload("res://config/spawn_point_def.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")

var id: int = -1
var world_pos: Vector2i = Vector2i.ZERO
var kind: int = _CrystalTypes.SpawnKind.RUIN
var health: float = 100.0
var max_health: float = 100.0
var active: bool = true
var is_boss: bool = false
var emit_rate: float = 1.0
var def_id: StringName = &""
var display_name: String = "Crystal Spawn"
var weaken_factor: float = 0.0
var power_drain: float = 0.0


func _init(
	p_id: int,
	p_pos: Vector2i,
	p_kind: int,
	p_health: float = 100.0,
	p_boss: bool = false
) -> void:
	id = p_id
	world_pos = p_pos
	kind = p_kind
	max_health = p_health
	health = p_health
	is_boss = p_boss
	emit_rate = _CrystalTypes.emit_rate_for(p_kind)


static func from_def(p_id: int, p_pos: Vector2i, def: _SpawnPointDef) -> CrystalSpawnPoint:
	var spawn := CrystalSpawnPoint.new(
		p_id,
		p_pos,
		def.spawn_kind,
		def.max_health,
		def.is_boss
	)
	spawn.def_id = def.id
	spawn.display_name = def.display_name
	spawn.emit_rate = def.emit_rate
	spawn.weaken_factor = def.weaken_factor
	spawn.power_drain = def.power_drain
	return spawn


func apply_damage(amount: float) -> bool:
	if not active:
		return false
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		active = false
		return true
	return false