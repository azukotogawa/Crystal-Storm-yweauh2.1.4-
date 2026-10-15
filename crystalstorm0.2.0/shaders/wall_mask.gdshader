shader_type canvas_item;

uniform float height_offset = 16.0; 

void vertex() {
    VERTEX.y -= height * height_offset;
}