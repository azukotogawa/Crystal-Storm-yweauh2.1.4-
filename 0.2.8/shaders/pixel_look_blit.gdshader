shader_type canvas_item;

uniform sampler2D world_tex : source_color, filter_nearest;
uniform vec2 subpixel = vec2(0.0, 0.0);
uniform vec2 tex_pixel_size = vec2(0.00208333, 0.00370370);
uniform bool banding_enabled = false;
uniform float banding_steps = 16.0;
uniform bool outline_enabled = false;
uniform vec4 outline_color : source_color = vec4(0.12, 0.08, 0.05, 0.55);
uniform float outline_strength = 0.65;

void fragment() {
	// Sub-pixel remainder shifts the sample so the snapped camera does not shimmer.
	vec2 uv = UV + subpixel * tex_pixel_size;
	vec4 col = texture(world_tex, uv);

	if (outline_enabled) {
		float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
		float l_l = dot(texture(world_tex, uv + vec2(-tex_pixel_size.x, 0.0)).rgb, vec3(0.299, 0.587, 0.114));
		float l_r = dot(texture(world_tex, uv + vec2(tex_pixel_size.x, 0.0)).rgb, vec3(0.299, 0.587, 0.114));
		float l_u = dot(texture(world_tex, uv + vec2(0.0, -tex_pixel_size.y)).rgb, vec3(0.299, 0.587, 0.114));
		float l_d = dot(texture(world_tex, uv + vec2(0.0, tex_pixel_size.y)).rgb, vec3(0.299, 0.587, 0.114));
		float edge = abs(lum - l_l) + abs(lum - l_r) + abs(lum - l_u) + abs(lum - l_d);
		edge = clamp(edge * outline_strength * 2.5, 0.0, 1.0);
		col.rgb = mix(col.rgb, outline_color.rgb, edge * outline_color.a);
	}

	if (banding_enabled) {
		float steps = max(banding_steps, 2.0);
		col.rgb = floor(col.rgb * steps + 0.5) / steps;
	}

	COLOR = col;
}
