class_name RuntimeConfigResolver
extends RefCounted
## Explicit configuration precedence:
##   author defaults → project/authored config → quality preset → platform overrides → runtime debug overrides
## Quality never mutates authored WorldGenConfig as sim authority; caves_enabled lives on the policy.

const _GameConfig = preload("res://config/game_config.gd")
const _PerformanceQualityConfig = preload("res://config/performance_quality_config.gd")


static func resolve(
	defaults = null,
	project = null,
	quality = null,
	platform: Dictionary = {},
	debug: Dictionary = {}
) -> Dictionary:
	var authored = project if project != null else defaults
	if authored == null:
		authored = _GameConfig.create_default()
		if authored.has_method("ensure_defaults"):
			authored.ensure_defaults()

	var q = quality
	if q == null:
		q = _PerformanceQualityConfig.create_default()

	var policy := {
		"render_distance": int(q.render_distance) if "render_distance" in q else 3,
		"max_chunks_per_frame": int(q.max_chunks_per_frame) if "max_chunks_per_frame" in q else 2,
		"max_inflight_chunks": int(q.max_inflight_chunks) if "max_inflight_chunks" in q else 6,
		"mesh_caves": bool(q.mesh_caves) if "mesh_caves" in q else false,
		"caves_enabled": bool(q.caves_enabled) if "caves_enabled" in q else false,
		"crystal_sim_enabled": bool(q.crystal_sim_enabled) if "crystal_sim_enabled" in q else true,
		"max_crystal_flow_cells": int(q.max_crystal_flow_cells) if "max_crystal_flow_cells" in q else 280,
		"chunk_upload_budget_us": int(q.chunk_upload_budget_us) if "chunk_upload_budget_us" in q else 3500,
		"vegetation_scatter_multiplier": float(q.vegetation_scatter_multiplier) if "vegetation_scatter_multiplier" in q else 1.0,
		"use_lightweight_entity_nav": bool(q.use_lightweight_entity_nav) if "use_lightweight_entity_nav" in q else false,
		"perf_profiler_enabled": bool(q.perf_profiler_enabled) if "perf_profiler_enabled" in q else true,
		"preset": int(q.preset) if "preset" in q else 1,
	}

	_apply_dict_overrides(policy, platform)
	_apply_dict_overrides(policy, debug)

	# Authored sim config is referenced, not mutated by quality.
	var world_gen = authored.world_gen if "world_gen" in authored else null
	var crystal_sim = authored.crystal_sim if "crystal_sim" in authored else null
	var world_settings = authored.world_settings if "world_settings" in authored else null

	# Authored world_gen may declare caves for generation; quality policy may disable
	# *runtime* cave rendering/query without rewriting the resource.
	var authored_caves := true
	if world_gen != null and "caves_enabled" in world_gen:
		authored_caves = bool(world_gen.caves_enabled)
	if not debug.has("caves_enabled"):
		policy["caves_enabled"] = bool(policy.get("caves_enabled", false)) and authored_caves

	return {
		"authored_game_config": authored,
		"world_gen": world_gen,
		"crystal_sim": crystal_sim,
		"world_settings": world_settings,
		"quality": q,
		"policy": policy,
		"precedence": [
			"author_defaults",
			"project_configuration",
			"quality_preset",
			"platform_overrides",
			"runtime_debug_overrides",
		],
		"platform_overrides": platform.duplicate(true),
		"debug_overrides": debug.duplicate(true),
	}


static func _apply_dict_overrides(policy: Dictionary, overrides: Dictionary) -> void:
	for k in overrides.keys():
		policy[k] = overrides[k]


static func policy_get(resolved: Dictionary, key: String, fallback = null):
	var p: Dictionary = resolved.get("policy", {})
	if p.has(key):
		return p[key]
	return fallback


static func fold_policy_into_quality(quality, policy: Dictionary = {}):
	var base = quality
	if base == null:
		base = _PerformanceQualityConfig.create_default()
	var eff = base.duplicate(true)
	if policy.is_empty():
		return eff
	_assign_if(eff, "render_distance", policy)
	_assign_if(eff, "max_chunks_per_frame", policy)
	_assign_if(eff, "max_inflight_chunks", policy)
	_assign_if(eff, "mesh_caves", policy)
	_assign_if(eff, "caves_enabled", policy)
	_assign_if(eff, "crystal_sim_enabled", policy)
	_assign_if(eff, "max_crystal_flow_cells", policy)
	_assign_if(eff, "chunk_upload_budget_us", policy)
	_assign_if(eff, "streaming_budget_us", policy)
	_assign_if(eff, "vegetation_scatter_multiplier", policy)
	_assign_if(eff, "use_lightweight_entity_nav", policy)
	_assign_if(eff, "perf_profiler_enabled", policy)
	return eff


static func _assign_if(eff, key: String, policy: Dictionary) -> void:
	if not policy.has(key):
		return
	if key in eff:
		eff.set(key, policy[key])
