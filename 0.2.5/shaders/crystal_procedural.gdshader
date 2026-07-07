shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// Optional shader for swapping procedural crystal textures with iridescence in materials.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 glow_color : source_color = vec4(0.72, 0.28, 1.0, 1.0);
uniform float glow_strength : hint_range(0.0, 4.0) = 1.0;
uniform float iridescence : hint_range(0.0, 1.0) = 0.35;
uniform float roughness : hint_range(0.0, 1.0) = 0.12;
uniform float metallic : hint_range(0.0, 1.0) = 0.4;

void fragment() {
	vec4 base = texture(albedo_tex, UV);
	ALBEDO = base.rgb;

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	vec3 irid_rgb = vec3(
		0.5 + 0.5 * sin(fresnel * 6.28 + UV.x * 8.0),
		0.5 + 0.5 * sin(fresnel * 6.28 + UV.y * 8.0 + 2.0),
		0.5 + 0.5 * sin(fresnel * 6.28 + (UV.x + UV.y) * 6.0 + 4.0)
	);
	ALBEDO = mix(ALBEDO, irid_rgb, iridescence * fresnel);

	EMISSION = glow_color.rgb * glow_strength * base.a * (0.35 + fresnel * 0.65);
	ROUGHNESS = roughness;
	METALLIC = metallic;
	ALPHA = base.a;
}