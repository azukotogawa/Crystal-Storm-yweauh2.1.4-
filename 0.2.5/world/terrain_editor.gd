class_name TerrainEditor
extends Node

const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _StatIds = preload("res://stats/stat_ids.gd")
const _BuildingRegistry = preload("res://building/building_registry.gd")
const _PlantableRegistry = preload("res://world/plantable_registry.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")

var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager


func _ready() -> void:
	add_to_group("terrain_editor")
	_TerrainEdits.reset()
	_BuildingRegistry.ensure_builtins()
	_PlantableRegistry.ensure_builtins()
	world = get_tree().get_first_node_in_group("world")
	chunk_manager = get_tree().get_first_node_in_group("chunk_manager")


func get_dig_delay(world_pos: Vector3) -> float:
	var wx := floori(world_pos.x)
	var wz := floori(world_pos.z)
	var dug_depth := maxf(0.0, -_TerrainEdits.get_height_delta(wx, wz))
	var base_delay := 0.1 + dug_depth * 0.18 + dug_depth * dug_depth * 0.35
	var dig_speed := 1.0
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("get_stat"):
		dig_speed = maxf(player.get_stat(_StatIds.DIG_SPEED), 0.1)
	return base_delay / dig_speed


func try_dig(world_pos: Vector3) -> bool:
	if world == null or chunk_manager == null:
		return false
	var wx := floori(world_pos.x)
	var wz := floori(world_pos.z)
	var base_h: float = world.get_surface_height(float(wx), float(wz))
	if base_h + _TerrainEdits.get_height_delta(wx, wz) <= -2.0:
		return false
	if not _TerrainEdits.dig(wx, wz, 1):
		return false
	_invalidate_and_rebuild(wx, wz)
	return true


func try_build_wall(world_pos: Vector3, inventory, prefer_stone: bool = true) -> bool:
	var build_id: StringName = &"stone_wall" if prefer_stone else &"wood_wall"
	return try_build(world_pos, inventory, build_id)


func try_build(world_pos: Vector3, inventory, buildable_id: StringName = &"stone_wall") -> bool:
	if world == null or chunk_manager == null or inventory == null:
		return false
	var def = _BuildingRegistry.get_def(buildable_id)
	if def == null:
		return try_build_wall(world_pos, inventory, buildable_id == &"stone_wall")

	var wx := floori(world_pos.x)
	var wz := floori(world_pos.z)
	var mat_count := int(def.material_count)
	var build_cost_mult := 1.0
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("get_stat"):
		build_cost_mult = maxf(player.get_stat(_StatIds.BUILD_COST), 0.1)
	mat_count = maxi(1, int(ceil(float(mat_count) * build_cost_mult)))

	if not inventory.consume_item(def.material_id, mat_count):
		if def.material_id == "stone" and inventory.consume_item("wood", def.wood_fallback_count):
			pass
		else:
			return false

	if not _TerrainEdits.build_wall(wx, wz, def.tile_id):
		inventory.add_item(def.material_id, mat_count)
		return false
	_invalidate_and_rebuild(wx, wz)
	return true


func try_plant(world_pos: Vector3, inventory, plant_id: StringName = &"grass_tuft") -> bool:
	if world == null or chunk_manager == null or inventory == null:
		return false
	var def = _PlantableRegistry.get_def(plant_id)
	if def == null:
		return false
	var wx := floori(world_pos.x)
	var wz := floori(world_pos.z)
	if not _TerrainEdits.can_edit(wx, wz):
		return false
	if not _can_plant_at(wx, wz):
		return false
	if not inventory.consume_item(def.material_id, def.material_cost):
		return false
	_FeatureRegistry.set_tile_override(wx, wz, def.tile_id)
	_FeatureRegistry.register_feature(wx, wz, def.feature_kind, {"player_placed": true})
	_invalidate_and_rebuild(wx, wz)
	return true


func try_channel_water(world_pos: Vector3, inventory = null) -> bool:
	if world == null or chunk_manager == null:
		return false
	var wx := floori(world_pos.x)
	var wz := floori(world_pos.z)
	if not _TerrainEdits.can_edit(wx, wz):
		return false
	var surf: float = world.get_surface_height(float(wx), float(wz))
	if surf > 52.0 and not _has_adjacent_water(wx, wz):
		return false
	if inventory and not inventory.consume_item("stone", 1):
		return false
	if not _TerrainEdits.dig(wx, wz, 1):
		if inventory:
			inventory.add_item("stone", 1)
		return false
	var tile := VoxelTypes.RIVER if _has_adjacent_water(wx, wz) else VoxelTypes.WATER
	_FeatureRegistry.set_tile_override(wx, wz, tile)
	_FeatureRegistry.register_feature(wx, wz, _WorldFeatureTypes.FeatureKind.NONE, {"channel": true})
	_invalidate_and_rebuild(wx, wz)
	return true


func _can_plant_at(wx: int, wz: int) -> bool:
	if _TerrainEdits.get_build_tile(wx, wz) >= 0:
		return false
	var tile := world.get_tile_type(float(wx), float(wz))
	if tile in [
		VoxelTypes.RIVER, VoxelTypes.WATER, VoxelTypes.OCEAN, VoxelTypes.OCEAN2,
		VoxelTypes.STONE, VoxelTypes.STONE2,
		VoxelTypes.GRASS_TUFT, VoxelTypes.BUSH, VoxelTypes.TREE_TRUNK,
	]:
		return false
	var feat: Dictionary = _FeatureRegistry.get_feature(wx, wz)
	if not feat.is_empty():
		var kind: int = int(feat.get("kind", _WorldFeatureTypes.FeatureKind.NONE))
		if kind in [_WorldFeatureTypes.FeatureKind.TOWN, _WorldFeatureTypes.FeatureKind.RUIN]:
			return false
	return true


func _has_adjacent_water(wx: int, wz: int) -> bool:
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			if dx == 0 and dz == 0:
				continue
			var t := world.get_tile_type(float(wx + dx), float(wz + dz))
			if t in [VoxelTypes.RIVER, VoxelTypes.WATER, VoxelTypes.OCEAN, VoxelTypes.OCEAN2]:
				return true
	return false


func _invalidate_and_rebuild(wx: int, wz: int) -> void:
	if world and world.has_method("invalidate_column_cache"):
		world.invalidate_column_cache(wx, wz)
	if chunk_manager and chunk_manager.has_method("rebuild_chunk_at_world"):
		chunk_manager.rebuild_chunk_at_world(float(wx), float(wz))