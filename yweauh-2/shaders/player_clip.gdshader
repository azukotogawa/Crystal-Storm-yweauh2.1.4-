shader_type canvas_item;

uniform bool is_clipped = false;
uniform float clip_threshold_y = 0.0;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	
	if (is_clipped) {
		float current_pixel_y = FRAGCOORD.y;
		
		// Only clip pixels above the wall's peak
		if (current_pixel_y < clip_threshold_y) {
			col.a = 0.0;
		}
	}
	
	COLOR = col;
}