extends SceneTree

const _Marks = preload("res://world/distant_landmarks.gd")
const _Props = preload("res://world/prop_scatter.gd")
const _Poi = preload("res://world/poi_scatter.gd")
const _Features = preload("res://world/feature_registry.gd")
const _FeatureTypes = preload("res://helpers/world_feature_types.gd")
const _WorldState = preload("res://world/world_state.gd")
const _World = preload("res://world/InfiniteNoiseWorld.gd")
const _Layer = preload("res://world/feature_visual_layer.gd")
const _Registry = preload("res://systems/game_visual_registry.gd")
const _Voxels = preload("res://helpers/voxel_types.gd")

const SEED := 44021
const PROP_BUDGET := 12
const MEASURE_PATH := "D:/ARCHIVE/CrystalStorm/verify-evidence/pivot-0.4/density/MEASURE.txt"

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)
	print("FAIL " + msg)


func _run() -> void:
	_check_heights()
	_check_scatter(SEED)
	_check_flag_off()
	_check_skips_feature()
	_check_place_dry(SEED)
	_measure(SEED)
	_check_prop_skips_landmark(SEED)
	_check_layer(SEED)
	_WorldState.replace_active()
	if _failed == 0:
		print("All distant landmark tests OK")
		quit(0)
	else:
		push_error("verify_distant_landmarks: %d failure(s)" % _failed)
		quit(1)


func _check_heights() -> void:
	for kind in _Marks.KINDS:
		var node := _Marks.build_visual(kind)
		var height := _Marks.model_height(node)
		var wide := 0.0
		for child in node.get_children():
			if child is MeshInstance3D and (child as MeshInstance3D).mesh is BoxMesh:
				var box := (child as MeshInstance3D).mesh as BoxMesh
				wide = maxf(wide, maxf(box.size.x, box.size.z))
		if height < _Marks.MIN_HEIGHT or height < _Marks.READ_VIEW * 0.5:
			_fail("%s height %.2f is under half of ortho %.0f" % [kind, height, _Marks.READ_VIEW])
			node.free()
			return
		if wide >= height * 0.4:
			_fail("%s reads wide (%.2f) for its height %.2f" % [kind, wide, height])
			node.free()
			return
		if kind == "crystal_glow" and _Marks.glow_energy(node) < 2.0:
			_fail("crystal glow energy %.2f is too dim at ortho 16" % _Marks.glow_energy(node))
			node.free()
			return
		if kind != "crystal_glow" and _Marks.glow_energy(node) > 0.0:
			_fail("%s should not glow" % kind)
			node.free()
			return
		node.free()
	print("OK landmark heights clear half of ortho %.0f" % _Marks.READ_VIEW)


func _check_scatter(seed_value: int) -> void:
	var first: Array[Dictionary] = _Marks.scatter(seed_value)
	var again: Array[Dictionary] = _Marks.scatter(seed_value)
	if first.is_empty():
		_fail("scatter placed nothing")
		return
	if _signature(first) != _signature(again):
		_fail("scatter is not deterministic")
		return
	var kinds: Dictionary = {}
	var per_chunk: Dictionary = {}
	for i in first.size():
		var spot: Dictionary = first[i]
		var center: Vector2i = spot.get("center", Vector2i.ZERO)
		var kind := str(spot.get("poi_kind", ""))
		if kind not in _Marks.KINDS:
			_fail("unknown landmark %s" % kind)
			return
		kinds[kind] = true
		var chunk: Vector2i = spot.get("chunk", Vector2i.ZERO)
		if per_chunk.has(chunk):
			_fail("chunk %s has two landmarks" % chunk)
			return
		per_chunk[chunk] = true
		if Vector2(center).length() < _Marks.ORIGIN_CLEAR:
			_fail("landmark inside origin clear %s" % center)
			return
		for j in i:
			var other: Vector2i = first[j].get("center", Vector2i.ZERO)
			if Vector2(center).distance_to(Vector2(other)) < float(_Marks.MIN_SPACING):
				_fail("spacing %s to %s" % [center, other])
				return
	for kind in _Marks.KINDS:
		if not kinds.has(kind):
			_fail("scatter missed %s" % kind)
			return
	print("OK landmark scatter seed=%d count=%d kinds=%d" % [seed_value, first.size(), kinds.size()])


