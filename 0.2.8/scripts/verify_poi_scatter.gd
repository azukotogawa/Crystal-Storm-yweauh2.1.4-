extends SceneTree

const _Poi = preload("res://world/poi_scatter.gd")
const _WorldState = preload("res://world/world_state.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _Blueprints = preload("res://helpers/structure_blueprints.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)
	print("FAIL " + msg)


func _run() -> void:
	_check_flag()
	_check_seed_count_and_spacing(44021)
	_check_seed_count_and_spacing(918337)
	_check_seeds_differ(44021, 918337)
	_check_budget_drops_second_slot(44021)
	_check_layouts()
	_check_visuals()
	_check_install()
	_check_flag_off_place()
	if _failed == 0:
		print("All poi scatter tests OK")
		quit(0)
	else:
		push_error("verify_poi_scatter: %d failure(s)" % _failed)
		quit(1)


func _check_flag() -> void:
	if not _Poi.ENABLED:
		_fail("POI scatter must default on")
		return
	if _Poi.CHUNK_BUDGET < 1 or _Poi.MIN_SPACING < 1:
		_fail("budget and spacing must be positive")
		return
	print("OK poi scatter flag budget=%d spacing=%d" % [_Poi.CHUNK_BUDGET, _Poi.MIN_SPACING])


func _check_seed_count_and_spacing(seed_value: int) -> void:
	var first: Array[Dictionary] = _Poi.scatter(seed_value)
	var again: Array[Dictionary] = _Poi.scatter(seed_value)
	if first.is_empty():
		_fail("seed %d scattered nothing" % seed_value)
		return
	if first.size() != again.size() or _signature(first) != _signature(again):
		_fail("seed %d is not deterministic" % seed_value)
		return
	var seen: Dictionary = {}
	var per_chunk: Dictionary = {}
	var kinds: Dictionary = {}
	for i in first.size():
		var spot: Dictionary = first[i]
		var center: Vector2i = spot.get("center", Vector2i.ZERO)
		var chunk: Vector2i = spot.get("chunk", Vector2i.ZERO)
		var kind := str(spot.get("poi_kind", ""))
		if kind not in _Poi.KINDS:
			_fail("unknown poi kind %s" % kind)
			return
		kinds[kind] = true
		if seen.has(center):
			_fail("duplicate poi at %s" % center)
			return
		seen[center] = true
		var expect := Vector2i(
			floori(float(center.x) / float(ChunkData.SIZE)),
			floori(float(center.y) / float(ChunkData.SIZE))
		)
		if chunk != expect:
			_fail("poi %s recorded chunk %s, floor chunk is %s" % [center, chunk, expect])
			return
		per_chunk[chunk] = int(per_chunk.get(chunk, 0)) + 1
		if int(per_chunk[chunk]) > _Poi.CHUNK_BUDGET:
			_fail("chunk %s exceeded budget %d" % [chunk, _Poi.CHUNK_BUDGET])
			return
		for j in i:
			var other: Vector2i = first[j].get("center", Vector2i.ZERO)
			if Vector2(center).distance_to(Vector2(other)) < float(_Poi.MIN_SPACING):
				_fail("spacing %s to %s is under %d" % [center, other, _Poi.MIN_SPACING])
				return
	if kinds.size() < _Poi.KINDS.size():
		_fail("seed %d missed a poi kind: %s" % [seed_value, str(kinds.keys())])
		return
	print("OK poi scatter seed=%d count=%d" % [seed_value, first.size()])


func _check_seeds_differ(a: int, b: int) -> void:
	if _signature(_Poi.scatter(a)) == _signature(_Poi.scatter(b)):
		_fail("seeds %d and %d scattered the same points" % [a, b])
		return
	print("OK poi scatter seeds differ")


func _check_budget_drops_second_slot(seed_value: int) -> void:
	var proposed: Array[Dictionary] = _Poi.proposals(seed_value)
	var accepted: Array[Dictionary] = _Poi.scatter(seed_value)
	var by_chunk: Dictionary = {}
	for spot in proposed:
		var chunk: Vector2i = spot.get("chunk", Vector2i.ZERO)
		if not by_chunk.has(chunk):
			by_chunk[chunk] = []
		(by_chunk[chunk] as Array).append(spot)
	var proved := false
	for chunk_v in by_chunk.keys():
		var rows: Array = by_chunk[chunk_v]
		if rows.size() < 2:
			continue
		var a: Vector2i = rows[0].get("center", Vector2i.ZERO)
		var b: Vector2i = rows[1].get("center", Vector2i.ZERO)
		if Vector2(a).distance_to(Vector2(b)) < float(_Poi.MIN_SPACING):
			continue
		var kept := 0
		for spot in accepted:
			if spot.get("chunk", Vector2i.ZERO) == chunk_v:
				kept += 1
		if kept != _Poi.CHUNK_BUDGET:
			_fail("chunk %s kept %d, budget is %d" % [chunk_v, kept, _Poi.CHUNK_BUDGET])
			return
		proved = true
		break
	if not proved:
		_fail("no chunk had two spaced proposals to prove the budget")
		return
	print("OK poi chunk budget")


func _check_layouts() -> void:
	if not _Blueprints.LARGE_STRUCTURES:
		_fail("structure blueprints are off, poi layouts cannot reuse them")
		return
	var camp: Array[Dictionary] = _Poi.layout("camp")
	if not _covers_ground(camp, _Blueprints.WALL_SEGMENT, "stone_wall"):
		_fail("camp layout did not reuse the wall segment")
		return
	if not _has_plant(camp, "bush"):
		_fail("camp layout is missing its bush prop")
		return
	var dig: Array[Dictionary] = _Poi.layout("abandoned_dig")
	if not _covers_ground(dig, _Blueprints.STAIRS, "stone_wall"):
		_fail("abandoned dig layout did not reuse the stairs")
		return
	var shrine: Array[Dictionary] = _Poi.layout("shrine")
	if not _covers_ground(shrine, _Blueprints.SMALL_TOWER, ""):
		_fail("shrine layout did not reuse the small tower footprint")
		return
	if not _has_structure(shrine, "ruin_pillar") or not _has_plant(shrine, "crystal_grass"):
		_fail("shrine layout is missing the pillar or crystal grass")
		return
	var grove: Array[Dictionary] = _Poi.layout("crystal_grove")
	if not _has_plant(grove, "shard_tree") or not _has_plant(grove, "crystal_bush") or not _has_plant(grove, "crystal_grass"):
		_fail("grove layout is missing crystal props")
		return
	print("OK poi layouts")


func _check_visuals() -> void:
	for kind in _Poi.KINDS:
		var node := _Poi.build_visual(kind)
		var props := 0
		var meshes := 0
		for child in node.get_children():
			if str(child.name).begins_with("VoxelProp"):
				props += 1
			if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
				meshes += 1
		if kind == "crystal_grove":
			if props < 3 or meshes != 0:
				_fail("grove visual props=%d meshes=%d" % [props, meshes])
				node.free()
				return
		elif props < 1 or meshes < 1:
			_fail("%s visual props=%d meshes=%d" % [kind, props, meshes])
			node.free()
			return
		node.free()
	print("OK poi visuals")


func _check_install() -> void:
	_WorldState.replace_active()
	var spots: Array[Dictionary] = _Poi.scatter(44021)
	var one: Array[Dictionary] = [spots[0]]
	if _Poi.install(one) != 1:
		_fail("install did not place the poi")
		_WorldState.replace_active()
		return
	var center: Vector2i = spots[0].get("center", Vector2i.ZERO)
	var feat: Dictionary = _FeatureRegistry.get_feature(center.x, center.y)
	if int(feat.get("kind", -1)) != _WorldFeatureTypes.FeatureKind.POI:
		_fail("installed cell is not a poi feature")
		_WorldState.replace_active()
		return
	if str(feat.get("poi_kind", "")) != str(spots[0].get("poi_kind", "")) or not bool(feat.get("poi", false)):
		_fail("installed poi lost its kind")
		_WorldState.replace_active()
		return
	if _Poi.install(one) != 0:
		_fail("second install overwrote the poi cell")
		_WorldState.replace_active()
		return
	_WorldState.replace_active()
	print("OK poi install")


func _check_flag_off_place() -> void:
	var was: bool = _Poi.ENABLED
	_Poi.ENABLED = false
	var placed := _Poi.place(null)
	_Poi.ENABLED = was
	if placed != 0:
		_fail("flag off still placed pois")
		return
	print("OK poi scatter flag off")


func _covers_ground(pieces: Array[Dictionary], blueprint_id: StringName, structure_id: String) -> bool:
	var bp: Dictionary = _Blueprints.get_blueprint(blueprint_id)
	var need: Dictionary = {}
	for cell_v in bp.get("cells", []):
		var cell: Dictionary = cell_v
		if int(cell.get("y", 0)) != 0:
			continue
		need[Vector2i(int(cell.get("x", 0)), int(cell.get("z", 0)))] = true
	if need.is_empty():
		return false
	for piece in pieces:
		var off: Vector2i = piece.get("offset", Vector2i.ZERO)
		if not bool(need.get(off, false)):
			continue
		var got := str(piece.get("structure", ""))
		if structure_id != "" and got != structure_id:
			continue
		if got == "":
			continue
		need.erase(off)
	return need.is_empty()


func _has_plant(pieces: Array[Dictionary], plant_id: String) -> bool:
	for piece in pieces:
		if str(piece.get("plant", "")) == plant_id:
			return true
	return false


func _has_structure(pieces: Array[Dictionary], structure_id: String) -> bool:
	for piece in pieces:
		if str(piece.get("structure", "")) == structure_id:
			return true
	return false


func _signature(spots: Array[Dictionary]) -> String:
	var parts: PackedStringArray = []
	for spot in spots:
		var center: Vector2i = spot.get("center", Vector2i.ZERO)
		parts.append("%d,%d:%s" % [center.x, center.y, str(spot.get("poi_kind", ""))])
	return "|".join(parts)
