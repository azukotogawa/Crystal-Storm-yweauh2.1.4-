shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// A built-in TIME read would pulse without that bind, so the check would miss a stale material.
uniform sampler2D texture_atlas : source_color, filter_nearest, repeat_disable;
uniform vec2 atlas_grid = vec2(7.0, 10.0);
uniform vec2 ground_cell = vec2(6.0, 3.0);
uniform float albedo_tint = 0.28;
uniform vec4 albedo_color : source_color = vec4(0.72, 0.28, 1.0, 0.88);
uniform vec4 emission_color : source_color = vec4(0.55, 0.18, 0.95, 1.0);
uniform float emission_energy = 0.42;
uniform float crystal_time = 0.0;

#include "res://shaders/atlas_sample.gdshaderinc"

void fragment() {
	vec4 tex = cs_sample_atlas(texture_atlas, atlas_grid, ground_cell, UV);
	float wave = sin(crystal_time * 3.6);
	float glow = emission_energy * (1.05 + 0.55 * wave);
	vec3 tint = mix(vec3(1.0), albedo_color.rgb, clamp(albedo_tint, 0.0, 1.0));
	ALBEDO = tex.rgb * tint;
	EMISSION = emission_color.rgb * glow;
	ALPHA = tex.a * albedo_color.a;
	ALPHA_SCISSOR_THRESHOLD = 0.35;
	ROUGHNESS = 0.08;
	METALLIC = 0.42;
	RIM = 0.42;
	RIM_TINT = 0.65;
	CLEARCOAT = 0.35;
	CLEARCOAT_ROUGHNESS = 0.12;
}
