class_name PerformanceService
extends Node

const _PerformanceQualityConfig = preload("res://config/performance_quality_config.gd")
const _TopographicalMapConfig = preload("res://config/topographical_map_config.gd")
const _WorldGenConfig = preload("res://config/world_gen_config.gd")

var quality: _PerformanceQualityConfig = _PerformanceQualityConfig.create_default()


func _enter_tree() -> void:
	add_to_group("performance_service")


func apply_quality(cfg: _PerformanceQualityConfig) -> void:
	if cfg == null:
		return
	quality = cfg
	_apply_to_scene()


func apply_preset(which: int) -> void:
	apply_quality(_PerformanceQualityConfig.apply_preset(which))


func _ready() -> void:
	call_deferred("_apply_to_scene")


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
		var cfg_svc = get_tree().get_first_node_in_group("config_service")
		if cfg_svc and cfg_svc.world_gen is _WorldGenConfig:
			cfg_svc.world_gen.caves_enabled = quality.caves_enabled

	var crystal = get_tree().get_first_node_in_group("crystal_manager")
	if crystal and crystal.has_method("apply_performance_config"):
		crystal.apply_performance_config(quality)

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

	var combat_vfx = get_tree().get_first_node_in_group("combat_visual_feedback")
	if combat_vfx and combat_vfx.has_method("apply_performance_config"):
		combat_vfx.apply_performance_config(quality)

	var entity_mgr = get_tree().get_first_node_in_group("entity_manager")
	if entity_mgr and entity_mgr.has_method("apply_performance_config"):
		entity_mgr.apply_performance_config(quality)

	var cfg_svc = get_tree().get_first_node_in_group("config_service")
	var veg_mgr = get_tree().get_first_node_in_group("vegetation_manager")
	if veg_mgr and cfg_svc and cfg_svc.world_gen:
		var wg = cfg_svc.world_gen
		if "vegetation_scatter_attempts" in veg_mgr:
			var base: int = int(wg.vegetation_scatter_attempts)
			veg_mgr.scatter_attempts = maxi(0, int(float(base) * quality.vegetation_scatter_multiplier))

	print("[Perf] Applied preset=%d dist=%d caves=%s crystal_skip=%d flow_cap=%d map=%.1fs" % [
		quality.preset,
		quality.render_distance,
		quality.caves_enabled,
		quality.crystal_sim_skip_frames,
		quality.max_crystal_flow_cells,
		quality.map_rebuild_interval_sec,
	])