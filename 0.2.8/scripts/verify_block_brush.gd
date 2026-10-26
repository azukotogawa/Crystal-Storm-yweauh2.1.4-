extends SceneTree

const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _Highlight = preload("res://player/target_highlight.gd")
const _GameFeelConfig = preload("res://config/game_feel_config.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")

var failed := false


class FlatWorld:
	extends "res://world/InfiniteNoiseWorld.gd"

	func get_surface_height(wx: float, wz: float) -> float:
		return TerrainEdits.get_height_delta(floori(wx), floori(wz))

	func invalidate_column_cache(_wx: int, _wz: int) -> void:
		pass


func _init() -> void:
	call_deferred("_run")


func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("OK %s" % msg)
	else:
		push_error(msg)
		failed = true


func _run() -> void:
	_shapes()
	_config()
	_outline()
	_planning()
	_micro_off()
	if failed:
		print("FAIL block brush tests")
		quit(1)
		return
	print("All block brush tests OK")
	quit(0)


func _shapes() -> void:
	var want := {
		_ItemTypes.BreakShape.SINGLE: 1,
		_ItemTypes.BreakShape.LINE_3: 3,
		_ItemTypes.BreakShape.PAD_3X3: 9,
		_ItemTypes.BreakShape.SHAFT_1X3: 3,
		_ItemTypes.BreakShape.CUBE_3X3X2: 18,
	}
	for shape in want:
		_expect(_ItemTypes.brush_offsets(shape).size() == int(want[shape]), "brush %s has %d offsets" % [_ItemTypes.brush_id(shape), int(want[shape])])
	_expect(_ItemTypes.BRUSH_ORDER.size() == 5, "five brushes in unlock order")
	_expect(_ItemTypes.brush_wear(1) == 1 and _ItemTypes.brush_wear(9) == 3 and _ItemTypes.brush_wear(18) == 6, "wear grows one per three blocks")


func _config() -> void:
	var cfg = _GameFeelConfig.active()
	_expect(is_equal_approx(cfg.brush_reach, 5.0), "brush reach is 5")
	_expect(cfg.brush_unlock("single") == 0, "single brush is free")
	var last := 0
	var rising := true
	for shape in _ItemTypes.BRUSH_ORDER:
		var need: int = cfg.brush_unlock(_ItemTypes.brush_id(shape))
		if need < last:
			rising = false
		last = need
	_expect(rising, "unlock thresholds never fall")
	_expect(cfg.brush_unlock("nope") > 1000000, "unknown brush never unlocks")
	_expect(is_equal_approx(cfg.brush_extra_sec(1), 0.0), "one block adds no time")
	_expect(cfg.brush_extra_sec(500) <= cfg.brush_time_cap_sec + 0.0001, "extra time is capped")


func _outline() -> void:
	var one: Array = [Vector3i(0, 0, 0)]
	_expect(_Highlight.exposed_faces(one).size() == 6, "one cube exposes six faces")
	var pair: Array = [Vector3i(0, 0, 0), Vector3i(1, 0, 0)]
	_expect(_Highlight.exposed_faces(pair).size() == 10, "shared face between two cubes is hidden")
	var pad: Array = []
	for z in 3:
		for x in 3:
			pad.append(Vector3i(x, 0, z))
	_expect(_Highlight.exposed_faces(pad).size() == 9 + 9 + 12, "flat pad exposes top, bottom, and rim")
	var flat_edges: Array = _Highlight.outline_edges(_Highlight.exposed_faces(pad))
	_expect(flat_edges.size() == 28, "pad outline keeps only silhouette and rim edges")


func _planning() -> void:
	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	var world := FlatWorld.new()
	root.add_child(world)
	var anchor := Vector3i(10, 0, 10)
	var aim := Vector3(0, 0, 1)
	var dig: Array = _TerrainEdits.brush_cells(_ItemTypes.BreakShape.SHAFT_1X3, anchor, aim, world, false)
	var ys := []
	for c in dig:
		ys.append(c.y)
	ys.sort()
	_expect(dig.size() == 3 and ys[2] - ys[0] == 2, "shaft digs three layers down one column")
	var place: Array = _TerrainEdits.brush_cells(_ItemTypes.BreakShape.LINE_3, anchor, aim, world, true)
	var base := _TerrainEdits.surface_block_y(world, 10, 10)
	var all_above := true
	for c in place:
		if c.y != base + 1:
			all_above = false
	_expect(place.size() == 3 and all_above, "line place sits one block above each column surface")
	var clipped := _TerrainEdits.clip_brush_place(place, world, null)
	_expect(clipped.size() == 3, "open ground keeps all three placements")
	var floating: Array[Vector3i] = [Vector3i(10, base + 4, 10)]
	_expect(_TerrainEdits.clip_brush_place(floating, world, null).is_empty(), "placement never floats above the surface")
	var skipped := _TerrainEdits.clip_brush_place(place, world, null, {Vector2i(10, 10): true})
	_expect(skipped.size() == 2, "skipped columns drop out of the plan")
	world.queue_free()
	_TerrainEdits.reset()


func _micro_off() -> void:
	_expect(not _ChunkData.USE_MICRO_BRICKS, "micro bricks are off by default")
	_expect(not _ChunkData.micro_terrain_enabled(), "micro terrain stays off without opt in")
