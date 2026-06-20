class_name CrystalCell
extends RefCounted

var world_pos: Vector2i = Vector2i.ZERO
var surface_y: int = 0
var bridge: bool = false
var source_tile: int = VoxelTypes.AIR
var spawn_id: int = -1
var growth_stage: float = 1.0


func _init(
	p_pos: Vector2i,
	p_surface_y: int,
	p_source_tile: int,
	p_spawn_id: int = -1,
	p_bridge: bool = false
) -> void:
	world_pos = p_pos
	surface_y = p_surface_y
	source_tile = p_source_tile
	spawn_id = p_spawn_id
	bridge = p_bridge