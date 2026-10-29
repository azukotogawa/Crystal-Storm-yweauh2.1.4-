class_name PropScatter
extends RefCounted

const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldBorder = preload("res://helpers/world_border.gd")
const _Props = preload("res://helpers/voxel_prop_builder.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")

static var ENABLED: bool = true

const MIN_SPACING := 3
const ORIGIN_CLEAR := 14.0
const KINDS: Array[String] = [
	"rock", "log", "bush", "flower", "mushroom", "fence",
	"flower_red", "flower_yellow", "flower_blue", "flower_white",
	"grass_tuft", "fern", "boulder", "stump", "reeds", "sapling", "dead_bush",
]
const DENSITY_SCALE := 0.7
const FIELD_CELLS := 28.0
const CLEARING_BELOW := 0.34
const CLUSTER_SHARE := 0.55
const CLUSTER_RADIUS := 3
const KIND_PATCH_CELLS := 7
const KIND_PATCH_SHARE := 0.6
const BIOME_WEIGHTS: Dictionary = {
	"plains": {"grass_tuft": 4, "flower_red": 2, "flower_yellow": 2, "flower_blue": 1, "flower_white": 1, "rock": 2, "bush": 2, "sapling": 1, "stump": 1, "log": 1, "mushroom": 1, "fence": 1, "boulder": 1},
	"forest": {"fern": 4, "mushroom": 3, "log": 3, "stump": 2, "sapling": 2, "bush": 3, "rock": 1, "boulder": 1, "grass_tuft": 2, "flower_white": 1},
	"marsh": {"reeds": 5, "grass_tuft": 3, "mushroom": 2, "flower_blue": 1, "flower_white": 1, "log": 1, "bush": 1, "fern": 2, "stump": 1},
	"steppe": {"grass_tuft": 4, "dead_bush": 3, "rock": 3, "boulder": 2, "flower_yellow": 1, "stump": 1, "bush": 1},
	"highland": {"rock": 4, "boulder": 3, "grass_tuft": 2, "dead_bush": 1, "flower_white": 1, "fern": 1, "sapling": 1, "bush": 1},
}


