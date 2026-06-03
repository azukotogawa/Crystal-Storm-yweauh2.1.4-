# HexHelpers.gd
class_name HexHelpers

# Axial to Pixel (pointy-top)
static func axial_to_pixel(q: int, r: int, size: float = 64.0) -> Vector2:
	var x = size * (3.0 / 2.0 * q)
	var y = size * (sqrt(3) / 2.0 * q + sqrt(3) * r)
	return Vector2(x, y)

# Simple round for axial
static func round_axial(q: float, r: float) -> Vector2i:
	var cube_x = q
	var cube_z = r
	var cube_y = -cube_x - cube_z
	
	var rx = round(cube_x)
	var ry = round(cube_y)
	var rz = round(cube_z)
	
	var x_diff = abs(rx - cube_x)
	var y_diff = abs(ry - cube_y)
	var z_diff = abs(rz - cube_z)
	
	if x_diff > y_diff and x_diff > z_diff:
		rx = -ry - rz
	elif y_diff > z_diff:
		ry = -rx - rz
	else:
		rz = -rx - ry
	
	return Vector2i(int(rx), int(rz))
