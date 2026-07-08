extends Node

const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")
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
	call_deferred("_bootstrap")


func ensure_ready() -> void:
	while not bootstrap_complete:
		await get_tree().process_frame


func _bootstrap() -> void:
	while get_tree().get_first_node_in_group("config_service") == null:
		await get_tree().process_frame
	var perf_svc = get_tree().get_first_node_in_group("performance_service")
	while perf_svc == null:
		await get_tree().process_frame
		perf_svc = get_tree().get_first_node_in_group("performance_service")
	if perf_svc.has_method("ensure_ready"):
		await perf_svc.ensure_ready()

	world = get_tree().get_first_node_in_group("world")
	while world == null:
		await get_tree().process_frame
		world = get_tree().get_first_node_in_group("world")

	_FeatureRegistry.reset()
	_ChannelRegistry.reset()

	var safe_mode := false
	if perf_svc.has_method("is_safe_mode"):
		safe_mode = perf_svc.is_safe_mode()

	var town_mgr = get_node_or_null("TownManager")
	if town_mgr and town_mgr.has_method("generate") and not safe_mode:
		town_mgr.generate()
		await get_tree().process_frame

	var veg_mgr = get_node_or_null("VegetationManager")
	if veg_mgr and veg_mgr.has_method("generate_scatter_async") and not safe_mode:
		await veg_mgr.generate_scatter_async()
	elif veg_mgr and veg_mgr.has_method("generate") and not safe_mode:
		veg_mgr.generate()

	var ruin_mgr = get_node_or_null("RuinManager")
	if ruin_mgr and ruin_mgr.has_method("generate") and not safe_mode:
		ruin_mgr.generate()
		await get_tree().process_frame

	var entity_mgr = get_node_or_null("EntityManager")
	if entity_mgr and not safe_mode:
		entity_mgr.seed_spawns()

	bootstrap_complete = true


func on_chunk_manager_ready(cm: ChunkManager) -> void:
	chunk_manager = cm
	# Feature registry is populated before ChunkManager exists — no full rebuild needed.