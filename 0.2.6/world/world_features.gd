extends Node

const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _TownManager = preload("res://world/town_manager.gd")
const _VegetationManager = preload("res://world/vegetation_manager.gd")
const _EntityManager = preload("res://entities/entity_manager.gd")
const _RuinManager = preload("res://world/ruin_manager.gd")
const _StartupProfiler = preload("res://systems/startup_profiler.gd")

# Orchestrates town, vegetation, and animal placement before chunk visuals finalize.

var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager
var bootstrap_complete: bool = false
var _composition_driven: bool = false


func _ready() -> void:
	add_to_group("world_features")
	# CompositionRoot drives bootstrap when present; legacy deferred path otherwise.
	call_deferred("_maybe_legacy_bootstrap")


func _maybe_legacy_bootstrap() -> void:
	if _composition_driven or bootstrap_complete:
		return
	# Give CompositionRoot a frame to claim ownership.
	await get_tree().process_frame
	if _composition_driven or bootstrap_complete:
		return
	if get_tree().get_first_node_in_group("composition_root") != null:
		return
	await _bootstrap()


func ensure_ready() -> void:
	while not bootstrap_complete:
		await get_tree().process_frame


## Composition-root path: explicit service refs, no group polling.
## `resolved` is EffectiveRuntimePolicy from RuntimeConfigResolver (may be empty early).
func bootstrap_with_services(registry, resolved: Dictionary = {}) -> void:
	_composition_driven = true
	if bootstrap_complete:
		return
	var perf_svc = registry.resolve(&"performance_service") if registry else null
	_StartupProfiler.begin("fs/bootstrap_perf_ready")
	if perf_svc and perf_svc.has_method("ensure_ready"):
		await perf_svc.ensure_ready()
	_StartupProfiler.end("fs/bootstrap_perf_ready")
	# Honor resolved safe-mode / crystal policy for seeding decisions.
	var policy: Dictionary = resolved.get("policy", {}) if not resolved.is_empty() else {}
	var visual_registry = registry.resolve(&"game_visual_registry") if registry else null
	_StartupProfiler.begin("fs/bootstrap_visual_textures")
	if visual_registry and visual_registry.has_method("ensure_textures_ready"):
		await visual_registry.ensure_textures_ready()
	elif visual_registry and visual_registry.has_method("ensure_ready"):
		await visual_registry.ensure_ready()
	_StartupProfiler.end("fs/bootstrap_visual_textures")
	_StartupProfiler.begin("fs/world_resolve_and_policy")
	world = registry.resolve(&"world") if registry else null
	if world == null and registry == null:
		world = get_tree().get_first_node_in_group("world")
	# Apply effective caves policy when world already present (before chunks).
	if world and world.has_method("set_caves_enabled") and policy.has("caves_enabled"):
		world.set_caves_enabled(bool(policy.get("caves_enabled")))
	_StartupProfiler.end("fs/world_resolve_and_policy")
	await _seed_content(perf_svc)
	bootstrap_complete = true


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

	await _seed_content(perf_svc)
	bootstrap_complete = true


