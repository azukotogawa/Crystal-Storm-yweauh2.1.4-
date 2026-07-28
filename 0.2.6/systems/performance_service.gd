class_name PerformanceService
extends Node

const _PerformanceQualityConfig = preload("res://config/performance_quality_config.gd")
const _TopographicalMapConfig = preload("res://config/topographical_map_config.gd")
const _WorldGenConfig = preload("res://config/world_gen_config.gd")
const _EntityNavigation = preload("res://entities/entity_navigation.gd")
const _RuntimeConfigResolver = preload("res://systems/runtime_config_resolver.gd")

var quality: _PerformanceQualityConfig = _PerformanceQualityConfig.create_default()
## Last effective quality after folding platform/debug policy (composition path).
var effective_quality: _PerformanceQualityConfig = null
var _safe_mode: bool = false
var _applied: bool = false


func _enter_tree() -> void:
	add_to_group("performance_service")


func apply_quality(cfg: _PerformanceQualityConfig) -> void:
	if cfg == null:
		return
	var same_preset: bool = quality != null and cfg.preset == quality.preset and _applied
	quality = cfg
	if same_preset:
		return
	if is_inside_tree():
		call_deferred("_apply_to_scene")


func apply_preset(which: int) -> void:
	_safe_mode = false
	apply_quality(_PerformanceQualityConfig.apply_preset(which))


func apply_safe_mode() -> void:
	_safe_mode = true
	apply_quality(_PerformanceQualityConfig.apply_safe_mode())


func is_safe_mode() -> bool:
	return _safe_mode


func ensure_ready() -> void:
	while not _applied:
		await get_tree().process_frame


func reapply_to_chunk_manager(cm: ChunkManager, resolved: Dictionary = {}) -> void:
	if cm == null:
		return
	var cfg = _effective_for(resolved)
	if cfg == null:
		return
	if cm.has_method("apply_performance_config"):
		cm.apply_performance_config(cfg)
	elif "RENDER_DISTANCE" in cm:
		cm.RENDER_DISTANCE = cfg.render_distance
		cm.MAX_CHUNKS_PER_FRAME = cfg.max_chunks_per_frame
		cm.MAX_INFLIGHT_CHUNKS = cfg.max_inflight_chunks
		if "MESH_CAVES" in cm:
			cm.MESH_CAVES = cfg.mesh_caves


func _effective_for(resolved: Dictionary = {}):
	if not resolved.is_empty():
		var policy: Dictionary = resolved.get("policy", {})
		effective_quality = _RuntimeConfigResolver.fold_policy_into_quality(quality, policy)
		return effective_quality
	if effective_quality != null:
		return effective_quality
	return quality


## Composition-root path: apply *resolved* policy via registry peers (no group search).
## `resolved` is EffectiveRuntimePolicy from RuntimeConfigResolver — debug/platform knobs win.
func apply_to_registered(registry, resolved: Dictionary = {}) -> void:
	if registry == null or quality == null:
		return
	var policy: Dictionary = resolved.get("policy", {})
	var eff = _RuntimeConfigResolver.fold_policy_into_quality(quality, policy)
	effective_quality = eff
	var chunk_mgr = registry.resolve(&"chunk_manager") if registry.has_method("resolve") else null
	if chunk_mgr:
		reapply_to_chunk_manager(chunk_mgr, resolved)
	var world = registry.resolve(&"world") if registry.has_method("resolve") else null
	if world and world.has_method("set_caves_enabled"):
		world.set_caves_enabled(bool(eff.caves_enabled))
	# Do NOT mutate authored world_gen.caves_enabled — quality is policy-only.
	var crystal = registry.resolve(&"crystal_manager") if registry.has_method("resolve") else null
	if crystal:
		if crystal.has_method("apply_performance_config"):
			crystal.apply_performance_config(eff)
		if crystal.has_method("refresh_spawn_marker_textures"):
			crystal.call_deferred("refresh_spawn_marker_textures")
	var visual_registry = registry.resolve(&"game_visual_registry") if registry.has_method("resolve") else null
	if visual_registry:
		if visual_registry.has_method("apply_performance_config"):
			visual_registry.apply_performance_config(eff)
		if visual_registry.has_method("preload_game_bundle"):
			visual_registry.preload_game_bundle()
	var combat_vfx = registry.resolve(&"combat_visual_feedback") if registry.has_method("resolve") else null
	if combat_vfx and combat_vfx.has_method("apply_performance_config"):
		combat_vfx.apply_performance_config(eff)
	var entity_mgr = registry.resolve(&"entity_manager") if registry.has_method("resolve") else null
	if entity_mgr and entity_mgr.has_method("apply_performance_config"):
		entity_mgr.apply_performance_config(eff)
	_EntityNavigation.use_lightweight_nav = bool(eff.use_lightweight_entity_nav)
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler:
		profiler.enabled = bool(eff.perf_profiler_enabled)
	_applied = true
	print("[Perf] Applied effective policy dist=%d caves=%s flow_cap=%d upload_budget=%dus (registry)" % [
		eff.render_distance,
		"on" if eff.caves_enabled else "off",
		eff.max_crystal_flow_cells,
		eff.chunk_upload_budget_us,
	])


