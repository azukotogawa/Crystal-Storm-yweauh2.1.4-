extends Node

const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _TownManager = preload("res://world/town_manager.gd")
const _VegetationManager = preload("res://world/vegetation_manager.gd")
const _EntityManager = preload("res://entities/entity_manager.gd")

# Orchestrates town, vegetation, and animal placement before chunk visuals finalize.

var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager


func _ready() -> void:
	call_deferred("_bootstrap")


func _bootstrap() -> void:
	world = get_tree().get_first_node_in_group("world")
	while world == null:
		await get_tree().process_frame
		world = get_tree().get_first_node_in_group("world")

	chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	while chunk_manager == null:
		await get_tree().process_frame
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")

	_FeatureRegistry.reset()

	var town_mgr = get_node_or_null("TownManager")
	if town_mgr and town_mgr.has_method("generate"):
		town_mgr.generate()

	var veg_mgr = get_node_or_null("VegetationManager")
	if veg_mgr and veg_mgr.has_method("generate"):
		veg_mgr.generate()

	var entity_mgr = get_node_or_null("EntityManager")
	if entity_mgr:
		entity_mgr.seed_spawns()

	chunk_manager.rebuild_chunks()