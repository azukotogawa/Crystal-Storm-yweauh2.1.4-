class_name IsoMath

# Change Vector2i to Vector2 to support floating point positions
static func grid_to_screen(grid_pos: Vector2) -> Vector2:
	return Vector2(
	(grid_pos.x - grid_pos.y) * 32.0,
	(grid_pos.x + grid_pos.y) * 16.0
	)

func grid_to_screen2(raw_pos: Vector2) -> Vector2:
	# Use the raw float coordinates directly to preserve sub-tile movement
	var screen_x = (raw_pos.x - raw_pos.y) * 32.0
	var screen_y = (raw_pos.x + raw_pos.y) * 16.0
	return Vector2(screen_x, screen_y)

# Convert screen position (pixels) to grid coordinates (floats)
# Use this in your debug_panel.gd and main.gd for sampling
static func screen_to_grid(screen_pos: Vector2) -> Vector2:
	var x = (screen_pos.x / 32.0 + screen_pos.y / 16.0) / 2.0
	var y = (screen_pos.y / 16.0 - screen_pos.x / 32.0) / 2.0
	return Vector2(x, y)