func refresh_world_visuals() -> void:
	if not is_inside_tree():
		return
	var root = get_tree().get_first_node_in_group("composition_root")
	var registry = root.registry if root and "registry" in root else null
	var visual_registry = null
	if registry and registry.has_method("resolve"):
		visual_registry = registry.resolve(&"game_visual_registry")
	if visual_registry == null:
		visual_registry = get_tree().get_first_node_in_group("game_visual_registry")
	if visual_registry:
		if visual_registry.has_method("apply_performance_config"):
			visual_registry.apply_performance_config(quality)
		if visual_registry.has_method("preload_game_bundle"):
			visual_registry.preload_game_bundle(false, "PerformanceService.refresh_world_visuals")
		if visual_registry.has_method("refresh_all"):
			visual_registry.refresh_all("PerformanceService.refresh_world_visuals")
	var feature_visuals = get_tree().get_first_node_in_group("feature_visual_layer")
	if feature_visuals:
		if feature_visuals.has_method("apply_performance_config"):
			feature_visuals.apply_performance_config(quality)
		elif feature_visuals.has_method("repopulate_all"):
			feature_visuals.repopulate_all()
	var crystal = null
	if registry and registry.has_method("resolve"):
		crystal = registry.resolve(&"crystal_manager")
	if crystal == null:
		crystal = get_tree().get_first_node_in_group("crystal_manager")
	if crystal and crystal.has_method("refresh_spawn_marker_textures"):
		crystal.refresh_spawn_marker_textures()
	var combat_vfx = null
	if registry and registry.has_method("resolve"):
		combat_vfx = registry.resolve(&"combat_visual_feedback")
	if combat_vfx == null:
		combat_vfx = get_tree().get_first_node_in_group("combat_visual_feedback")
	if combat_vfx and combat_vfx.has_method("apply_performance_config"):
		combat_vfx.apply_performance_config(quality)


func _ready() -> void:
	if _env_flag("CRYSTALSTORM_SAFE_MODE") or _env_flag("CRYSTALSTORM_MINIMAL"):
		apply_safe_mode()
	elif not _apply_env_preset_if_set():
		apply_preset(_PerformanceQualityConfig.Preset.MEDIUM)


func _apply_env_preset_if_set() -> bool:
	var raw := OS.get_environment("CRYSTALSTORM_PERF_PRESET").strip_edges().to_lower()
	if raw.is_empty():
		return false
	match raw:
		"low", "0":
			apply_preset(_PerformanceQualityConfig.Preset.LOW)
		"medium", "med", "1":
			apply_preset(_PerformanceQualityConfig.Preset.MEDIUM)
		"high", "2":
			apply_preset(_PerformanceQualityConfig.Preset.HIGH)
		"safe", "minimal":
			apply_safe_mode()
		_:
			push_warning("[Perf] Unknown CRYSTALSTORM_PERF_PRESET=%s (use low|medium|high|safe)" % raw)
			apply_preset(_PerformanceQualityConfig.Preset.MEDIUM)
	return true


