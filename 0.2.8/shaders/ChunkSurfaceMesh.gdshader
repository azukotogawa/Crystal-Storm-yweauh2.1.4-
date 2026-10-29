shader_type spatial;

// Face-authored shade (COLOR.b) plus a world-up hemisphere. light() multiplies
// shadow attenuation only. Lambert would black the faces the iso camera sees
// edge-on. Terrain does not cast. cull_disabled keeps 45° slopes visible.
render_mode ambient_light_disabled, specular_disabled, cull_disabled, depth_draw_opaque;

// Cave cutaway. Keep in sync with helpers/camera_cutaway.gd and ChunkView.gdshader.
global uniform float cutaway_enabled;
global uniform vec3 cutaway_player;
global uniform vec3 cutaway_camera;
global uniform float cutaway_radius;
global uniform float cutaway_radius_near;
global uniform float cutaway_feet_clear;
global uniform float cutaway_past;

uniform sampler2D texture_atlas : source_color, filter_nearest, repeat_disable;
uniform vec2 atlas_grid = vec2(7.0, 10.0);

#include "res://shaders/atlas_sample.gdshaderinc"
#include "res://shaders/terrain_shade.gdshaderinc"

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
	if (cutaway_enabled > 0.5) {
		vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		if (world_pos.y > cutaway_player.y + cutaway_feet_clear) {
			vec3 ab = cutaway_player + vec3(0.0, 1.4, 0.0) - cutaway_camera;
			float ab_len2 = dot(ab, ab);
			if (ab_len2 > 0.01) {
				float t = dot(ab, world_pos - cutaway_camera) / ab_len2;
				float ahead = (1.0 - t) * sqrt(ab_len2);
				if (t > 0.05 && ahead > cutaway_past) {
					float tc = clamp(t, 0.0, 1.0);
					vec3 closest = cutaway_camera + ab * tc;
					float dist = distance(world_pos, closest);
					float rad = mix(cutaway_radius_near, cutaway_radius, tc);
					float edge = rad * 0.78;
					if (dist < edge) {
						discard;
					} else if (dist < rad) {
						float dither = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
						if (dither > (dist - edge) / max(rad - edge, 0.001)) {
							discard;
						}
					}
				}
			}
		}
	}
	vec2 repeated_uv = max(voxel_uv, vec2(0.0));
	vec2 col_row = floor(face_tint.rg * 255.0 + 0.5);
	vec4 tex_color = vec4(0.35, 0.42, 0.22, 1.0);
	// Out-of-range COLOR (missing vertex color / empty atlas slot) used to
	// sample the black unused cells of Cube.png — those read as opaque black
	// holes, not missing geometry.
	if (col_row.x >= 0.0 && col_row.y >= 0.0 && col_row.x < atlas_grid.x && col_row.y < atlas_grid.y) {
		tex_color = cs_sample_atlas(texture_atlas, atlas_grid, col_row, repeated_uv);
	}
	// Near-black unused slots only. A 0.04 cutoff also matched the dark half of
	// real tiles (grass sits on that line) and replaced them with one flat
	// color, which reads as a grid at ortho 16.
	if (tex_color.a < 0.1 || dot(tex_color.rgb, vec3(0.33, 0.33, 0.34)) < 0.002) {
		tex_color = vec4(0.35, 0.42, 0.22, 1.0);
	}

	float shade = max(face_tint.b, 0.55);
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	ALBEDO = cs_depth(tex_color.rgb * shade * fill_light, world_n, world_pos, face_tint.a);
}

void light() {
	float lit = clamp(ATTENUATION, 0.0, 1.0);
	float dark = clamp(terrain_shadow_darken, 0.0, 0.8);
	DIFFUSE_LIGHT += vec3(mix(1.0 - dark, 1.0, lit));
}