class_name CrystalSpawnPoint
extends RefCounted

var id: int = -1
var world_pos: Vector2i = Vector2i.ZERO
var kind: CrystalTypes.SpawnKind = CrystalTypes.SpawnKind.RUIN
var health: float = 100.0
var max_health: float = 100.0
var active: bool = true
var is_boss: bool = false


func _init(
	p_id: int,
	p_pos: Vector2i,
	p_kind: CrystalTypes.SpawnKind,
	p_health: float = 100.0,
	p_boss: bool = false
) -> void:
	id = p_id
	world_pos = p_pos
	kind = p_kind
	max_health = p_health
	health = p_health
	is_boss = p_boss


func apply_damage(amount: float) -> bool:
	if not active:
		return false
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		active = false
		return true
	return false