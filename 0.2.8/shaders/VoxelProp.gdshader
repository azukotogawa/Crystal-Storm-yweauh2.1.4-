shader_type spatial;
render_mode ambient_light_disabled, specular_disabled, cull_back, depth_draw_opaque;

global uniform vec3 terrain_sun_dir;
global uniform float terrain_shadow_darken;
global uniform float terrain_day_gain;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform float use_texture = 0.0;
uniform float use_vertex_color = 0.0;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;

varying vec3 fill_tint;

vec3 vp_srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	vec3 n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	vec3 sun = terrain_sun_dir;
	if (dot(sun, sun) < 0.001) {
		sun = vec3(0.55, 0.82, 0.38);
	}
	float ndl = clamp(dot(n, normalize(sun)), 0.0, 1.0);
	float hemi = clamp(n.y * 0.5 + 0.5, 0.0, 1.0);
	float fill = 0.52 + 0.28 * hemi + 0.28 * ndl;
	fill_tint = vec3(fill) * mix(vec3(0.84, 0.87, 0.95), vec3(1.10, 1.06, 0.98), ndl);
}

void fragment() {
	vec3 base = albedo_color.rgb;
	if (use_vertex_color > 0.5) {
		base *= vp_srgb_to_linear(COLOR.rgb);
	}
	if (use_texture > 0.5) {
		base *= texture(albedo_texture, UV).rgb;
	}
	ALBEDO = base * fill_tint * clamp(terrain_day_gain, 0.28, 1.0);
	EMISSION = emission_color * emission_energy;
}

void light() {
	float lit = clamp(ATTENUATION, 0.0, 1.0);
	float dark = clamp(terrain_shadow_darken, 0.0, 0.8);
	DIFFUSE_LIGHT += vec3(mix(1.0 - dark, 1.0, lit));
}
