// wall_mask.gdshader
shader_type canvas_item;

// Pass the tile height from the shader parameter or vertex attributes
uniform float height_offset = 16.0; 

void vertex() {
    // Look at your height data and displace the Y coordinate
    // This happens entirely on the GPU
    VERTEX.y -= height * height_offset;
}