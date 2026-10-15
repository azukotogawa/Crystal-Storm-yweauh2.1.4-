class_name SceneLighting
extends RefCounted

const _Sun = preload("res://helpers/terrain_lighting.gd")

const AMBIENT := Color(0.34, 0.38, 0.48, 1)
const FOG_COLOR := Color(0.72, 0.78, 0.9, 1)


static func apply_from(service: Node, quality) -> void:
	if service == null or quality == null:
		return
	var host: Node = service.get_parent()
	if host == null and service.is_inside_tree():
		host = service.get_tree().root
	apply_host(host, quality)


static func apply_host(host: Node, quality) -> void:
	if host == null or quality == null:
		return
	var light := _light(host)
	if light != null:
		_apply_light(light, quality)
	var world_env := _world_env(host)
	if world_env != null:
		if world_env.environment == null:
			world_env.environment = Environment.new()
		_apply_env(world_env.environment, quality)
	var size := int(quality.shadow_atlas_size)
	if size >= 256:
		RenderingServer.directional_shadow_atlas_set_size(size, true)


static func _light(host: Node) -> DirectionalLight3D:
	var named := host.get_node_or_null("DirectionalLight3D")
	if named is DirectionalLight3D:
		return named
	return host.find_child("DirectionalLight3D", true, false) as DirectionalLight3D


static func _world_env(host: Node) -> WorldEnvironment:
	var named := host.get_node_or_null("WorldEnvironment")
	if named is WorldEnvironment:
		return named
	return host.find_child("WorldEnvironment", true, false) as WorldEnvironment


static func _apply_light(light: DirectionalLight3D, quality) -> void:
	var color := light.light_color
	var energy := light.light_energy
	var basis := light.transform.basis
	var origin := light.transform.origin
	light.shadow_enabled = bool(quality.scene_shadows)
	light.shadow_bias = float(quality.shadow_bias)
	light.shadow_normal_bias = float(quality.shadow_normal_bias)
	light.shadow_blur = float(quality.shadow_blur)
	light.directional_shadow_mode = int(quality.shadow_split_mode)
	light.directional_shadow_blend_splits = true
	light.directional_shadow_max_distance = float(quality.shadow_max_distance)
	light.directional_shadow_split_1 = float(quality.shadow_split_1)
	light.directional_shadow_split_2 = float(quality.shadow_split_2)
	light.directional_shadow_split_3 = float(quality.shadow_split_3)
	light.directional_shadow_fade_start = 0.92
	light.directional_shadow_pancake_size = float(quality.shadow_pancake)
	light.light_color = color
	light.light_energy = energy
	light.transform = Transform3D(basis, origin)
	if not _Sun.SUN.is_equal_approx(Vector3(0.55, 0.82, 0.38)):
		push_error("locked sun moved")


static func _apply_env(env: Environment, quality) -> void:
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT
	env.ambient_light_energy = float(quality.ambient_light_energy)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = float(quality.tonemap_exposure)
	env.ssao_enabled = bool(quality.ssao_enabled)
	env.ssao_radius = float(quality.ssao_radius)
	env.ssao_intensity = float(quality.ssao_intensity)
	env.ssao_power = 1.5
	env.ssao_detail = 0.35
	env.fog_enabled = bool(quality.fog_enabled)
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = FOG_COLOR
	env.fog_light_energy = float(quality.fog_light_energy)
	env.fog_sun_scatter = 0.08
	env.fog_density = float(quality.fog_density)
	env.fog_aerial_perspective = 0.12
	env.fog_sky_affect = 0.35
	env.volumetric_fog_enabled = false
