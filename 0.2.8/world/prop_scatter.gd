class_name PropScatter
extends RefCounted

const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldBorder = preload("res://helpers/world_border.gd")
const _Props = preload("res://helpers/voxel_prop_builder.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")

static var ENABLED: bool = true

const MIN_SPACING := 3
const ORIGIN_CLEAR := 14.0
const KINDS: Array[String] = ["rock", "log", "bush", "flower", "mushroom", "fence"]
const _WEIGHTS: Array[int] = [3, 2, 3, 3, 2, 1]


static func for_chunk(seed_value: int, cx: int, cz: int, budget: int, world = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not ENABLED or budget <= 0:
		return out
	var span := ChunkData.SIZE - 2
	var tries := mini(maxi(budget * 6, 12), 72)
	for slot in tries:
		if out.size() >= budget:
			break
		var roll := _mix(seed_value, cx, cz, slot + 1)
		var cell := Vector2i(
			cx * ChunkData.SIZE + 1 + posmod(roll, span),
			cz * ChunkData.SIZE + 1 + posmod(_mix(seed_value, cx, cz, slot + 97), span)
		)
		if not _cell_open(world, cell):
			continue
		var crowded := false
		for prev in out:
			var other: Vector2i = prev.get("cell", Vector2i.ZERO)
			if other == cell or Vector2(cell).distance_to(Vector2(other)) < float(MIN_SPACING):
				crowded = true
				break
		if crowded:
			continue
		var kind := _kind_for(roll)
		var yaw := 0
		if kind == "fence" or kind == "log":
			yaw = 90 if posmod(_mix(seed_value, cx, cz, slot + 13), 2) == 1 else 0
		out.append({
			"cell": cell,
			"chunk": Vector2i(cx, cz),
			"kind": kind,
			"yaw": yaw,
		})
	return out


static func build_visual(kind: String) -> Node3D:
	return _Props.build_scatter_prop(kind)


static func _kind_for(roll: int) -> String:
	var total := 0
	for w in _WEIGHTS:
		total += int(w)
	if total <= 0:
		return KINDS[0]
	var pick := posmod(roll, total)
	var acc := 0
	for i in _WEIGHTS.size():
		acc += int(_WEIGHTS[i])
		if pick < acc:
			return KINDS[i]
	return KINDS[0]


static func _cell_open(world, cell: Vector2i) -> bool:
	if Vector2(cell).length() < ORIGIN_CLEAR:
		return false
	if not _WorldBorder.is_playable(float(cell.x), float(cell.y)):
		return false
	if not _FeatureRegistry.get_feature(cell.x, cell.y).is_empty():
		return false
	if world != null and world.has_method("get_tile_type"):
		var tile := int(world.get_tile_type(float(cell.x) + 0.5, float(cell.y) + 0.5))
		if tile == _VoxelTypes.RIVER or tile == _VoxelTypes.WATER \
				or tile == _VoxelTypes.OCEAN or tile == _VoxelTypes.OCEAN2 or tile == _VoxelTypes.OCEAN3:
			return false
	return true


static func _mix(seed_value: int, cx: int, cz: int, salt: int) -> int:
	var n: int = int(seed_value) * 2246822519 + int(cx) * 3266489917 + int(cz) * 668265263 + int(salt) * 374761393
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	if n < 0:
		n = -n
	if n < 0:
		n = 0
	return n
