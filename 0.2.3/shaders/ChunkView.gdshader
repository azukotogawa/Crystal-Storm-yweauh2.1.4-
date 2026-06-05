shader_type spatial;

render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D texture_atlas : source_color, filter_nearest;	
uniform vec2 atlas_grid = vec2(7.0, 10.0);

varying flat vec4 instance_data;

void vertex() {
    instance_data = INSTANCE_CUSTOM;
}

void fragment() {
    float col = floor(instance_data.r * 255.0 + 0.5);
    float row = floor(instance_data.g * 255.0 + 0.5);
    float face = instance_data.b; // 0 = top, 1 = side

    vec2 atlas_uv = vec2(col, row) / atlas_grid;

    // local UV inside tile
    vec2 local_uv = UV;
	vec2 tile_size = 1.0 / atlas_grid;

	vec2 padding = tile_size / 32.0;

	local_uv = mix(
		padding,
		vec2(1.0) - padding,
		UV
	);

    // optional: slight UV tweak per face (helps avoid seam issues)
    if (face > 0.5) {
        // side faces can be vertically biased or darkened
        local_uv.y = mix(local_uv.y, local_uv.y * 0.9, 1.0);
    }

    vec4 tex_color = texture(texture_atlas, atlas_uv + local_uv / atlas_grid);

    if (tex_color.a < 0.1) discard;

    ALBEDO = tex_color.rgb;
}