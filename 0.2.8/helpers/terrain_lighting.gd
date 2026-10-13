class_name TerrainLighting
extends RefCounted
## Quality hook for baked AO and contact blobs.
## Detail, sun shade, and cave fog stay on at every preset.

const _AO = preload("res://helpers/terrain_vertex_ao.gd")
const _Shadow = preload("res://helpers/contact_shadow.gd")
const _Quality = preload("res://config/performance_quality_config.gd")

const SUN := Vector3(0.55, 0.82, 0.38)


static func cheap_for_preset(preset: int) -> bool:
	return preset != int(_Quality.Preset.LOW) and preset != int(_Quality.Preset.SAFE)


static func apply_preset(preset: int) -> void:
	var cheap := cheap_for_preset(preset)
	_AO.bake_enabled = cheap
	ensure_globals()
	RenderingServer.global_shader_parameter_set("terrain_ao_strength", 1.0 if cheap else 0.0)
	RenderingServer.global_shader_parameter_set("terrain_sun_dir", SUN)
	RenderingServer.global_shader_parameter_set("terrain_detail", 1.0)
	RenderingServer.global_shader_parameter_set("terrain_cave_fog", 0.55)
	_Shadow.set_globally_enabled(cheap)


static func ensure_globals() -> void:
	var have := PackedStringArray()  # get_list is editor-only; see _add(
	_add(have, &"terrain_ao_strength", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0)
	_add(have, &"terrain_sun_dir", RenderingServer.GLOBAL_VAR_TYPE_VEC3, SUN)
	_add(have, &"terrain_detail", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0)
	_add(have, &"terrain_cave_fog", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.55)


static func _add(have: PackedStringArray, param: StringName, type: int, default_value: Variant) -> void:
	if have.has(String(param)) or Engine.has_meta(&"sg_" + String(param)) \
			or ProjectSettings.has_setting("shader_globals/" + String(param)):
		return
	Engine.set_meta(&"sg_" + String(param), true)  # shared registry: camera + terrain_lighting both register terrain_*
	RenderingServer.global_shader_parameter_add(param, type, default_value)
