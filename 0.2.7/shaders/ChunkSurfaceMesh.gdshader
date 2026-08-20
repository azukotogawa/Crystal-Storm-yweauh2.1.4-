shader_type spatial;

render_mode cull_back, depth_draw_opaque, diffuse_lambert;

uniform sampler2D texture_atlas : source_color, filter_nearest;
uniform vec2 atlas_grid = vec2(7.0, 10.0);

varying vec2 voxel_uv;
varying vec4 face_tint;


void vertex() {
	voxel_uv = UV;
	face_tint = COLOR;
}


void fragment() {
	vec2 repeated_uv = fract(voxel_uv);
	vec2 tile_size = 1.0 / atlas_grid;
	vec2 padding = vec2(1.0 / 32.0);
	vec2 local_uv = mix(padding, vec2(1.0) - padding, repeated_uv);

	vec2 col_row = floor(face_tint.rg * 255.0 + 0.5);
	vec2 atlas_uv = col_row / atlas_grid;
	vec4 tex_color = texture(texture_atlas, atlas_uv + (local_uv * tile_size));

	if (tex_color.a < 0.1) {
		discard;
	}

	ALBEDO = tex_color.rgb * face_tint.b;
}