class_name CrystalTerrainQuery
extends RefCounted

const _CrystalTypes = preload("res://helpers/crystal_types.gd")

var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager


func get_terrain_height(pos: Vector2i) -> float:
	if world == null:
		return 0.0
	if world.has_method("get_surface_height_smooth"):
		return world.get_surface_height_smooth(float(pos.x), float(pos.y))
	return world.get_surface_height(float(pos.x), float(pos.y))


func get_tile(pos: Vector2i) -> int:
	if world == null:
		return VoxelTypes.AIR
	return world.get_tile_type(float(pos.x), float(pos.y))


func is_water_tile(tile_id: int) -> bool:
	return _CrystalTypes.is_water_tile(tile_id)