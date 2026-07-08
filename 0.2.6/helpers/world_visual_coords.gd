class_name WorldVisualCoords
extends RefCounted

const _WorldSettings = preload("res://config/world_settings.gd")


static func column_to_world_pos(column_x: float, world_y: float, column_z: float) -> Vector3:
	var ws = _WorldSettings.get_active()
	return Vector3(
		ws.column_to_world(column_x),
		world_y,
		ws.column_to_world(column_z)
	)


static func cell_center(column_x: int, world_y: float, column_z: int) -> Vector3:
	return column_to_world_pos(float(column_x) + 0.5, world_y, float(column_z) + 0.5)