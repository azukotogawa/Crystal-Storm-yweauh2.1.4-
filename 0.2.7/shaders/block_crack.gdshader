shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_mix, depth_draw_always, fog_disabled;

uniform vec4 crack_tint : source_color = vec4(0.08, 0.06, 0.05, 0.92);
uniform float stage = 1.0;
uniform float progress = 0.5;

varying vec3 v_local;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec2 uv = v_local.xz;
	if (abs(v_local.y) >= abs(v_local.x) && abs(v_local.y) >= abs(v_local.z)) {
		uv = v_local.xz;
	} else if (abs(v_local.x) >= abs(v_local.z)) {
		uv = v_local.zy;
	} else {
		uv = v_local.xy;
	}
	uv *= 5.0;
	float s = clamp(stage, 0.0, 3.0);
	float n = hash21(floor(uv + vec2(s, 0.0)));
	float d = 1.0;
	if (s >= 1.0) {
		d = min(d, abs(fract(uv.x * 1.7 + n) - 0.5));
	}
	if (s >= 2.0) {
		d = min(d, abs(fract(uv.y * 2.4 + n * 1.7) - 0.38));
	}
	if (s >= 3.0) {
		d = min(d, abs(fract((uv.x + uv.y) * 1.15 + n) - 0.5));
	}
	float width = 0.045 + max(s - 1.0, 0.0) * 0.012;
	float band = smoothstep(width, 0.0, d);
	if (s < 0.5 || band < 0.2) {
		discard;
	}
	ALBEDO = crack_tint.rgb;
	ALPHA = crack_tint.a * band * clamp(progress, 0.2, 1.0);
}
