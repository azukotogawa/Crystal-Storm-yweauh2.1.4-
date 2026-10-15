class_name IsoMath


static func grid_to_screen(grid_pos: Vector2) -> Vector2:
	return Vector2(
		(grid_pos.x - grid_pos.y) * 32.0,
		(grid_pos.x + grid_pos.y) * 16.0
	)

static func screen_to_grid(screen_pos: Vector2) -> Vector2:
	var x = (screen_pos.x / 32.0 + screen_pos.y / 16.0) / 2.0
	var y = (screen_pos.y / 16.0 - screen_pos.x / 32.0) / 2.0
	return Vector2(x, y)
