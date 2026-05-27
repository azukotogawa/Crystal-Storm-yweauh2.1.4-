class_name IsoMath

# Assuming a tile size of 64x32
# If your tiles are 64 pixels wide and 32 pixels tall:
static func grid_to_screen(grid_pos: Vector2) -> Vector2:
	# This aligns with Godot's isometric TileSet layout
	return Vector2(
		(grid_pos.x - grid_pos.y) * 32.0,
		(grid_pos.x + grid_pos.y) * 16.0
	)

static func screen_to_grid(screen_pos: Vector2) -> Vector2:
	# Inverse of the above matrix
	var x = (screen_pos.x / 32.0 + screen_pos.y / 16.0) / 2.0
	var y = (screen_pos.y / 16.0 - screen_pos.x / 32.0) / 2.0
	return Vector2(x, y)
