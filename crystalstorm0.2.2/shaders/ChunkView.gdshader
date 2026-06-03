shader_type spatial;

// FIXED RENDER MODES: Changed 'depth_draw_opaque' to 'depth_draw_never'.
// Turning off depth tracking completely stops the invisible outer corners of your cards 
// from leaving hidden punch-holes, passing all layer order over to your sorting_offsets!
render_mode depth_draw_never, cull_disabled, unshaded;

uniform sampler2D texture_atlas : source_color, hint_default_black, filter_nearest;
uniform vec2 atlas_grid = vec2(7.0, 10.0);

varying vec4 instance_data;

void vertex() {
	instance_data = INSTANCE_CUSTOM;
}

void fragment() {
	float col = round(instance_data.r * 255.0);
	float row = round(instance_data.g * 255.0);

	vec2 local_uv = clamp(UV, vec2(0.001), vec2(0.999));
	local_uv /= atlas_grid;
	vec2 atlas_offset = vec2(col, row) / atlas_grid;

	vec4 tex_color = texture(texture_atlas, local_uv + atlas_offset);
	
	if (tex_color.a < 0.1) {
		discard;
	}

	ALBEDO = tex_color.rgb;
}
