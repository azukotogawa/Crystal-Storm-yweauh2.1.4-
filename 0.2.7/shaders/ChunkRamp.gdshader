shader_type spatial;

// Ramps are custom meshes with sloped normals. The voxel face-select shader
// (ChunkView) discards non-axis faces and punched black diamonds in the
// landing column. This shader always draws the wedge/corner.
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D texture_atlas : source_color, filter_nearest;
uniform vec2 atlas_grid = vec2(7.0, 10.0);

varying flat vec4 instance_data;


void vertex() {
	instance_data = INSTANCE_CUSTOM;
}


void fragment() {
	float col = floor(instance_data.r * 255.0 + 0.5);
	float row = floor(instance_data.g * 255.0 + 0.5);
	vec2 tile_size = 1.0 / atlas_grid;
	vec2 padding = vec2(1.0 / 32.0);
	vec2 repeated_uv = fract(max(UV, vec2(0.0)));
	vec2 local_uv = mix(padding, vec2(1.0) - padding, repeated_uv);
	vec2 atlas_uv = vec2(col, row) / atlas_grid;
	vec4 tex_color = texture(texture_atlas, atlas_uv + (local_uv * tile_size));
	if (tex_color.a < 0.1 || dot(tex_color.rgb, vec3(0.33, 0.33, 0.34)) < 0.04) {
		tex_color = vec4(0.35, 0.42, 0.22, 1.0);
	}
	ALBEDO = tex_color.rgb * 0.92;
}
