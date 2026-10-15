shader_type canvas_item;

uniform float height_multiplier = 16.0;

void vertex() {
    float h = COLOR.r * 255.0;
    
    VERTEX.y -= h * height_multiplier;
}