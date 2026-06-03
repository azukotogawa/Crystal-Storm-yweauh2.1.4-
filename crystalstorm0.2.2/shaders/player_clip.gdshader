shader_type canvas_item;

uniform float height_multiplier = 16.0;

void vertex() {
    // COLOR is the per-cell modulate color we set in GDScript
    float h = COLOR.r * 255.0;
    
    // Displace the Y coordinate on the GPU
    VERTEX.y -= h * height_multiplier;
}