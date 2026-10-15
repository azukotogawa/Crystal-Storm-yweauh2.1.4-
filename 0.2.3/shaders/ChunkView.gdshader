shader_type spatial;

render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D texture_atlas : source_color, filter_nearest;	
uniform vec2 atlas_grid = vec2(7.0, 10.0);

varying flat vec4 instance_data;


varying vec2 voxel_tiling;

void vertex() {
    instance_data = INSTANCE_CUSTOM;
    
    float w = instance_data.a;
    
    float face_int = floor(instance_data.b);
    float h = round((instance_data.b - face_int) * 100.0);
    
    voxel_tiling = vec2(w, h);
}


void fragment() {
    float col = floor(instance_data.r * 255.0 + 0.5);
    float row = floor(instance_data.g * 255.0 + 0.5);
    float face = instance_data.b;

    vec2 repeated_uv = fract(UV * voxel_tiling);

    vec2 tile_size = 1.0 / atlas_grid;
    vec2 padding = tile_size / 32.0;

    vec2 local_uv = mix(
        padding,
        tile_size - padding,
        repeated_uv
    );

    if (face > 0.5) {
        local_uv.y = mix(local_uv.y, local_uv.y * 0.9, 1.0);
    }

    vec2 atlas_uv = vec2(col, row) / atlas_grid;
    vec4 tex_color = texture(texture_atlas, atlas_uv + (local_uv * tile_size));

    if (tex_color.a < 0.1) discard;

    ALBEDO = tex_color.rgb;
    
    if (face > 0.5) {
        ALBEDO *= 0.75;
    }
}
