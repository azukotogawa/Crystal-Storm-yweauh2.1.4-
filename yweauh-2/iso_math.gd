class_name IsoMath

# Assuming a tile size of 64x32
# If your tiles are 64 pixels wide and 32 pixels tall:

#Change Vector2i to Vector2 to support floating point positions
#Uses given isometric grid coordinate, IE (0,1), to find the x/y screen coordinates
#Isometric grid means that the normal compass cardinals are rotated 45 degrees. 
	#Visualy this means, if north to the viewer is the top center of the screen, that the grid's x coordinate increases positively toward the southeast and y toward the southwest
#Is primarily used to draw tiles in the right places. The isometric grid math is done so that the 0, 0 pixel point of each tile sprite is the top center rather than the top left
	#For us that means making sure that the tile sprite origins are the top center
static func grid_to_screen(grid_pos: Vector2) -> Vector2:
	# This aligns with Godot's isometric TileSet layout
	return Vector2(
		(grid_pos.x - grid_pos.y) * 32.0,
		(grid_pos.x + grid_pos.y) * 16.0
	)

#Uses screen coordinates to find the appropriate isometric grid tile underneath them
static func screen_to_grid(screen_pos: Vector2) -> Vector2:
	# Inverse of the above matrix
	var x = (screen_pos.x / 32.0 + screen_pos.y / 16.0) / 2.0
	var y = (screen_pos.y / 16.0 - screen_pos.x / 32.0) / 2.0
	return Vector2(x, y)
