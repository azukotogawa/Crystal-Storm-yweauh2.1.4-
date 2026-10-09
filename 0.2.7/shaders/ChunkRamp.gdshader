shader_type spatial;

// Ramps are custom meshes with sloped normals. The voxel face-select shader
// (ChunkView) discards non-axis faces and punched black diamonds in the
// landing column. This shader always draws the wedge/corner.
render_mode unshaded, cull_disabled, depth_draw_opaque;

// Cave cutaway. Ramp geometry is unchanged. Keep in sync with helpers/camera_cutaway.gd.
global uniform float cutaway_enabled;
global uniform vec3 cutaway_player;
global uniform vec3 cutaway_camera;
global uniform float cutaway_radius;
global uniform float cutaway_radius_near;
global uniform float cutaway_feet_clear;
global uniform float cutaway_past;

global uniform float terrain_ao_strength;
global uniform vec3 terrain_sun_dir;
global uniform float terrain_detail;
global uniform float terrain_cave_fog;

#include "res://shaders/terrain_shade.gdshaderinc"

uniform sampler2D texture_atlas : source_color, filter_nearest;
uniform vec2 atlas_grid = vec2(7.0, 10.0);

varying flat vec4 instance_data;
varying vec3 shade_normal;


void vertex() {
	instance_data = INSTANCE_CUSTOM;
	vec3 nrm = NORMAL;
	shade_normal = dot(nrm, nrm) > 0.001 ? normalize(nrm) : vec3(0.0, 1.0, 0.0);
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
	vec3 lit_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float crystal = cs_crystal_cell(vec2(col, row));
	ALBEDO = cs_finish(tex_color.rgb, shade_normal, repeated_uv, lit_pos, 1.0, crystal);
}
