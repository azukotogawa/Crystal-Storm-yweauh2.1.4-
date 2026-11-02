shader_type spatial;

// Ramps are custom meshes with sloped normals. The voxel face-select shader
// (ChunkView) discards non-axis faces and punched black diamonds in the
// landing column. This shader always draws the wedge/corner.
render_mode ambient_light_disabled, specular_disabled, cull_disabled, depth_draw_opaque;

// Cave cutaway. Ramp geometry is unchanged. Keep in sync with helpers/camera_cutaway.gd.
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

varying flat vec4 instance_data;


void vertex() {
	instance_data = INSTANCE_CUSTOM;
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
	float col = floor(instance_data.r * 255.0 + 0.5);
	float row = floor(instance_data.g * 255.0 + 0.5);
	vec2 repeated_uv = max(UV, vec2(0.0));
	vec4 tex_color = cs_sample_atlas(texture_atlas, atlas_grid, vec2(col, row), repeated_uv);
	// Same near-black gate as ChunkSurfaceMesh. 0.04 flattened real tile texels.
	if (tex_color.a < 0.1 || dot(tex_color.rgb, vec3(0.33, 0.33, 0.34)) < 0.002) {
		tex_color = vec4(0.35, 0.42, 0.22, 1.0);
	}
	vec3 ramp_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 ramp_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	ALBEDO = cs_depth(tex_color.rgb * 0.92, ramp_n, ramp_pos, 1.0);
}

void light() {
	float lit = clamp(ATTENUATION, 0.0, 1.0);
	float dark = clamp(terrain_shadow_darken, 0.0, 0.8);
	DIFFUSE_LIGHT += cs_sun_light(lit, dark, NORMAL, LIGHT, LIGHT_IS_DIRECTIONAL);
}
