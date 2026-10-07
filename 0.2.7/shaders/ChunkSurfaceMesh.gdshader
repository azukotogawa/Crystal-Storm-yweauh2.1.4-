shader_type spatial;

// Face-authored shade (COLOR.b) plus a world-up hemisphere. Engine Lambert
// with a single directional light blacks any face away from the sun — unusable
// at the iso camera. Unshaded fill never drops a readable terrain/ramp face
// to black. cull_disabled keeps 45° slopes visible from both sides.
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D texture_atlas : source_color, filter_nearest;
uniform vec2 atlas_grid = vec2(7.0, 10.0);

varying vec2 voxel_uv;
varying flat vec4 face_tint;
varying float fill_light;


void vertex() {
	voxel_uv = UV;
	face_tint = COLOR;
	// Fake iso key light so slopes, tops, and vertical cuts read apart without
	// Lambert black-out. Chunks are not rotated; NORMAL is world-ish.
	vec3 L = normalize(vec3(0.55, 0.82, 0.38));
	vec3 n = normalize(NORMAL);
	float ndl = clamp(dot(n, L), 0.0, 1.0);
	float hemi = clamp(n.y * 0.5 + 0.5, 0.0, 1.0);
	fill_light = 0.52 + 0.28 * hemi + 0.28 * ndl;
}


void fragment() {
	vec2 repeated_uv = fract(max(voxel_uv, vec2(0.0)));
	vec2 tile_size = 1.0 / atlas_grid;
	vec2 padding = vec2(1.0 / 32.0);
	vec2 local_uv = mix(padding, vec2(1.0) - padding, repeated_uv);

	vec2 col_row = floor(face_tint.rg * 255.0 + 0.5);
	vec4 tex_color = vec4(0.35, 0.42, 0.22, 1.0);
	// Out-of-range COLOR (missing vertex color / empty atlas slot) used to
	// sample the black unused cells of Cube.png — those read as opaque black
	// holes, not missing geometry.
	if (col_row.x >= 0.0 && col_row.y >= 0.0 && col_row.x < atlas_grid.x && col_row.y < atlas_grid.y) {
		vec2 atlas_uv = col_row / atlas_grid;
		tex_color = texture(texture_atlas, atlas_uv + (local_uv * tile_size));
	}
	if (tex_color.a < 0.1 || dot(tex_color.rgb, vec3(0.33, 0.33, 0.34)) < 0.04) {
		tex_color = vec4(0.35, 0.42, 0.22, 1.0);
	}

	float shade = max(face_tint.b, 0.55);
	ALBEDO = tex_color.rgb * shade * fill_light;
}