static func for_chunk(seed_value: int, cx: int, cz: int, budget: int, world = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not ENABLED or budget <= 0:
		return out
	var cap := maxi(int(round(float(budget) * DENSITY_SCALE)), 1)
	var base_x := cx * ChunkData.SIZE
	var base_z := cz * ChunkData.SIZE
	var lo := 1
	var hi := ChunkData.SIZE - 2
	var tries := mini(maxi(budget * 6, 12), 72)
	for slot in tries:
		if out.size() >= cap:
			break
		var cell: Vector2i
		if not out.is_empty() and _unit(seed_value, cx, cz, slot * 7 + 3) < CLUSTER_SHARE:
			var anchor: Vector2i = out[int(_unit(seed_value, cx, cz, slot * 7 + 4) * float(out.size())) % out.size()].cell
			var jx := int(round((_unit(seed_value, cx, cz, slot * 7 + 5) + _unit(seed_value, cx, cz, slot * 7 + 6) - 1.0) * float(CLUSTER_RADIUS) * 1.6))
			var jz := int(round((_unit(seed_value, cx, cz, slot * 7 + 1) + _unit(seed_value, cx, cz, slot * 7 + 2) - 1.0) * float(CLUSTER_RADIUS) * 1.6))
			cell = Vector2i(clampi(anchor.x + jx, base_x + lo, base_x + hi), clampi(anchor.y + jz, base_z + lo, base_z + hi))
		else:
			cell = Vector2i(
				base_x + lo + int(_unit(seed_value, cx, cz, slot * 7 + 1) * float(hi - lo + 1)),
				base_z + lo + int(_unit(seed_value, cx, cz, slot * 7 + 2) * float(hi - lo + 1))
			)
		var field := _field(seed_value, cell)
		if field < CLEARING_BELOW:
			continue
		if _unit(seed_value, cell.x, cell.y, 911) > (field - CLEARING_BELOW) / (1.0 - CLEARING_BELOW) * 1.4:
			continue
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
		var kind := _kind_at(seed_value, cell, _biome_of(world, cell))
		var yaw := 90 * (int(_unit(seed_value, cell.x, cell.y, 13) * 4.0) % 4)
		out.append({
			"cell": cell,
			"chunk": Vector2i(cx, cz),
			"kind": kind,
			"yaw": yaw,
		})
	return out


static func _biome_of(world, cell: Vector2i) -> String:
	if world != null and world.has_method("get_biome"):
		var b: Dictionary = world.get_biome(float(cell.x), 0.0, float(cell.y))
		var name := str(b.get("name", "plains"))
		if BIOME_WEIGHTS.has(name):
			return name
	return "plains"


static func _kind_at(seed_value: int, cell: Vector2i, biome: String) -> String:
	var weights: Dictionary = BIOME_WEIGHTS.get(biome, BIOME_WEIGHTS["plains"])
	var r := _unit(seed_value, cell.x, cell.y, 4271)
	if _unit(seed_value, cell.x, cell.y, 4273) < KIND_PATCH_SHARE:
		var px := floori(float(cell.x) / float(KIND_PATCH_CELLS))
		var pz := floori(float(cell.y) / float(KIND_PATCH_CELLS))
		r = _unit(seed_value, px, pz, 4277)
	var total := 0
	for k in weights.keys():
		total += int(weights[k])
	var pick := r * float(total)
	var acc := 0.0
	for k in weights.keys():
		acc += float(weights[k])
		if pick < acc:
			return str(k)
	return str(weights.keys()[0])


static func _field(seed_value: int, cell: Vector2i) -> float:
	var fx := float(cell.x) / FIELD_CELLS
	var fz := float(cell.y) / FIELD_CELLS
	var x0 := floori(fx)
	var z0 := floori(fz)
	var tx := smoothstep(0.0, 1.0, fx - float(x0))
	var tz := smoothstep(0.0, 1.0, fz - float(z0))
	var a := _unit(seed_value, x0, z0, 5003)
	var b := _unit(seed_value, x0 + 1, z0, 5003)
	var c := _unit(seed_value, x0, z0 + 1, 5003)
	var d := _unit(seed_value, x0 + 1, z0 + 1, 5003)
	var low := lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)
	var gx := float(cell.x) / (FIELD_CELLS * 0.37)
	var gz := float(cell.y) / (FIELD_CELLS * 0.37)
	var g0 := floori(gx)
	var h0 := floori(gz)
	var ux := smoothstep(0.0, 1.0, gx - float(g0))
	var uz := smoothstep(0.0, 1.0, gz - float(h0))
	var e := lerpf(lerpf(_unit(seed_value, g0, h0, 5009), _unit(seed_value, g0 + 1, h0, 5009), ux), lerpf(_unit(seed_value, g0, h0 + 1, 5009), _unit(seed_value, g0 + 1, h0 + 1, 5009), ux), uz)
	return clampf(low * 0.7 + e * 0.3, 0.0, 1.0)


static func _fmix(h: int) -> int:
	h = h & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x85EBCA6B) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 0xC2B2AE35) & 0xFFFFFFFF
	return h ^ (h >> 16)


static func _unit(seed_value: int, a: int, b: int, salt: int) -> float:
	var h := _fmix(int(seed_value) ^ 0x9E3779B9)
	h = _fmix(h ^ (int(a) & 0xFFFFFFFF))
	h = _fmix(h + 0x7F4A7C15 ^ (int(b) & 0xFFFFFFFF))
	h = _fmix(h ^ (int(salt) * 0x27D4EB2F & 0xFFFFFFFF))
	return float(h & 0xFFFFFF) / 16777216.0

static func build_visual(kind: String) -> Node3D:
	return _Props.build_scatter_prop(kind)


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
