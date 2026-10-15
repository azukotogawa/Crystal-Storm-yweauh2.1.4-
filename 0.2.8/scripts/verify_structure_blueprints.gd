extends SceneTree

const _Blueprints = preload("res://helpers/structure_blueprints.gd")
const _Registry = preload("res://building/building_registry.gd")
const _Edits = preload("res://world/terrain_edits.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL " + msg)


func _run() -> void:
	_Registry.reset()
	_Registry.ensure_builtins()
	if not _Blueprints.LARGE_STRUCTURES:
		_fail("LARGE_STRUCTURES must default true")
	_test_wall_tiles()
	_test_segment()
	_test_corner()
	_test_unknown()
	if _failed == 0:
		print("All structure blueprint tests OK")
		quit(0)
	else:
		push_error("verify_structure_blueprints: %d failure(s)" % _failed)
		quit(1)


func _test_wall_tiles() -> void:
	var stone = _Registry.get_def(&"stone_wall")
	var wood = _Registry.get_def(&"wood_wall")
	if stone == null or wood == null:
		_fail("stone and wood walls must stay registered")
		return
	var src := (_Edits as GDScript).source_code
	var at := src.find("func build_wall")
	var end := src.find("\nstatic func ", at + 10)
	var body := src.substr(at, maxi(end - at, 0))
	if "ws.build_tile[key] = tile_id" not in body:
		_fail("build_wall must keep storing the passed wall tile")
		return
	if int(stone.tile_id) == int(wood.tile_id):
		_fail("stone and wood walls must keep different tiles")
		return
	print("OK build_wall still stores the stone and wood wall tiles")


func _test_segment() -> void:
	var bp := _Blueprints.get_blueprint(_Blueprints.WALL_SEGMENT)
	if not _expect_box(bp, "wall_segment", 3, 2, 1, 6):
		return
	var stone = _Registry.get_def(&"stone_wall")
	if not _expect_cost(bp, stone, 6):
		return
	print("OK wall segment is 3x2x1 of the stone wall tile")


func _test_corner() -> void:
	var bp := _Blueprints.get_blueprint(_Blueprints.WALL_CORNER)
	if not _expect_box(bp, "wall_corner", 2, 2, 2, 6):
		return
	var seen := {}
	for cell in bp["cells"]:
		seen[Vector3i(int(cell["x"]), int(cell["y"]), int(cell["z"]))] = true
	if seen.has(Vector3i(1, 0, 1)) or seen.has(Vector3i(1, 1, 1)):
		_fail("wall corner must leave the inner column empty")
		return
	if not seen.has(Vector3i(0, 0, 0)) or not seen.has(Vector3i(1, 0, 0)) or not seen.has(Vector3i(0, 0, 1)):
		_fail("wall corner must occupy the L at the bottom")
		return
	var stone = _Registry.get_def(&"stone_wall")
	if not _expect_cost(bp, stone, 6):
		return
	print("OK wall corner is a 2x2x2 L of the stone wall tile")


func _test_unknown() -> void:
	var ids := _Blueprints.ids()
	if ids.size() != 2 or _Blueprints.WALL_SEGMENT not in ids or _Blueprints.WALL_CORNER not in ids:
		_fail("blueprint ids must be the wall segment and the wall corner")
		return
	if not _Blueprints.get_blueprint(&"tower").is_empty():
		_fail("unknown structures must stay empty until they are specified")
		return
	print("OK only the wall segment and wall corner are blueprinted")


func _expect_box(bp: Dictionary, id: String, w: int, h: int, d: int, count: int) -> bool:
	if str(bp.get("id", "")) != id:
		_fail("%s id missing" % id)
		return false
	var foot: Dictionary = bp.get("footprint", {})
	if int(foot.get("w", -1)) != w or int(foot.get("h", -1)) != h or int(foot.get("d", -1)) != d:
		_fail("%s footprint %s is not %dx%dx%d" % [id, foot, w, h, d])
		return false
	var cells: Array = bp.get("cells", [])
	if cells.size() != count:
		_fail("%s has %d cells, want %d" % [id, cells.size(), count])
		return false
	var stone_tile := int(_Registry.get_def(&"stone_wall").tile_id)
	var seen := {}
	for cell in cells:
		var at := Vector3i(int(cell.get("x", -1)), int(cell.get("y", -1)), int(cell.get("z", -1)))
		if at.x < 0 or at.y < 0 or at.z < 0 or at.x >= w or at.y >= h or at.z >= d:
			_fail("%s cell %s is outside the footprint" % [id, at])
			return false
		if seen.has(at):
			_fail("%s repeats %s" % [id, at])
			return false
		seen[at] = true
		if int(cell.get("tile", -1)) != stone_tile:
			_fail("%s cell %s tile is not the stone wall tile" % [id, at])
			return false
	return true


func _expect_cost(bp: Dictionary, wall, occupied: int) -> bool:
	var count := occupied * int(wall.material_count)
	var cost: Dictionary = bp.get("cost", {})
	if str(cost.get("id", "")) != str(wall.material_id) or int(cost.get("count", -1)) != count:
		_fail("%s cost %s is not %d %s" % [bp.get("id", ""), cost, count, wall.material_id])
		return false
	var fallback := occupied * int(wall.wood_fallback_count)
	if int(cost.get("wood_fallback", -1)) != fallback:
		_fail("%s wood fallback %s is not %d" % [bp.get("id", ""), cost, fallback])
		return false
	var recipe: Array = bp.get("recipe", [])
	if recipe.size() != 1:
		_fail("%s recipe must be one stone stack" % bp.get("id", ""))
		return false
	var line: Dictionary = recipe[0]
	if str(line.get("id", "")) != str(wall.material_id) or int(line.get("count", -1)) != count:
		_fail("%s recipe %s does not match the stone cost" % [bp.get("id", ""), line])
		return false
	return true
