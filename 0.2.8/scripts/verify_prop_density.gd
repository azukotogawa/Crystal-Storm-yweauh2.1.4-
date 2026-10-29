extends SceneTree

const _Props = preload("res://helpers/voxel_prop_builder.gd")
const _Scatter = preload("res://world/prop_scatter.gd")
const _Poi = preload("res://world/poi_scatter.gd")
const _Quality = preload("res://config/performance_quality_config.gd")
const _Features = preload("res://world/feature_registry.gd")
const _FeatureTypes = preload("res://helpers/world_feature_types.gd")
const _Layer = preload("res://world/feature_visual_layer.gd")
const _Registry = preload("res://systems/game_visual_registry.gd")
const _World = preload("res://world/InfiniteNoiseWorld.gd")
const _Voxels = preload("res://helpers/voxel_types.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)
	print("FAIL " + msg)


func _run() -> void:
	_check_budgets()
	_check_scatter(44021, 4, 5)
	_check_scatter(918337, -3, 6)
	_check_kinds_across_chunks(44021)
	_check_feature_blocks(44021, 4, 5)
	_check_water_blocks(44021, 6, 2)
	_check_meshes()
	_check_layer_places(44021, Vector2i(8, 3))
	_check_layer_budget_zero(Vector2i(8, 4))
	if _failed == 0:
		print("All prop density tests OK")
		quit(0)
	else:
		push_error("verify_prop_density: %d failure(s)" % _failed)
		quit(1)


func _check_budgets() -> void:
	var safe: int = int(_Quality.apply_safe_mode().props_per_chunk)
	var low: int = int(_Quality.apply_preset(_Quality.Preset.LOW).props_per_chunk)
	var med: int = int(_Quality.apply_preset(_Quality.Preset.MEDIUM).props_per_chunk)
	var high: int = int(_Quality.apply_preset(_Quality.Preset.HIGH).props_per_chunk)
	var fallback: int = int(_Quality.create_default().props_per_chunk)
	if safe != 0 or low != 4 or med != 12 or high != 24 or fallback != med:
		_fail("prop budgets safe=%d low=%d med=%d high=%d default=%d" % [safe, low, med, high, fallback])
		return
	if not (safe < low and low < med and med < high):
		_fail("prop budgets must rise with the preset")
		return
	print("OK prop budgets safe=%d low=%d med=%d high=%d poi_per_chunk=%d" % [safe, low, med, high, _Poi.CHUNK_BUDGET])


func _check_scatter(seed_value: int, cx: int, cz: int) -> void:
	var budget := 12
	var first: Array[Dictionary] = _Scatter.for_chunk(seed_value, cx, cz, budget, null)
	var again: Array[Dictionary] = _Scatter.for_chunk(seed_value, cx, cz, budget, null)
	if first.size() < 1 and _Scatter._field(seed_value, Vector2i(cx * 16 + 8, cz * 16 + 8)) >= _Scatter.CLEARING_BELOW:
		_fail("chunk %d,%d seed %d placed %d, want at least 1 outside a clearing" % [cx, cz, seed_value, first.size()])
		return
	if first.size() > budget:
		_fail("chunk exceeded budget %d" % budget)
		return
	if _signature(first) != _signature(again):
		_fail("scatter is not deterministic")
		return
	var seen: Dictionary = {}
	for i in first.size():
		var spot: Dictionary = first[i]
		var cell: Vector2i = spot.get("cell", Vector2i.ZERO)
		var kind := str(spot.get("kind", ""))
		if kind not in _Scatter.KINDS:
			_fail("unknown prop kind %s" % kind)
			return
		if seen.has(cell):
			_fail("duplicate prop cell %s" % cell)
			return
		seen[cell] = true
		var expect := Vector2i(floori(float(cell.x) / float(ChunkData.SIZE)), floori(float(cell.y) / float(ChunkData.SIZE)))
		if expect != Vector2i(cx, cz):
			_fail("prop %s left chunk %d,%d" % [cell, cx, cz])
			return
		for j in i:
			var other: Vector2i = first[j].get("cell", Vector2i.ZERO)
			if Vector2(cell).distance_to(Vector2(other)) < float(_Scatter.MIN_SPACING):
				_fail("spacing %s to %s under %d" % [cell, other, _Scatter.MIN_SPACING])
				return
	print("OK prop scatter seed=%d chunk=%d,%d count=%d" % [seed_value, cx, cz, first.size()])


func _check_kinds_across_chunks(seed_value: int) -> void:
	var kinds: Dictionary = {}
	var total := 0
	for cz in range(2, 6):
		for cx in range(2, 6):
			var spots: Array[Dictionary] = _Scatter.for_chunk(seed_value, cx, cz, 12, null)
			total += spots.size()
			for spot in spots:
				kinds[str(spot.get("kind", ""))] = true
	for kind in _Scatter.BIOME_WEIGHTS["plains"].keys():
		if not kinds.has(kind):
			_fail("region missed prop kind %s" % kind)
			return
	print("OK prop kinds over 16 chunks count=%d kinds=%d (was 0 props/chunk)" % [total, kinds.size()])


func _check_feature_blocks(seed_value: int, cx: int, cz: int) -> void:
	var open_spots: Array[Dictionary] = _Scatter.for_chunk(seed_value, cx, cz, 12, null)
	if open_spots.is_empty():
		_fail("feature block had no open prop")
		return
	var cell: Vector2i = open_spots[0].get("cell", Vector2i.ZERO)
	_Features.register_feature(cell.x, cell.y, _FeatureTypes.FeatureKind.RUIN, {"center": cell, "name": "prop-block"})
	var blocked: Array[Dictionary] = _Scatter.for_chunk(seed_value, cx, cz, 12, null)
	_Features.clear_feature(cell.x, cell.y)
	for spot in blocked:
		if spot.get("cell", Vector2i.ZERO) == cell:
			_fail("prop stayed on feature cell %s" % cell)
			return
	print("OK prop skips feature cell %s" % cell)


func _check_water_blocks(seed_value: int, cx: int, cz: int) -> void:
	var world = _World.new(seed_value)
	var dry: Array[Dictionary] = _Scatter.for_chunk(seed_value, cx, cz, 12, world)
	if dry.is_empty():
		_fail("water check found no dry prop")
		return
	var cell: Vector2i = dry[0].get("cell", Vector2i.ZERO)
	_Features.set_tile_override(cell.x, cell.y, _Voxels.WATER)
	var wet: Array[Dictionary] = _Scatter.for_chunk(seed_value, cx, cz, 12, world)
	_Features.clear_tile_override(cell.x, cell.y)
	for spot in wet:
		if spot.get("cell", Vector2i.ZERO) == cell:
			_fail("prop stayed on water cell %s" % cell)
			return
	print("OK prop skips water cell %s" % cell)


func _check_meshes() -> void:
	for kind in _Scatter.KINDS:
		var node := _Props.build_scatter_prop(kind)
		var meshes := 0
		var wide := 0.0
		for child in node.get_children():
			if child is MeshInstance3D and (child as MeshInstance3D).mesh is BoxMesh:
				meshes += 1
				wide = maxf(wide, ((child as MeshInstance3D).mesh as BoxMesh).size.x)
		if meshes < 2:
			_fail("%s prop has %d boxes" % [kind, meshes])
			return
		if _Props.model_height(node) <= 0.0:
			_fail("%s prop has no height" % kind)
			return
		if kind == "fence" and wide < _Props.model_height(node):
			_fail("fence should read wider than it is tall")
			return
		node.free()
	print("OK prop meshes %s" % str(_Scatter.KINDS))


func _check_layer_places(seed_value: int, coord: Vector2i) -> void:
	var world = _World.new(seed_value)
	var layer = _Layer.new()
	root.add_child(layer)
	var veg := Node3D.new()
	layer.add_child(veg)
	layer._vegetation_root = veg
	layer.world = world
	var reg = _Registry.new()
	reg.max_feature_billboards_per_chunk = 48
	layer._registry = reg
	_set_live_prop_budget(12)
	layer._props_per_chunk = 12
	layer._populate_chunk(coord)
	var want: Array[Dictionary] = _Scatter.for_chunk(seed_value, coord.x, coord.y, 12, world)
	var got := 0
	var kinds: Dictionary = {}
	for child in veg.get_children():
		if child.is_in_group("scatter_prop"):
			got += 1
			kinds[str(child.get_meta("prop_kind", ""))] = true
	if got != want.size() or got < 1:
		_fail("layer placed %d props, scatter wanted %d" % [got, want.size()])
		return
	for spot in want:
		var kind := str(spot.get("kind", ""))
		if not kinds.has(kind):
			_fail("layer missed placed kind %s" % kind)
			return
	print("OK feature layer props=%d chunk=%s" % [got, coord])
	layer.queue_free()


func _check_layer_budget_zero(coord: Vector2i) -> void:
	var layer = _Layer.new()
	root.add_child(layer)
	var veg := Node3D.new()
	layer.add_child(veg)
	layer._vegetation_root = veg
	var reg = _Registry.new()
	reg.max_feature_billboards_per_chunk = 48
	layer._registry = reg
	_set_live_prop_budget(0)
	layer._props_per_chunk = 0
	layer._populate_chunk(coord)
	var got := 0
	for child in veg.get_children():
		if child.is_in_group("scatter_prop"):
			got += 1
	if got != 0:
		_fail("zero budget still placed %d props" % got)
		return
	print("OK zero prop budget places nothing")
	layer.queue_free()


func _set_live_prop_budget(budget: int) -> void:
	var perf = get_first_node_in_group("performance_service")
	if perf != null and "quality" in perf and perf.quality != null and "props_per_chunk" in perf.quality:
		perf.quality.props_per_chunk = budget


func _signature(spots: Array[Dictionary]) -> String:
	var parts: PackedStringArray = []
	for spot in spots:
		var cell: Vector2i = spot.get("cell", Vector2i.ZERO)
		parts.append("%s:%s:%d" % [cell, str(spot.get("kind", "")), int(spot.get("yaw", 0))])
	return "|".join(parts)
