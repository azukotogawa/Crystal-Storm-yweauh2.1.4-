shader_type canvas_item;
render_mode unshaded;

uniform float top_brightness : hint_range(0.0, 1.0) = 0.85;
uniform float side_darkness : hint_range(0.0, 1.0) = 0.75;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.7;
uniform float height_contrast : hint_range(0.0, 2.0) = 1.3;

void fragment() {
    vec4 color = texture(TEXTURE, UV);
    
    // Per-tile UV
    vec2 tile_uv = fract(UV * vec2(38.0, 8.0));   // adjust second number to your atlas height
    
    // Top face highlight
    float top = 1.0 + (1.0 - tile_uv.y) * top_brightness;
    
    // Side darkness
    float side = 1.0 - (tile_uv.x * side_darkness);
    
    // Ambient Occlusion (darker in corners and lower areas)
    float ao = 1.0 - (tile_uv.x * tile_uv.y * ao_strength);
    
    // Height contrast
    float height = pow(1.0 - tile_uv.y, height_contrast);
    
    vec3 final = color.rgb * top * side * ao * height;
    
    // Sharp blocky grid
    if (fract(UV.x * 38.0) < 0.04 || fract(UV.y * 8.0) < 0.04) {
        final *= 0.88;
    }
    
    COLOR = vec4(final, color.a);
}