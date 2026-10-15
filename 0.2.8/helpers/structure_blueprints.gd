class_name StructureBlueprints
extends RefCounted

const _Registry = preload("res://building/building_registry.gd")

const LARGE_STRUCTURES := true

const WALL_SEGMENT := &"wall_segment"
const WALL_CORNER := &"wall_corner"


static func ids() -> Array[StringName]:
	if not LARGE_STRUCTURES:
		return []
	return [WALL_SEGMENT, WALL_CORNER]


static func get_blueprint(id: StringName) -> Dictionary:
	if not LARGE_STRUCTURES:
		return {}
	if id == WALL_SEGMENT:
		return _make(WALL_SEGMENT, 3, 2, 1, _segment_cells())
	if id == WALL_CORNER:
		return _make(WALL_CORNER, 2, 2, 2, _corner_cells())
	return {}


static func _segment_cells() -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for x in 3:
		for y in 2:
			cells.append(Vector3i(x, y, 0))
	return cells


static func _corner_cells() -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for y in 2:
		cells.append(Vector3i(0, y, 0))
		cells.append(Vector3i(1, y, 0))
		cells.append(Vector3i(0, y, 1))
	return cells


static func _make(id: StringName, w: int, h: int, d: int, mask: Array[Vector3i]) -> Dictionary:
	_Registry.ensure_builtins()
	var wall = _Registry.get_def(&"stone_wall")
	var tile := int(wall.tile_id)
	var per := maxi(1, int(wall.material_count))
	var wood_each := maxi(0, int(wall.wood_fallback_count))
	var cells: Array[Dictionary] = []
	for cell in mask:
		cells.append({
			"x": cell.x,
			"y": cell.y,
			"z": cell.z,
			"tile": tile,
		})
	var count := cells.size() * per
	return {
		"id": String(id),
		"footprint": {"w": w, "h": h, "d": d},
		"cells": cells,
		"cost": {
			"id": str(wall.material_id),
			"count": count,
			"wood_fallback": cells.size() * wood_each,
		},
		"recipe": [{
			"id": str(wall.material_id),
			"count": count,
		}],
	}
