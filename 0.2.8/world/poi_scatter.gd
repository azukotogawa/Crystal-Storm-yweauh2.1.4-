class_name PoiScatter
extends RefCounted

const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _WorldBorder = preload("res://helpers/world_border.gd")
const _Blueprints = preload("res://helpers/structure_blueprints.gd")
const _Props = preload("res://helpers/voxel_prop_builder.gd")
const _VisualRegistry = preload("res://systems/game_visual_registry.gd")
const _Coords = preload("res://helpers/world_visual_coords.gd")

static var ENABLED: bool = true

const CHUNK_BUDGET := 1
const MIN_SPACING := 12
const SLOT_COUNT := 2
const ATTEMPT_MOD := 3
const ORIGIN_CLEAR := 40.0
const REGION_MIN := Vector2i(-16, -16)
const REGION_MAX := Vector2i(15, 15)

const KINDS: Array[String] = ["camp", "abandoned_dig", "crystal_grove", "shrine"]


static func scatter(seed_value: int, chunk_min: Vector2i = REGION_MIN, chunk_max: Vector2i = REGION_MAX) -> Array[Dictionary]:
	return _accept(proposals(seed_value, chunk_min, chunk_max))


static func proposals(seed_value: int, chunk_min: Vector2i = REGION_MIN, chunk_max: Vector2i = REGION_MAX) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var size := ChunkData.SIZE
	for cz in range(chunk_min.y, chunk_max.y + 1):
		for cx in range(chunk_min.x, chunk_max.x + 1):
			if _mix(seed_value, cx, cz, 0) % ATTEMPT_MOD != 0:
				continue
			for slot in SLOT_COUNT:
				var roll := _mix(seed_value, cx, cz, slot + 1)
				var local := _local_cell(roll, slot)
				var center := Vector2i(cx * size + local.x, cz * size + local.y)
				if Vector2(center).length() < ORIGIN_CLEAR:
					continue
				if not _WorldBorder.is_playable(float(center.x), float(center.y)):
					continue
				out.append({
					"center": center,
					"chunk": Vector2i(cx, cz),
					"poi_kind": KINDS[roll % KINDS.size()],
					"slot": slot,
				})
	return out


static func place(world) -> int:
	if not ENABLED or world == null:
		return 0
	var open: Array[Dictionary] = []
	for spot in scatter(int(world.world_seed)):
		var center: Vector2i = spot.get("center", Vector2i.ZERO)
		if _site_open(world, center):
			open.append(spot)
	return install(open)


static func install(spots: Array) -> int:
	var placed := 0
	for spot_v in spots:
		var spot: Dictionary = spot_v
		var center: Vector2i = spot.get("center", Vector2i.ZERO)
		if not _FeatureRegistry.get_feature(center.x, center.y).is_empty():
			continue
		var kind := str(spot.get("poi_kind", ""))
		_FeatureRegistry.register_feature(center.x, center.y, _WorldFeatureTypes.FeatureKind.POI, {
			"center": center,
			"name": display_name(kind),
			"poi": true,
			"poi_kind": kind,
		})
		placed += 1
	return placed


static func display_name(poi_kind: String) -> String:
	match poi_kind:
		"camp":
			return "Hunter Camp"
		"abandoned_dig":
			return "Abandoned Dig"
		"crystal_grove":
			return "Crystal Grove"
		"shrine":
			return "Shrine"
		_:
			return "Point of Interest"


static func layout(poi_kind: String) -> Array[Dictionary]:
	match poi_kind:
		"camp":
			return _structure_pieces(_Blueprints.WALL_SEGMENT, "stone_wall", [{"plant": "bush", "offset": Vector2i(0, 1)}])
		"abandoned_dig":
			return _structure_pieces(_Blueprints.STAIRS, "stone_wall", [{"plant": "fern", "offset": Vector2i(1, 0)}])
		"crystal_grove":
			return [
				{"structure": "", "plant": "shard_tree", "offset": Vector2i(0, 0)},
				{"structure": "", "plant": "crystal_bush", "offset": Vector2i(2, 1)},
				{"structure": "", "plant": "crystal_grass", "offset": Vector2i(-1, 2)},
			]
		"shrine":
			return _shrine_pieces()
		_:
			return []


