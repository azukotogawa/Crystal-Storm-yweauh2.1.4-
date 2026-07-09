shader_type spatial;

render_mode cull_disabled, depth_draw_opaque, unshaded;

uniform sampler2D texture_atlas : source_color, filter_nearest;	
uniform vec2 atlas_grid = vec2(7.0, 10.0);

varying flat vec4 instance_data;

// Update these lines inside your shader file's vertex() processor block
varying vec2 voxel_tiling;
varying flat float face_code;
varying flat float render_this_face;
varying vec3 primitive_obj_normal;

void vertex() {
    instance_data = INSTANCE_CUSTOM;
    // Mesh-local normals for all primitives (ramps, corners, concave). Concave orientation is
    // handled by the instance basis; per-face shading uses authored local normals.
    primitive_obj_normal = normalize(NORMAL);
    
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
    float thresh = 0.7;  // axis normals after non-uniform instance scale
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
    } else if (f == 7 || f == 8 || f == 9) { // RAMP / corner / concave primitives — all faces (fills + slopes)
        render_this_face = 1.0;
    }
}


void fragment() {
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

    ALBEDO = tex_color.rgb;

    // Face-based pixel-art shading layered under scene lighting.
    int f_shade = int(face_code + 0.1);
    if (f_shade == 9) {
        // Concave diagonal prism: top/bottom/diagonal/vertical walls (not walkable slopes).
        vec3 n = normalize(primitive_obj_normal);
        float ax = abs(n.x);
        float ay = abs(n.y);
        float az = abs(n.z);
        if (ay > 0.85) {
            ALBEDO *= (n.y > 0.0) ? 0.96 : 0.48;
        } else if (ax > 0.85 || az > 0.85) {
            ALBEDO *= 0.68;
        } else if (ax > 0.3 && az > 0.3) {
            ALBEDO *= 0.85;
        } else {
            ALBEDO *= 0.68;
        }
    } else if (f_shade == 7 || f_shade == 8) {
        // Walkable slopes tilt upward (n.y ~0.7); keep them as bright as flat tops.
        vec3 n = normalize(primitive_obj_normal);
        float ax = abs(n.x);
        float ay = abs(n.y);
        float az = abs(n.z);
        if (n.y > 0.45) {
            ALBEDO *= 0.96;
        } else if (n.y < -0.45) {
            ALBEDO *= 0.48;
        } else if (ax > 0.85 || az > 0.85) {
            ALBEDO *= 0.68;
        } else {
            ALBEDO *= 0.85;
        }
    } else if (face_code > 0.5 && face_code < 6.5 && face_code != 2.0) {
        ALBEDO *= 0.68;
    } else if (face_code == 2.0) {
        ALBEDO *= 0.48;
    } else if (face_code < 0.5) {
        ALBEDO *= 0.96;
    }
}