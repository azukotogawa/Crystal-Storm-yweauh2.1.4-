class_name CoordMapper

# CoordMapper.gd
static func get_logical_coord(grid_pos: Vector2i, world_ref: Object, cm: Object) -> Vector3:
	var drift = cm.get_drift_at(grid_pos)
	var height = float(get_height_at(grid_pos, world_ref))
	var chunk = cm.get_chunk_at(grid_pos)

	if is_disregarded(grid_pos, world_ref, chunk):
		return Vector3(0,0,0)
	
	var view_offset = Vector2i.ZERO
	if chunk != null:
		var angle = chunk.get_angle_index()
	# Scale by 0.25 to prevent jumping by full tile units
		var raw_offset = Vector2i(1, 
		1)
		view_offset = raw_offset * height

	# Cast to float for precision, then round or snap as needed for UI
	var logical_x = float(grid_pos.x) + view_offset.x
	var logical_y = float(grid_pos.y) + view_offset.y

	return Vector3(logical_x, logical_y, height)
	
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
