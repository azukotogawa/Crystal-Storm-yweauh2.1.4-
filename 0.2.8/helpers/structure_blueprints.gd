class_name StructureBlueprints
extends RefCounted

const _Registry = preload("res://building/building_registry.gd")

const LARGE_STRUCTURES := true

const WALL_SEGMENT := &"wall_segment"
const WALL_CORNER := &"wall_corner"
const GATE := &"gate"
const STAIRS := &"stairs"
const SMALL_TOWER := &"small_tower"


static func ids() -> Array[StringName]:
	if not LARGE_STRUCTURES:
		return []
	return [WALL_SEGMENT, WALL_CORNER, GATE, STAIRS, SMALL_TOWER]


static func get_blueprint(id: StringName) -> Dictionary:
	if not LARGE_STRUCTURES:
		return {}
	if id == WALL_SEGMENT:
		return _make(WALL_SEGMENT, 3, 2, 1, _segment_cells(), "stone_wall")
	if id == WALL_CORNER:
		return _make(WALL_CORNER, 2, 2, 2, _corner_cells(), "stone_wall")
	if id == GATE:
		return _gate()
	if id == STAIRS:
		return _make(STAIRS, 3, 3, 1, _stair_cells(), "stairs")
	if id == SMALL_TOWER:
		return _make(SMALL_TOWER, 2, 3, 2, _tower_cells(), "small_tower")
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


static func _stair_cells() -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for x in 3:
		for y in x + 1:
			cells.append(Vector3i(x, y, 0))
	return cells


static func _tower_cells() -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for x in 2:
		for z in 2:
			for y in 3:
				cells.append(Vector3i(x, y, z))
	return cells


static func _gate() -> Dictionary:
	var posts: Array[Vector3i] = []
	for y in 2:
		posts.append(Vector3i(0, y, 0))
		posts.append(Vector3i(2, y, 0))
	var bp := _make(GATE, 3, 2, 1, posts, "stone_wall")
	var gate = _Registry.get_def(&"gate")
	bp["passages"] = [{
		"x": 1,
		"y": 0,
		"z": 0,
		"tile": int(gate.tile_id),
		"build": "gate",
		"role": "passage",
	}]
	var recipe: Array = bp.get("recipe", [])
	recipe.append({
		"id": str(gate.material_id),
		"count": maxi(1, int(gate.material_count)),
	})
	bp["recipe"] = recipe
	return bp


static func _make(id: StringName, w: int, h: int, d: int, mask: Array[Vector3i], build_id: String) -> Dictionary:
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
			"build": build_id,
			"role": "wall",
		})
	var count := cells.size() * per
	return {
		"id": String(id),
		"footprint": {"w": w, "h": h, "d": d},
		"cells": cells,
		"passages": [],
		"build_id": build_id,
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
