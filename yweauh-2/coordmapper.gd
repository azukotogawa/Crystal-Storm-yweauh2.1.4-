class_name CoordMapper

# CoordMapper.gd
static func get_logical_coord(grid_pos: Vector2i, world_ref: Object, cm: Object) -> Vector2:
	var drift = cm.get_drift_at(grid_pos)
	var height = float(get_render_height_at(grid_pos, world_ref))
	var chunk = cm.get_chunk_at(grid_pos)

	if is_disregarded(grid_pos, world_ref):
		return Vector2i(0,0)
	
	var view_offset = Vector2.ZERO
	if chunk:
	# Scale by 0.25 to prevent jumping by full tile units
		var raw_offset = Vector2(0 + 1, 
		0 + 1)
		view_offset = raw_offset * height

	# Cast to float for precision, then round or snap as needed for UI
	var logical_x = float(grid_pos.x) + view_offset.x
	var logical_y = float(grid_pos.y) + view_offset.y

	return Vector2(logical_x, logical_y)
	
static func get_render_height_at(pos: Vector2i, world_ref: Object) -> int:
	var b = world_ref.get_biome(pos.x, pos.y)
	return int(b.get("render_height", 0))

static func is_disregarded(pos: Vector2i, world_ref: Object) -> bool:
	var current_height = get_render_height_at(pos, world_ref)
	var neighbors = [pos + Vector2i(0, 1), pos + Vector2i(0, -1), 
	pos + Vector2i(1, 0), pos + Vector2i(-1, 0), pos + Vector2i(-1, -1)]

	# Check if ANY neighbor is lower to flag this as a "shift" tile
	for n in neighbors:
		if get_render_height_at(n, world_ref) > current_height:
			return true
	return false
