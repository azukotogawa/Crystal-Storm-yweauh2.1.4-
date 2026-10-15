class_name CoordMapper

static func get_logical_coord(grid_pos: Vector2i, world_ref: Object, cm: Object) -> Vector3:
	var q = grid_pos.x
	var r = grid_pos.y
	var s = -q - r
	
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

		for n in neighbors:
			if get_height_at(n, world_ref) > current_height:
				return true
	return false
