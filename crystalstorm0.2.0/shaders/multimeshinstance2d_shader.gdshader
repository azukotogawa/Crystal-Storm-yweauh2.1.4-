shader_type canvas_item;

uniform vec2 atlas_grid = vec2(7.0, 10.0);

varying vec4 instance_data;

void vertex()
{
	instance_data = INSTANCE_CUSTOM;
}

void fragment()
{
	float col = round(instance_data.r * 255.0);
	float row = round(instance_data.g * 255.0);
	float quad_w = instance_data.b * 255.0;
	float quad_h = instance_data.a * 255.0;

	vec2 uv = UV;
	uv.y = 1.0 - uv.y;


	uv.x *= quad_w;
	uv.y *= quad_h;

	uv = fract(uv);
	
	uv /= atlas_grid;
	uv += vec2(col, row) / atlas_grid;

	COLOR = texture(TEXTURE, uv);
}