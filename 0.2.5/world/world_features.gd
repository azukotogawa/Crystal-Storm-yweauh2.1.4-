extends Node

const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _TownManager = preload("res://world/town_manager.gd")
const _VegetationManager = preload("res://world/vegetation_manager.gd")
const _EntityManager = preload("res://entities/entity_manager.gd")
const _RuinManager = preload("res://world/ruin_manager.gd")

# Orchestrates town, vegetation, and animal placement before chunk visuals finalize.

var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager
var bootstrap_complete: bool = false


func _ready() -> void:
	add_to_group("world_features")
	_bootstrap()


func ensure_ready() -> void:
	while not bootstrap_complete:
		await get_tree().process_frame


func _bootstrap() -> void:
	world = get_tree().get_first_node_in_group("world")
	while world == null:
		await get_tree().process_frame
		world = get_tree().get_first_node_in_group("world")

	_FeatureRegistry.reset()

	var town_mgr = get_node_or_null("TownManager")
	if town_mgr and town_mgr.has_method("generate"):
		town_mgr.generate()

	var veg_mgr = get_node_or_null("VegetationManager")
	if veg_mgr and veg_mgr.has_method("generate"):
		veg_mgr.generate()

	var ruin_mgr = get_node_or_null("RuinManager")
	if ruin_mgr and ruin_mgr.has_method("generate"):
		ruin_mgr.generate()

	var entity_mgr = get_node_or_null("EntityManager")
	if entity_mgr:
		entity_mgr.seed_spawns()

	bootstrap_complete = true


func on_chunk_manager_ready(cm: ChunkManager) -> void:
	chunk_manager = cm
	if chunk_manager.has_method("rebuild_chunks"):
		chunk_manager.call_deferred("rebuild_chunks")