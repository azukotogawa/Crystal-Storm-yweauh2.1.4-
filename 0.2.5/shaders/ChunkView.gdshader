shader_type spatial;

render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D texture_atlas : source_color, filter_nearest;	
uniform vec2 atlas_grid = vec2(7.0, 10.0);

varying flat vec4 instance_data;

// Update these lines inside your shader file's vertex() processor block
varying vec2 voxel_tiling;
varying flat float face_code;
varying flat float render_this_face;

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
    } else if (f == 7 || f == 8) { // RAMP / corner ramp — render all wedge faces
        render_this_face = 1.0;
        // Nudge ramps slightly above coplanar terrain tops to avoid seam z-fighting.
        VERTEX.y += 0.003;
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
    
    // Add lighting contrast variation to distinguish flat surfaces
    if (face_code > 0.5 && face_code < 6.5 && face_code != 2.0) { // Sides only (not ramp=7)
        ALBEDO *= 0.75;
    }
    
    // Darken bottom faces slightly
    if (face_code == 2.0) { // FACE_BOTTOM
        ALBEDO *= 0.6;
    }
}