shader_type canvas_item;

uniform bool is_clipped = false;
uniform float clip_threshold_y = 0.0; // The screen-relative height cutoff pixel line

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	
	if (is_clipped) {
		// Calculate the pixel height across global screen axes.
		// This guarantees that the clipping edge stays flat with the environment tiles.
		float current_pixel_y = SCREEN_UV.y / SCREEN_PIXEL_SIZE.y;
		
		// Truncate everything behind the wall edge line
		if (current_pixel_y > clip_threshold_y) {
			col.a = 0.0;
		}
	}
	
	COLOR = col;
}