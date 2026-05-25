shader_type canvas_item;

uniform bool is_clipped = false;
uniform float clip_threshold_y = 0.0; // The screen-space Y pixel value to cut at

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	
	if (is_clipped) {
		// FRAGCOORD.y is the Y position in screen pixels
		if (FRAGCOORD.y > clip_threshold_y) {
			col.a = 0.0;
		}
	}
	
	COLOR = col;
}