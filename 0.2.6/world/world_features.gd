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

	var visual_registry = get_tree().get_first_node_in_group("game_visual_registry")
	if visual_registry and visual_registry.has_method("ensure_textures_ready"):
		await visual_registry.ensure_textures_ready()
	elif visual_registry and visual_registry.has_method("ensure_ready"):
		await visual_registry.ensure_ready()

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
	if cm == null:
		return
	chunk_manager = cm

	var cfg_svc = get_tree().get_first_node_in_group("config_service")
	if cfg_svc and cfg_svc.has_method("on_chunk_manager_ready"):
		cfg_svc.on_chunk_manager_ready(cm)

	var terrain_editor = get_tree().get_first_node_in_group("terrain_editor")
	if terrain_editor and terrain_editor.has_method("bind_chunk_manager"):
		terrain_editor.bind_chunk_manager(cm)

	var entity_mgr = get_node_or_null("EntityManager")
	if entity_mgr and entity_mgr.has_method("on_chunk_manager_ready"):
		entity_mgr.on_chunk_manager_ready(cm)

	var registry = get_tree().get_first_node_in_group("game_visual_registry")
	if registry and registry.has_method("on_chunk_manager_ready"):
		registry.on_chunk_manager_ready(cm)

	var world_visuals = get_tree().get_first_node_in_group("world_visuals_root")
	if world_visuals and world_visuals.has_method("on_chunk_manager_ready"):
		world_visuals.on_chunk_manager_ready(cm)

	var combat_vfx = get_tree().get_first_node_in_group("combat_visual_feedback")
	if combat_vfx and combat_vfx.has_method("on_chunk_manager_ready"):
		combat_vfx.on_chunk_manager_ready(cm)

	var perf_svc = get_tree().get_first_node_in_group("performance_service")
	if perf_svc and perf_svc.has_method("reapply_to_chunk_manager"):
		perf_svc.reapply_to_chunk_manager(cm)

	call_deferred("_post_bootstrap_visual_refresh")


func _post_bootstrap_visual_refresh() -> void:
	var world_visuals = get_tree().get_first_node_in_group("world_visuals_root")
	if world_visuals and world_visuals.has_method("post_bootstrap_refresh"):
		await world_visuals.post_bootstrap_refresh()
		return
	var registry = get_tree().get_first_node_in_group("game_visual_registry")
	if registry and registry.has_method("post_bootstrap_refresh"):
		await registry.post_bootstrap_refresh()