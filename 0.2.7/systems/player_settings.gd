class_name PlayerSettings
extends RefCounted
## Persisted player settings that map to existing systems only.

const _PerformanceQualityConfig = preload("res://config/performance_quality_config.gd")

const DEFAULT_PATH := "user://player_settings.json"

static var settings_path: String = DEFAULT_PATH


static func reset_path() -> void:
	settings_path = DEFAULT_PATH


static func defaults() -> Dictionary:
	return {
		"quality_preset": int(_PerformanceQualityConfig.Preset.MEDIUM),
		"render_distance": 2,
		"vegetation_scatter_multiplier": 1.0,
		"combat_visuals_enabled": true,
	}


static func load_settings() -> Dictionary:
	var out: Dictionary = defaults()
	if not FileAccess.file_exists(settings_path):
		return out
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
	if parsed == null or not parsed is Dictionary:
		return out
	var data: Dictionary = parsed
	if data.has("quality_preset"):
		out["quality_preset"] = int(data.quality_preset)
	if data.has("render_distance"):
		out["render_distance"] = clampi(int(data.render_distance), 1, 8)
	if data.has("vegetation_scatter_multiplier"):
		out["vegetation_scatter_multiplier"] = clampf(float(data.vegetation_scatter_multiplier), 0.0, 1.0)
	if data.has("combat_visuals_enabled"):
		out["combat_visuals_enabled"] = bool(data.combat_visuals_enabled)
	return out


static func save_settings(data: Dictionary) -> bool:
	var merged: Dictionary = defaults()
	merged.merge(data, true)
	var dir := settings_path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open(settings_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(merged, "\t"))
	f.close()
	return true


## Write persisted fields onto the live quality resource (does not call apply_quality).
static func apply_to_performance(perf) -> Dictionary:
	var data: Dictionary = load_settings()
	if perf == null:
		return data
	var quality = perf.get("quality") if "quality" in perf else null
	var env_preset := OS.get_environment("CRYSTALSTORM_PERF_PRESET").strip_edges().to_lower()
	# Env preset owns quality + native render_distance. Do not apply saved
	# quality_preset / render_distance from player_settings.json.
	if not env_preset.is_empty():
		if perf.has_method("apply_env_preset_if_set"):
			perf.apply_env_preset_if_set()
		quality = perf.get("quality") if "quality" in perf else quality
		if quality == null:
			return data
	else:
		var want_preset: int = int(data.get("quality_preset", _PerformanceQualityConfig.Preset.MEDIUM))
		if quality == null or int(quality.preset) != want_preset:
			if want_preset == int(_PerformanceQualityConfig.Preset.SAFE):
				quality = _PerformanceQualityConfig.apply_safe_mode()
			else:
				quality = _PerformanceQualityConfig.apply_preset(want_preset)
			perf.quality = quality
		if quality:
			quality.render_distance = clampi(int(data.get("render_distance", quality.render_distance)), 1, 8)
	if quality == null:
		return data
	quality.vegetation_scatter_multiplier = clampf(
		float(data.get("vegetation_scatter_multiplier", quality.vegetation_scatter_multiplier)), 0.0, 1.0
	)
	quality.combat_visuals_enabled = bool(data.get("combat_visuals_enabled", true))
	return data


static func write_policy(policy: Dictionary) -> void:
	var data: Dictionary = load_settings()
	var env_preset := OS.get_environment("CRYSTALSTORM_PERF_PRESET").strip_edges().to_lower()
	var saved_preset: int = int(data.get("quality_preset", _PerformanceQualityConfig.Preset.MEDIUM))
	var live_preset: int = int(policy.get("preset", saved_preset))
	if env_preset.is_empty() and saved_preset == live_preset:
		policy["render_distance"] = clampi(int(data.get("render_distance", 2)), 1, 8)
	policy["vegetation_scatter_multiplier"] = clampf(
		float(data.get("vegetation_scatter_multiplier", 1.0)), 0.0, 1.0
	)
	if env_preset.is_empty():
		policy["preset"] = saved_preset


## After QUALITY_APPLIED: overlay player fields and push through apply_to_registered.
static func apply_after_quality(perf, registry, resolved: Dictionary = {}) -> Dictionary:
	var data: Dictionary = apply_to_performance(perf)
	if resolved.has("policy") and resolved.policy is Dictionary:
		write_policy(resolved.policy)
	if perf != null and registry != null and perf.has_method("apply_to_registered"):
		perf.apply_to_registered(registry, resolved)
	return data


static func apply_to_tree(tree: SceneTree) -> Dictionary:
	var data: Dictionary = load_settings()
	if tree == null:
		return data
	var perf = tree.get_first_node_in_group("performance_service")
	return apply_to_performance(perf)
