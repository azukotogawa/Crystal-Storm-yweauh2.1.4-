class_name CoordMapper

# CoordMapper.gd
static func get_logical_coord(grid_pos: Vector2i, world_ref: Object, cm: Object) -> Vector3:
	# Hex axial conversion (using q, r coordinates)
	var q = grid_pos.x
	var r = grid_pos.y
	# Standard hex-to-cube conversion: q + r + s = 0, so s = -q - r
	var s = -q - r
	
	# Return as Vector3 representing (q, s, r) or (q, r, s) depending 
	# on how your system prefers to store the coordinate
	return Vector3(q, r, s)
	
static func get_height_at(pos: Vector2i, world_ref: Object) -> int:
	var b = world_ref.get_biome(pos.x+.5, pos.y+.5)
	return int(b.get("height", 0))

static func is_disregarded(pos: Vector2i, world_ref: Object, chunk: Object) -> bool:
	var current_height = get_height_at(pos, world_ref)
	if chunk != null:
		var angle = chunk.get_angle_index()
		var neighbors = [pos + angle["left_offset"]*-1, pos + angle["right_offset"]*-1, 
		pos + (angle["left_offset"]+angle["right_offset"])*-1]

		# Check if ANY neighbor is lower to flag this as a "shift" tile
		for n in neighbors:
			if get_height_at(n, world_ref) > current_height:
				return true
	return false
