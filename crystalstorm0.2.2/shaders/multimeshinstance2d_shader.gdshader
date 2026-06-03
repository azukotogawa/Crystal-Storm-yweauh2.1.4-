shader_type canvas_item;

uniform vec2 atlas_grid = vec2(7.0, 10.0);
varying vec4 instance_data;

void vertex() {
	instance_data = INSTANCE_CUSTOM;
}

void fragment() {
	float col = round(instance_data.r * 255.0);
	float row = round(instance_data.g * 255.0);

	// Safe half-pixel padding to stop texel bleeding on the atlas PNG
	vec2 local_uv = clamp(UV, vec2(0.001), vec2(0.999));
	local_uv.y = 1.0 - local_uv.y;
	
	// Fit into its atlas cell
	local_uv /= atlas_grid;
	vec2 atlas_offset = vec2(col, row) / atlas_grid;

	COLOR = texture(TEXTURE, local_uv + atlas_offset);
}
