class_name TerrainLighting
extends RefCounted
## Detail, sun shade, and cave fog stay on at every preset.

const _AO = preload("res://helpers/terrain_vertex_ao.gd")
const _Shadow = preload("res://helpers/contact_shadow.gd")
const _Quality = preload("res://config/performance_quality_config.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const SUN := Vector3(0.62, 0.57, 0.54)


static func cheap_for_preset(preset: int) -> bool:
	return preset != int(_Quality.Preset.LOW) and preset != int(_Quality.Preset.SAFE)


static func apply_preset(preset: int) -> void:
	var cheap := cheap_for_preset(preset)
	var cfg = _Quality.apply_preset(preset)
	_AO.bake_enabled = cheap
	ensure_globals()
	RenderingServer.global_shader_parameter_set("terrain_ao_strength", 1.0 if cheap else 0.0)
	RenderingServer.global_shader_parameter_set("terrain_sun_dir", SUN)
	RenderingServer.global_shader_parameter_set("terrain_detail", 1.0)
	RenderingServer.global_shader_parameter_set("terrain_cave_fog", 0.55)
	RenderingServer.global_shader_parameter_set("terrain_corner_darken", float(cfg.terrain_corner_darken))
	RenderingServer.global_shader_parameter_set("terrain_shadow_darken", float(cfg.terrain_shadow_darken))
	RenderingServer.global_shader_parameter_set("terrain_cell_size", _cell_size())
	RenderingServer.global_shader_parameter_set("terrain_day_gain", 1.0)
	_Shadow.set_globally_enabled(cheap)


static func ensure_globals() -> void:
	var have := PackedStringArray()  # get_list is editor-only; see _add(
	_add(have, &"terrain_ao_strength", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0)
	_add(have, &"terrain_sun_dir", RenderingServer.GLOBAL_VAR_TYPE_VEC3, SUN)
	_add(have, &"terrain_detail", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0)
	_add(have, &"terrain_cave_fog", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.55)
	_add(have, &"terrain_corner_darken", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.42)
	_add(have, &"terrain_shadow_darken", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.45)
	_add(have, &"terrain_cell_size", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 2.0)
	_add(have, &"terrain_day_gain", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0)
	_add(have, &"torch_count", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	_add(have, &"torch_0", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO)
	_add(have, &"torch_1", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO)
	_add(have, &"torch_2", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO)
	_add(have, &"torch_3", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO)
	_add(have, &"torch_4", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO)
	_add(have, &"torch_5", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO)
	_add(have, &"torch_6", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO)
	_add(have, &"torch_7", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO)


static func _cell_size() -> float:
	var ws = _WorldSettings.get_active()
	if ws == null:
		return 2.0
	return maxf(float(ws.voxel_scale), 0.25)


static func _add(have: PackedStringArray, param: StringName, type: int, default_value: Variant) -> void:
	if have.has(String(param)) or Engine.has_meta(&"sg_" + String(param)) \
			or ProjectSettings.has_setting("shader_globals/" + String(param)):
		return
	Engine.set_meta(&"sg_" + String(param), true)  # shared registry: camera + terrain_lighting both register terrain_*
	RenderingServer.global_shader_parameter_add(param, type, default_value)
