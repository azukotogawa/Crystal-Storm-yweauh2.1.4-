class_name CrystalCell
extends RefCounted

var world_pos: Vector2i = Vector2i.ZERO
var terrain_y: float = 0.0
var depth: float = 0.0
var spawn_id: int = -1


func _init(p_pos: Vector2i, p_terrain: float, p_depth: float, p_spawn_id: int = -1) -> void:
	world_pos = p_pos
	terrain_y = p_terrain
	depth = p_depth
	spawn_id = p_spawn_id


func top_y() -> float:
	return terrain_y + depth
