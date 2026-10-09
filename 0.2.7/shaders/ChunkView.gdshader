shader_type spatial;

render_mode unshaded, cull_disabled, depth_draw_opaque;

// Cave cutaway. Literals for the rim match helpers/camera_cutaway.gd (T_MIN 0.05).
// Fragments at or below the body stay, so feet, ramps, and water lids are kept.
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

// Update these lines inside your shader file's vertex() processor block
varying vec2 voxel_tiling;
varying flat float face_code;
varying flat float render_this_face;
varying vec3 shade_normal;
varying float vertex_ao;

void vertex() {
    instance_data = INSTANCE_CUSTOM;
    
    // Unpack uv_w directly from Alpha channel (width for UV tiling)
    voxel_tiling.x = instance_data.a;
    
    // Unpack face_code from the integer part of the Blue channel
    face_code = floor(instance_data.b);
    // Unpack uv_h from the fractional part of the Blue channel (height for UV tiling)
    voxel_tiling.y = round((instance_data.b - face_code) * 100.0);

    // Use the raw object-space mesh NORMAL (from BoxMesh attribute) to decide the face.
    // This is before any view/model transforms, so directions are pure axis for our
    // scale-only instance transforms. Avoids using view-space NORMAL (which depends on
    // camera angle and was causing all faces to be discarded → white voxels).
    // We use exact integer face codes + strict axis threshold so that:
    // - Only the intended face of each box instance is kept (top/bottom of surface slabs,
    //   outer vertical of side lips).
    // - No leakage: e.g. a lip box's own top/bottom (Y normals) or ends never render
    //   (prevents "bottom face appearing on a side face").
    // - Bottoms (face 2) and sides (3-6) are correctly distinguished for darkening.
    vec3 obj_n = normalize(NORMAL);
    float thresh = 0.9;  // strict for pure axis normals after scaling
    int f = int(face_code + 0.1);  // face_code is floor(...) + small frac from uv_h/100
    render_this_face = 0.0;
    if (f == 0) { // TOP
        if (obj_n.y > thresh) render_this_face = 1.0;
    } else if (f == 2) { // BOTTOM
        if (obj_n.y < -thresh) render_this_face = 1.0;
    } else if (f == 3) { // NEG_X
        if (obj_n.x < -thresh) render_this_face = 1.0;
    } else if (f == 4) { // POS_X
        if (obj_n.x > thresh) render_this_face = 1.0;
    } else if (f == 5) { // NEG_Z
        if (obj_n.z < -thresh) render_this_face = 1.0;
    } else if (f == 6) { // POS_Z
        if (obj_n.z > thresh) render_this_face = 1.0;
    } else if (f == 7 || f == 8 || f == 9) { // RAMP / corner / side diagonal
        render_this_face = 1.0;
    }
    vec3 nrm = NORMAL;
    shade_normal = dot(nrm, nrm) > 0.001 ? normalize(nrm) : vec3(0.0, 1.0, 0.0);
    vertex_ao = 1.0;
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

    // Force texture coordinates to loop per individual voxel step block instead of stretching
    vec2 repeated_uv = fract(UV * voxel_tiling);

    vec2 tile_size = 1.0 / atlas_grid;
    
    // CHANGED: Wrapped padding in a vec2 so the mix() math works correctly
    vec2 padding = vec2(1.0 / 32.0);  

    // Apply your pixel padding rule inside the specific tile segment limits
    vec2 local_uv = mix(
        padding,
        vec2(1.0) - padding, // CHANGED: Changed 1.0 to vec2(1.0) to match types
        repeated_uv
    );
    
    // Map into absolute texture coordinates on the layout sheet
    vec2 atlas_uv = vec2(col, row) / atlas_grid;
    vec4 tex_color = texture(texture_atlas, atlas_uv + (local_uv * tile_size));

    if (tex_color.a < 0.1) discard;

    // Only render the specific face this instance is meant for.
    // Uses the flag computed in vertex from object-space NORMAL (reliable axis directions).
    if (render_this_face < 0.5) discard;

    vec3 lit_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float crystal = cs_crystal_cell(vec2(col, row));
    ALBEDO = cs_finish(tex_color.rgb, shade_normal, repeated_uv, lit_pos, vertex_ao, crystal);
}