shader_type spatial;

// Water tops only. Terrain, ramps, and sides stay on ChunkSurfaceMesh.
// water_time is written on the material the water mesh draws. A built-in TIME
// read would move even when that bind is missing.
render_mode unshaded, cull_disabled, depth_draw_opaque;

global uniform float cutaway_enabled;
global uniform vec3 cutaway_player;
global uniform vec3 cutaway_camera;
global uniform float cutaway_radius;
global uniform float cutaway_radius_near;
global uniform float cutaway_feet_clear;
global uniform float cutaway_past;

uniform sampler2D texture_atlas : source_color, filter_nearest, repeat_disable;
uniform vec2 atlas_grid = vec2(7.0, 10.0);
uniform float water_time = 0.0;
// Used when the cell has no fluid-sim flow (UV2 is zero).
uniform vec2 flow_dir = vec2(1.0, 0.0);

#include "res://shaders/atlas_sample.gdshaderinc"

varying vec2 voxel_uv;
varying flat vec4 face_tint;
varying float crest;


void vertex() {
	vec2 cell = UV2;
	vec2 flow = dot(cell, cell) > 0.0001 ? cell : flow_dir;
	vec2 dir = flow / max(length(flow), 0.001);
	float along = VERTEX.x * dir.x + VERTEX.z * dir.y;
	crest = sin(along * 1.5 + water_time * 2.5);
	// 0.12 m crest. Visible at ortho 16, far below one 2 m layer.
	VERTEX.y += crest * 0.12;
	UV += dir * water_time * 0.22;
	voxel_uv = UV;
	face_tint = COLOR;
}


void fragment() {
	if (cutaway_enabled > 0.5) {
		vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		if (world_pos.y > cutaway_player.y + cutaway_feet_clear) {
			vec3 ab = cutaway_player - cutaway_camera;
			float ab_len2 = dot(ab, ab);
			if (ab_len2 > 0.01) {
				float t = dot(ab, world_pos - cutaway_camera) / ab_len2;
				float past = max(t - 1.0, 0.0) * sqrt(ab_len2);
				if (t > 0.05 && past < cutaway_past) {
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
	vec4 tex_color = vec4(0.15, 0.35, 0.55, 1.0);
	if (col_row.x >= 0.0 && col_row.y >= 0.0 && col_row.x < atlas_grid.x && col_row.y < atlas_grid.y) {
		tex_color = cs_sample_atlas(texture_atlas, atlas_grid, col_row, repeated_uv);
	}
	float shine = 0.82 + 0.18 * crest;
	ALBEDO = tex_color.rgb * shine;
}
