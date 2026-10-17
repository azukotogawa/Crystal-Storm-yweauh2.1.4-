shader_type spatial;

render_mode ambient_light_disabled, specular_disabled, cull_disabled, depth_draw_opaque;

// Cave cutaway. Literals for the rim match helpers/camera_cutaway.gd (T_MIN 0.05).
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

varying vec2 voxel_tiling;
varying flat float face_code;
varying flat float render_this_face;

void vertex() {
    instance_data = INSTANCE_CUSTOM;
    
    voxel_tiling.x = instance_data.a;
    
    face_code = floor(instance_data.b);
    voxel_tiling.y = round((instance_data.b - face_code) * 100.0);

    // This is before any view/model transforms, so directions are pure axis for our
    // scale-only instance transforms. Avoids using view-space NORMAL (which depends on
    // camera angle and was causing all faces to be discarded → white voxels).
    // - No leakage: e.g. a lip box's own top/bottom (Y normals) or ends never render
    //   (prevents "bottom face appearing on a side face").
    vec3 obj_n = normalize(NORMAL);
    float thresh = 0.9;  // strict for pure axis normals after scaling
    int f = int(face_code + 0.1);  // face_code is floor(...) + small frac from uv_h/100
    render_this_face = 0.0;
    if (f == 0) {
        if (obj_n.y > thresh) render_this_face = 1.0;
    } else if (f == 2) {
        if (obj_n.y < -thresh) render_this_face = 1.0;
    } else if (f == 3) {
        if (obj_n.x < -thresh) render_this_face = 1.0;
    } else if (f == 4) {
        if (obj_n.x > thresh) render_this_face = 1.0;
    } else if (f == 5) {
        if (obj_n.z < -thresh) render_this_face = 1.0;
    } else if (f == 6) {
        if (obj_n.z > thresh) render_this_face = 1.0;
    } else if (f == 7 || f == 8 || f == 9) {
        render_this_face = 1.0;
    }
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

    vec2 repeated_uv = UV * voxel_tiling;
    vec4 tex_color = cs_sample_atlas(texture_atlas, atlas_grid, vec2(col, row), repeated_uv);

    if (tex_color.a < 0.1) discard;

    if (render_this_face < 0.5) discard;

    ALBEDO = tex_color.rgb;

    // Face-based pixel-art shading. Do not rely on Lambert for side faces —
    // the iso camera leaves them nearly black under a single key light.
    if (face_code > 0.5 && face_code < 6.5 && face_code != 2.0) {
        ALBEDO *= 0.68;
    }
    if (face_code == 2.0) {
        ALBEDO *= 0.48;
    }
    if (face_code < 0.5) {
        ALBEDO *= 0.96;
    }
    vec3 depth_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec3 depth_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
    ALBEDO = cs_depth(ALBEDO, depth_n, depth_pos, 1.0);
}

void light() {
    float lit = clamp(ATTENUATION, 0.0, 1.0);
    float dark = clamp(terrain_shadow_darken, 0.0, 0.8);
    DIFFUSE_LIGHT += vec3(mix(1.0 - dark, 1.0, lit));
}