func _check_flag_off() -> void:
	var world = _World.new(SEED)
	var was: bool = _Marks.ENABLED
	_Marks.ENABLED = false
	var placed := _Marks.place(world)
	_Marks.ENABLED = was
	if placed != 0:
		_fail("flag off still placed %d" % placed)
		return
	print("OK landmark flag off places nothing")


func _check_skips_feature() -> void:
	_WorldState.replace_active()
	var spots: Array[Dictionary] = _Marks.scatter(SEED)
	if spots.is_empty():
		_fail("skip check had no landmark")
		return
	var center: Vector2i = spots[0].get("center", Vector2i.ZERO)
	_Features.register_feature(center.x, center.y, _FeatureTypes.FeatureKind.RUIN, {"center": center, "name": "block"})
	var placed := _Marks.install(spots)
	var feat: Dictionary = _Features.get_feature(center.x, center.y)
	_WorldState.replace_active()
	if int(feat.get("kind", -1)) != _FeatureTypes.FeatureKind.RUIN:
		_fail("landmark overwrote the ruin at %s" % center)
		return
	if placed >= spots.size():
		_fail("install ignored the blocked cell")
		return
	print("OK landmark skips occupied cell %s" % center)


func _check_place_dry(seed_value: int) -> void:
	_WorldState.replace_active()
	var world = _World.new(seed_value)
	var planned: Array[Dictionary] = _Marks.scatter(seed_value)
	var placed := _Marks.place(world)
	if placed < 1:
		_fail("place installed nothing")
		_WorldState.replace_active()
		return
	var found := 0
	for spot in planned:
		var center: Vector2i = spot.get("center", Vector2i.ZERO)
		var feat: Dictionary = _Features.get_feature(center.x, center.y)
		if not bool(feat.get("landmark", false)):
			continue
		found += 1
		if str(feat.get("poi_kind", "")) != str(spot.get("poi_kind", "")):
			_fail("placed kind drifted at %s" % center)
			_WorldState.replace_active()
			return
		var tile := int(world.get_tile_type(float(center.x), float(center.y)))
		if tile == _Voxels.RIVER or tile == _Voxels.WATER or tile == _Voxels.OCEAN or tile == _Voxels.OCEAN2 or tile == _Voxels.OCEAN3:
			_fail("landmark sits on water %s" % center)
			_WorldState.replace_active()
			return
	_WorldState.replace_active()
	if found != placed:
		_fail("placed %d but found %d landmark features" % [placed, found])
		return
	print("OK landmark place dry count=%d of %d planned" % [placed, planned.size()])


func _measure(seed_value: int) -> void:
	_WorldState.replace_active()
	var world = _World.new(seed_value)
	var chunks := _chunk_count()
	var pois := _Poi.scatter(seed_value).size()
	var props_off := _count_props(seed_value)
	var was: bool = _Marks.ENABLED
	_Marks.ENABLED = false
	var marks_off := _Marks.place(world)
	_Marks.ENABLED = was
	_Marks.ENABLED = true
	var marks_on := _Marks.place(world)
	var props_on := _count_props(seed_value)
	var pois_again := _Poi.scatter(seed_value).size()
	_WorldState.replace_active()
	if marks_off != 0:
		_fail("measure flag off placed landmarks")
		return
	if marks_on < 1:
		_fail("measure flag on placed no landmarks")
		return
	if pois_again != pois:
		_fail("poi plan changed when landmarks installed")
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append("seed=%d chunks=%d prop_budget=%d ortho=%d" % [seed_value, chunks, PROP_BUDGET, int(_Marks.READ_VIEW)])
	lines.append("MEASURE flag=off props=%d props_per_chunk=%.4f pois=%d pois_per_chunk=%.4f landmarks=0 landmarks_per_chunk=0.0000" % [
		props_off, float(props_off) / float(chunks), pois, float(pois) / float(chunks),
	])
	lines.append("MEASURE flag=on props=%d props_per_chunk=%.4f pois=%d pois_per_chunk=%.4f landmarks=%d landmarks_per_chunk=%.4f" % [
		props_on, float(props_on) / float(chunks), pois, float(pois) / float(chunks), marks_on, float(marks_on) / float(chunks),
	])
	lines.append("MEASURE delta props=%d pois=0 landmarks=+%d" % [props_on - props_off, marks_on])
	lines.append("MEASURE note poi count is PoiScatter.scatter over the same band; landmarks are extra sites and are not inside the poi chunk budget. Props use the medium budget and skip a cell once a landmark is installed.")
	if not _write_measure(lines):
		return
	for line in lines:
		print(line)


