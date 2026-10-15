shader_type spatial;

render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D texture_atlas : source_color, filter_nearest;	
uniform vec2 atlas_grid = vec2(7.0, 10.0);

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
    }
}


void fragment() {
    float col = floor(instance_data.r * 255.0 + 0.5);
    float row = floor(instance_data.g * 255.0 + 0.5);

    vec2 repeated_uv = fract(UV * voxel_tiling);

    vec2 tile_size = 1.0 / atlas_grid;
    
    vec2 padding = vec2(1.0 / 32.0);  

    vec2 local_uv = mix(
        padding,
        vec2(1.0) - padding,
        repeated_uv
    );
    
    vec2 atlas_uv = vec2(col, row) / atlas_grid;
    vec4 tex_color = texture(texture_atlas, atlas_uv + (local_uv * tile_size));

    if (tex_color.a < 0.1) discard;

    if (render_this_face < 0.5) discard;

    ALBEDO = tex_color.rgb;
    
    if (face_code > 0.5 && face_code != 2.0) {
        ALBEDO *= 0.75;
    }
    
    if (face_code == 2.0) {
        ALBEDO *= 0.6;
    }
}