static func build_visual(poi_kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "PoiVisual"
	var scale := _Coords.voxel_scale()
	var registry = _VisualRegistry.new()
	var parts: Array = []
	for piece in layout(poi_kind):
		var off: Vector2i = piece.get("offset", Vector2i.ZERO)
		var shift := Vector3(float(off.x) * scale, 0.0, float(off.y) * scale)
		var structure_id := str(piece.get("structure", ""))
		if structure_id != "":
			for part_v in registry.structure_mesh_parts(structure_id):
				var part: Dictionary = part_v
				parts.append({
					"center": (part.get("center", Vector3.ZERO) as Vector3) + shift,
					"size": part.get("size", Vector3.ONE),
				})
		var plant_id := str(piece.get("plant", ""))
		if plant_id != "":
			var prop := _Props.build_plant(plant_id, 2)
			prop.name = "VoxelProp_%s_%d_%d" % [plant_id, off.x, off.y]
			prop.position = shift
			root.add_child(prop)
	if not parts.is_empty():
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = "StructureMesh"
		mesh_inst.mesh = registry.build_structure_array_mesh(parts)
		root.add_child(mesh_inst)
	registry.free()
	return root


static func _accept(proposed: Array[Dictionary]) -> Array[Dictionary]:
	var accepted: Array[Dictionary] = []
	var per_chunk: Dictionary = {}
	for spot in proposed:
		var center: Vector2i = spot.get("center", Vector2i.ZERO)
		var chunk: Vector2i = spot.get("chunk", Vector2i.ZERO)
		var crowded := false
		for prev in accepted:
			var other: Vector2i = prev.get("center", Vector2i.ZERO)
			if Vector2(center).distance_to(Vector2(other)) < float(MIN_SPACING):
				crowded = true
				break
		if crowded:
			continue
		var used := int(per_chunk.get(chunk, 0))
		if used >= CHUNK_BUDGET:
			continue
		per_chunk[chunk] = used + 1
		accepted.append(spot)
	return accepted


static func _structure_pieces(blueprint_id: StringName, structure_id: String, plants: Array) -> Array[Dictionary]:
	var pieces: Array[Dictionary] = []
	for off in _ground_offsets(blueprint_id):
		pieces.append({"structure": structure_id, "plant": "", "offset": off})
	for plant_v in plants:
		var plant: Dictionary = plant_v
		pieces.append({
			"structure": "",
			"plant": str(plant.get("plant", "")),
			"offset": plant.get("offset", Vector2i.ZERO),
		})
	return pieces


static func _shrine_pieces() -> Array[Dictionary]:
	var pieces: Array[Dictionary] = []
	for off in _ground_offsets(_Blueprints.SMALL_TOWER):
		var structure_id := "stone_wall" if off != Vector2i.ZERO else "ruin_pillar"
		pieces.append({"structure": structure_id, "plant": "", "offset": off})
	pieces.append({"structure": "", "plant": "crystal_grass", "offset": Vector2i(0, 2)})
	return pieces


static func _ground_offsets(blueprint_id: StringName) -> Array[Vector2i]:
	var bp: Dictionary = _Blueprints.get_blueprint(blueprint_id)
	var cells: Array = bp.get("cells", [])
	var out: Array[Vector2i] = []
	for cell_v in cells:
		var cell: Dictionary = cell_v
		if int(cell.get("y", 0)) != 0:
			continue
		out.append(Vector2i(int(cell.get("x", 0)), int(cell.get("z", 0))))
	return out


static func _site_open(world, center: Vector2i) -> bool:
	if world == null or not world.has_method("get_tile_type"):
		return false
	var tile := int(world.get_tile_type(float(center.x), float(center.y)))
	if tile == VoxelTypes.RIVER or tile == VoxelTypes.WATER:
		return false
	if world.has_method("get_biome"):
		var biome: Dictionary = world.get_biome(float(center.x), 0.0, float(center.y))
		if str(biome.get("name", "")) in ["ocean", "border_mountain", "marsh"]:
			return false
	return _FeatureRegistry.get_feature(center.x, center.y).is_empty()


static func _local_cell(roll: int, slot: int) -> Vector2i:
	var n := posmod(roll, 3)
	var m := posmod(int(roll / 3), 3)
	if slot == 0:
		return Vector2i(n, m)
	return Vector2i(13 + n, 13 + m)


static func _mix(seed_value: int, cx: int, cz: int, salt: int) -> int:
	var n: int = int(seed_value) * 374761393 + int(cx) * 668265263 + int(cz) * 2146121005 + int(salt) * 1274126177
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	if n < 0:
		n = -n
	if n < 0:
		n = 0
	return n