func _seed_content(perf_svc) -> void:
	_StartupProfiler.begin("fs/registry_reset")
	_FeatureRegistry.reset()
	_ChannelRegistry.reset()
	_StartupProfiler.end("fs/registry_reset")

	var safe_mode := false
	if perf_svc and perf_svc.has_method("is_safe_mode"):
		safe_mode = perf_svc.is_safe_mode()

	# Biome Voronoi regions are built in InfiniteNoiseWorld._init (before this stage).
	_StartupProfiler.mark("fs/biome_initialization", 0)

	var town_mgr = get_node_or_null("TownManager")
	if town_mgr and town_mgr.has_method("generate") and not safe_mode:
		_StartupProfiler.begin("fs/town_generation")
		town_mgr.generate()
		_StartupProfiler.end("fs/town_generation")
		_StartupProfiler.begin("fs/await_frame_after_town")
		await get_tree().process_frame
		_StartupProfiler.end("fs/await_frame_after_town")
	else:
		_StartupProfiler.mark("fs/town_generation", 0)
		_StartupProfiler.mark("fs/town_site_search", 0)
		_StartupProfiler.mark("fs/town_ground_stamp", 0)
		_StartupProfiler.mark("fs/road_generation", 0)
		_StartupProfiler.mark("fs/resource_field_generation", 0)

	var veg_mgr = get_node_or_null("VegetationManager")
	# Baked vegetation streams with .chk packages — never scatter inside bake bounds.
	if _should_skip_runtime_vegetation_scatter():
		_StartupProfiler.mark("fs/vegetation_placement", 0)
		_StartupProfiler.mark("fs/vegetation_baked_streamed", 0)
	elif veg_mgr and veg_mgr.has_method("generate_scatter_async") and not safe_mode:
		_StartupProfiler.begin("fs/vegetation_placement")
		await veg_mgr.generate_scatter_async()
		_StartupProfiler.end("fs/vegetation_placement")
	elif veg_mgr and veg_mgr.has_method("generate") and not safe_mode:
		_StartupProfiler.begin("fs/vegetation_placement")
		veg_mgr.generate()
		_StartupProfiler.end("fs/vegetation_placement")
	else:
		_StartupProfiler.mark("fs/vegetation_placement", 0)

	var ruin_mgr = get_node_or_null("RuinManager")
	if ruin_mgr and ruin_mgr.has_method("generate") and not safe_mode:
		_StartupProfiler.begin("fs/ruin_generation")
		ruin_mgr.generate()
		_StartupProfiler.end("fs/ruin_generation")
		_StartupProfiler.begin("fs/await_frame_after_ruin")
		await get_tree().process_frame
		_StartupProfiler.end("fs/await_frame_after_ruin")
	else:
		_StartupProfiler.mark("fs/ruin_generation", 0)

	var entity_mgr = get_node_or_null("EntityManager")
	if entity_mgr and not safe_mode:
		_StartupProfiler.begin("fs/spawn_region_generation")
		entity_mgr.seed_spawns()
		_StartupProfiler.end("fs/spawn_region_generation")
	else:
		_StartupProfiler.mark("fs/spawn_region_generation", 0)

	# Categories not present in this stage (explicit zero; town marks road/farmland itself).
	_StartupProfiler.mark("fs/cave_feature_generation", 0)
	_StartupProfiler.mark("fs/navigation_generation", 0)
	_StartupProfiler.mark("fs/crystal_initialization", 0)
	_StartupProfiler.mark("fs/serialization", 0)
	_StartupProfiler.mark("fs/spatial_index_creation", 0)  # denial spatial is lazy on first query
	_StartupProfiler.mark("fs/node_creation", 0)  # seed_spawns registers spawn points; no Node spawn here


func _should_skip_runtime_vegetation_scatter() -> bool:
	var Bake = load("res://world/world_bake_service.gd")
	if Bake == null:
		return false
	var bake = Bake.get_active()
	if bake == null and Bake.has_method("ensure_active"):
		bake = Bake.ensure_active()
	if bake == null:
		return false
	if bool(bake.get("valid")) and bool(bake.get("vegetation_baked")):
		return true
	# Feature seeding runs before ChunkManager; probe index so we can skip scatter
	# when a v4+ bake with vegetation already exists on disk.
	if world == null:
		return false
	var seed: int = int(world.world_seed) if "world_seed" in world else 0
	var want_full: bool = false
	if Bake.has_method("use_full_world_from_env"):
		want_full = bool(Bake.use_full_world_from_env())
	if bake.has_method("load_bake_for_seed") and bake.load_bake_for_seed(seed, want_full):
		return bool(bake.get("vegetation_baked"))
	return false


func on_chunk_manager_ready(cm: ChunkManager) -> void:
	if cm == null:
		return
	chunk_manager = cm

	# Prefer composition root explicit handoff if available (already done by root).
	var root = get_tree().get_first_node_in_group("composition_root")
	if root and root.is_at_least(root.Stage.CHUNKS_CREATED if "Stage" in root else 4):
		call_deferred("_post_bootstrap_visual_refresh")
		return

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
		# Prefer composition-resolved policy when available so legacy path
		# still honors platform/debug overrides.
		var resolved_cfg: Dictionary = {}
		var CR = load("res://systems/composition_root.gd")
		var active = CR.get_active() if CR and CR.has_method("get_active") else null
		if active and "resolved_config" in active:
			resolved_cfg = active.resolved_config
		perf_svc.reapply_to_chunk_manager(cm, resolved_cfg)

	call_deferred("_post_bootstrap_visual_refresh")


func _post_bootstrap_visual_refresh() -> void:
	var world_visuals = get_tree().get_first_node_in_group("world_visuals_root")
	if world_visuals and world_visuals.has_method("post_bootstrap_refresh"):
		await world_visuals.post_bootstrap_refresh()
		return
	var registry = get_tree().get_first_node_in_group("game_visual_registry")
	if registry and registry.has_method("post_bootstrap_refresh"):
		await registry.post_bootstrap_refresh()
