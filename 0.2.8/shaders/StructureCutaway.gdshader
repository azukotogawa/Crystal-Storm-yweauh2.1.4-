shader_type spatial;

// Same cone as helpers/camera_cutaway.gd and the terrain shaders: screen-door
// rim, keep fragments at or below the feet. Globals are written once per frame
// by player/camera.gd. The mesh casts and this pass receives the sun shadow.
render_mode diffuse_burley, specular_schlick_ggx, depth_draw_opaque;

global uniform float cutaway_enabled;
global uniform vec3 cutaway_player;
global uniform vec3 cutaway_camera;
global uniform float cutaway_radius;
global uniform float cutaway_radius_near;
global uniform float cutaway_feet_clear;
global uniform float cutaway_past;

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float roughness_amount = 0.9;
uniform float metallic_amount = 0.0;
uniform vec3 emission_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform float vertex_color_as_albedo = 0.0;
uniform float alpha_scissor = 0.0;

varying vec4 v_color;


void vertex() {
	v_color = COLOR;
}


void fragment() {
	// Keep in sync with helpers/camera_cutaway.gd (T_MIN 0.05) and ChunkSurfaceMesh.gdshader.
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

	vec4 tex = texture(albedo_texture, UV);
	if (alpha_scissor > 0.001 && tex.a < alpha_scissor) {
		discard;
	}
	vec3 col = tex.rgb * albedo_color.rgb;
	if (vertex_color_as_albedo > 0.5) {
		col *= v_color.rgb;
	}
	ALBEDO = col;
	ROUGHNESS = roughness_amount;
	METALLIC = metallic_amount;
	EMISSION = emission_color * emission_energy;
}
