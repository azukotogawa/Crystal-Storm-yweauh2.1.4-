shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// crystal_time is written every frame on the material the crystal mesh draws.
// A built-in TIME read would pulse without that bind, so the check would miss a stale material.
uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_disable;
uniform vec4 albedo_color : source_color = vec4(0.72, 0.28, 1.0, 0.88);
uniform vec4 emission_color : source_color = vec4(0.55, 0.18, 0.95, 1.0);
uniform float emission_energy = 2.15;
uniform float crystal_time = 0.0;

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	float wave = sin(crystal_time * 3.6);
	float glow = emission_energy * (1.05 + 0.55 * wave);
	ALBEDO = tex.rgb * albedo_color.rgb;
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