func _env_flag(name: String) -> bool:
	var v := OS.get_environment(name)
	return v == "1" or v.to_lower() == "true"


func _apply_to_scene() -> void:
	if not is_inside_tree():
		return

	var chunk_mgr = get_tree().get_first_node_in_group("chunk_manager")
	if chunk_mgr:
		if chunk_mgr.has_method("apply_performance_config"):
			chunk_mgr.apply_performance_config(quality)
		elif "RENDER_DISTANCE" in chunk_mgr:
			chunk_mgr.RENDER_DISTANCE = quality.render_distance
			chunk_mgr.MAX_CHUNKS_PER_FRAME = quality.max_chunks_per_frame
			chunk_mgr.MAX_INFLIGHT_CHUNKS = quality.max_inflight_chunks
			if "MESH_CAVES" in chunk_mgr:
				chunk_mgr.MESH_CAVES = quality.mesh_caves

	var world = get_tree().get_first_node_in_group("world")
	if world:
		if world.has_method("set_caves_enabled"):
			world.set_caves_enabled(quality.caves_enabled)
		# Authored WorldGenConfig is not mutated by quality (composition policy).
		# Runtime cave enablement is applied only via world.set_caves_enabled / EffectiveRuntimePolicy.

	var crystal = get_tree().get_first_node_in_group("crystal_manager")
	if crystal:
		if crystal.has_method("apply_performance_config"):
			crystal.apply_performance_config(quality)
		if crystal.has_method("refresh_spawn_marker_textures"):
			crystal.call_deferred("refresh_spawn_marker_textures")

	var map_ui = get_tree().get_first_node_in_group("topographical_map")
	if map_ui:
		if map_ui.has_method("apply_performance_config"):
			map_ui.apply_performance_config(quality)
		elif "map_config" in map_ui:
			var mc = map_ui.map_config
			if mc == null or not mc is _TopographicalMapConfig:
				mc = _TopographicalMapConfig.create_default()
				map_ui.map_config = mc
			mc.rebuild_interval_sec = quality.map_rebuild_interval_sec
			mc.minimap_size = quality.minimap_pixel_size
			mc.sample_stride = quality.map_sample_stride

	var debug = get_tree().get_first_node_in_group("debug_panel")
	if debug and debug.has_method("apply_performance_config"):
		debug.apply_performance_config(quality)

	call_deferred("refresh_world_visuals")

	var growth_mgr = get_tree().get_first_node_in_group("vegetation_growth_manager")
	if growth_mgr and growth_mgr.has_method("apply_performance_config"):
		growth_mgr.apply_performance_config(quality)

	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler:
		profiler.enabled = quality.perf_profiler_enabled

	var entity_mgr = get_tree().get_first_node_in_group("entity_manager")
	if entity_mgr and entity_mgr.has_method("apply_performance_config"):
		entity_mgr.apply_performance_config(quality)

	_EntityNavigation.use_lightweight_nav = bool(quality.use_lightweight_entity_nav)

	var cfg_svc = get_tree().get_first_node_in_group("config_service")
	var veg_mgr = get_tree().get_first_node_in_group("vegetation_manager")
	if veg_mgr and cfg_svc and cfg_svc.world_gen:
		var wg = cfg_svc.world_gen
		if "vegetation_scatter_attempts" in veg_mgr:
			var base: int = int(wg.vegetation_scatter_attempts)
			veg_mgr.scatter_attempts = maxi(0, int(float(base) * quality.vegetation_scatter_multiplier))

	_applied = true
	print("[Perf] Applied preset=%d safe=%s dist=%d crystal=%s flow_cap=%d upload_budget=%dus" % [
		quality.preset,
		_safe_mode,
		quality.render_distance,
		"on" if quality.crystal_sim_enabled else "off",
		quality.max_crystal_flow_cells,
		quality.chunk_upload_budget_us,
	])
