shader_type spatial;
render_mode unshaded, shadows_disabled, cull_disabled, blend_mix, depth_draw_opaque, fog_disabled;

instance uniform float flash_amount = 0.0;

void fragment() {
	float a = clamp(flash_amount, 0.0, 1.0);
	ALBEDO = vec3(1.0);
	EMISSION = vec3(1.0);
	ALPHA = a;
}