func _check_prop_skips_landmark(seed_value: int) -> void:
	_WorldState.replace_active()
	var spots: Array[Dictionary] = _Props.for_chunk(seed_value, 4, 5, PROP_BUDGET, null)
	if spots.is_empty():
		_fail("prop skip had no prop")
		return
	var cell: Vector2i = spots[0].get("cell", Vector2i.ZERO)
	_Marks.install([{
		"center": cell,
		"chunk": Vector2i(4, 5),
		"poi_kind": "rock_spire",
		"landmark": true,
	}])
	var after: Array[Dictionary] = _Props.for_chunk(seed_value, 4, 5, PROP_BUDGET, null)
	_WorldState.replace_active()
	for spot in after:
		if spot.get("cell", Vector2i.ZERO) == cell:
			_fail("prop stayed on landmark cell %s" % cell)
			return
	print("OK prop skips landmark cell %s" % cell)


func _check_layer(seed_value: int) -> void:
	_WorldState.replace_active()
	var world = _World.new(seed_value)
	var cell := Vector2i(8 * ChunkData.SIZE + 6, 3 * ChunkData.SIZE + 6)
	_Marks.install([{
		"center": cell,
		"chunk": Vector2i(8, 3),
		"poi_kind": "crystal_glow",
		"landmark": true,
	}])
	var layer = _Layer.new()
	root.add_child(layer)
	var buildings := Node3D.new()
	buildings.name = "Buildings"
	layer.add_child(buildings)
	layer._buildings_root = buildings
	var veg := Node3D.new()
	layer.add_child(veg)
	layer._vegetation_root = veg
	layer.world = world
	var reg = _Registry.new()
	reg.max_feature_billboards_per_chunk = 48
	layer._registry = reg
	layer._props_per_chunk = 0
	_Props.ENABLED = false
	layer._populate_chunk(Vector2i(8, 3))
	_Props.ENABLED = true
	var found := false
	var height := 0.0
	for child in buildings.get_children():
		if str(child.name) == "DistantLandmark" and str(child.get_meta("landmark_kind", "")) == "crystal_glow":
			found = true
			height = _Marks.model_height(child)
			if _Marks.glow_energy(child) < 2.0:
				_fail("layer crystal glow is dim")
				layer.queue_free()
				_WorldState.replace_active()
				return
	layer.queue_free()
	_WorldState.replace_active()
	if not found or height < _Marks.MIN_HEIGHT:
		_fail("layer did not place a tall crystal glow (found=%s h=%.2f)" % [str(found), height])
		return
	print("OK feature layer crystal glow height=%.2f" % height)


func _count_props(seed_value: int) -> int:
	var total := 0
	for cz in range(_Marks.REGION_MIN.y, _Marks.REGION_MAX.y + 1):
		for cx in range(_Marks.REGION_MIN.x, _Marks.REGION_MAX.x + 1):
			total += _Props.for_chunk(seed_value, cx, cz, PROP_BUDGET, null).size()
	return total


func _chunk_count() -> int:
	return (_Marks.REGION_MAX.x - _Marks.REGION_MIN.x + 1) * (_Marks.REGION_MAX.y - _Marks.REGION_MIN.y + 1)


func _write_measure(lines: PackedStringArray) -> bool:
	DirAccess.make_dir_recursive_absolute("D:/ARCHIVE/CrystalStorm/verify-evidence/pivot-0.4/density")
	var f := FileAccess.open(MEASURE_PATH, FileAccess.WRITE)
	if f == null:
		_fail("could not write %s" % MEASURE_PATH)
		return false
	for line in lines:
		f.store_line(line)
	f.close()
	return true


func _signature(spots: Array[Dictionary]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for spot in spots:
		var center: Vector2i = spot.get("center", Vector2i.ZERO)
		parts.append("%s:%s:%s" % [center, str(spot.get("poi_kind", "")), str(spot.get("chunk", Vector2i.ZERO))])
	return "|".join(parts)
