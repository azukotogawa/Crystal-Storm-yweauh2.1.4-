class_name DungeonGraph
extends RefCounted

## Room-graph dungeon placer (plan #9 option A).
## Places a surface entrance, a short corridor, and one empty_room prefab.
## Carving uses TerrainEdits.dig → WorldState.height_delta (bake/stream path).
## Walls/floor use FeatureRegistry tile overrides (also bake/stream).

const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _WorldBorder = preload("res://helpers/world_border.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _EmptyPrefab = preload("res://world/prefabs/empty_room_prefab.gd")

static var ENABLED: bool = true

const POI_KIND := "dungeon_entrance"
const DISPLAY_NAME := "Dungeon Entrance"
const MIN_FROM_SPAWN := 48
const CORRIDOR_LEN := 5
const ENTRANCE_DIG := 1
const CORRIDOR_DIG_START := 2


static func plan(world) -> Dictionary:
	if world == null:
		return {}
	return plan_for_seed(int(world.world_seed))


static func plan_for_seed(seed_value: int) -> Dictionary:
	var spawn := _WorldBorder.origin_corner_for_seed(seed_value)
	var mix := _mix(seed_value, 41)
	var dir := _cardinal(mix % 4)
	var dist := MIN_FROM_SPAWN + int(mix % 24)
	var entrance := spawn + dir * dist
	var room_center := entrance + dir * (CORRIDOR_LEN + _EmptyPrefab.HALF_W + 1)
	var corridor: Array[Vector2i] = []
	for i in range(1, CORRIDOR_LEN + 1):
		corridor.append(entrance + dir * i)
	# Door cell into the room (break the near wall).
	var door := room_center - dir * _EmptyPrefab.HALF_W
	var digs := {}
	digs[entrance] = ENTRANCE_DIG
	for i in range(corridor.size()):
		var cell: Vector2i = corridor[i]
		digs[cell] = mini(CORRIDOR_DIG_START + i, _EmptyPrefab.DIG_LAYERS)
	digs[door] = _EmptyPrefab.DIG_LAYERS
	for cell in _EmptyPrefab.interior_cells(room_center):
		digs[cell] = _EmptyPrefab.DIG_LAYERS
	# Keep a clear mouth at the door so the wall ring does not seal the corridor.
	var walls: Array[Vector2i] = []
	for cell in _EmptyPrefab.wall_cells(room_center):
		if cell == door:
			continue
		walls.append(cell)
	var floors: Array[Vector2i] = _EmptyPrefab.interior_cells(room_center)
	floors.append(door)
	return {
		"seed": seed_value,
		"spawn": spawn,
		"entrance": entrance,
		"dir": dir,
		"corridor": corridor,
		"door": door,
		"rooms": [{
			"prefab": _EmptyPrefab.ID,
			"center": room_center,
			"half_w": _EmptyPrefab.HALF_W,
			"half_d": _EmptyPrefab.HALF_D,
			"dig_layers": _EmptyPrefab.DIG_LAYERS,
		}],
		"walls": walls,
		"floors": floors,
		"digs": digs,
		"prefab": _EmptyPrefab.describe(),
	}


static func place(world) -> int:
	if not ENABLED or world == null:
		return 0
	return install(plan(world))


static func install(plan_dict: Dictionary) -> int:
	if plan_dict.is_empty():
		return 0
	var entrance: Vector2i = plan_dict.get("entrance", Vector2i.ZERO)
	if not _FeatureRegistry.get_feature(entrance.x, entrance.y).is_empty():
		return 0
	var digs: Dictionary = plan_dict.get("digs", {})
	for key_v in digs.keys():
		var cell: Vector2i = key_v
		var layers: int = int(digs[key_v])
		if layers <= 0:
			continue
		if not _TerrainEdits.dig(cell.x, cell.y, layers):
			# Cap is -6; partial dig still leaves a depression — keep going.
			var left := layers
			while left > 0:
				if not _TerrainEdits.dig(cell.x, cell.y, 1):
					break
				left -= 1
	for cell_v in plan_dict.get("walls", []):
		var w: Vector2i = cell_v
		_FeatureRegistry.set_tile_override(w.x, w.y, _EmptyPrefab.WALL_TILE, true)
	for cell_v in plan_dict.get("floors", []):
		var f: Vector2i = cell_v
		_FeatureRegistry.set_tile_override(f.x, f.y, _EmptyPrefab.FLOOR_TILE, true)
	var rooms: Array = plan_dict.get("rooms", [])
	var room0: Dictionary = rooms[0] if not rooms.is_empty() else {}
	var payload := {
		"center": entrance,
		"name": DISPLAY_NAME,
		"poi": true,
		"poi_kind": POI_KIND,
		"dungeon": true,
		"surface_entrance": true,
		"spawn": plan_dict.get("spawn", Vector2i.ZERO),
		"dir": plan_dict.get("dir", Vector2i.RIGHT),
		"door": plan_dict.get("door", entrance),
		"rooms": rooms,
		"prefab": str(room0.get("prefab", _EmptyPrefab.ID)),
		"room_center": room0.get("center", entrance),
	}
	_FeatureRegistry.register_feature(
		entrance.x,
		entrance.y,
		_WorldFeatureTypes.FeatureKind.POI,
		payload
	)
	_FeatureRegistry.set_tile_override(entrance.x, entrance.y, _EmptyPrefab.WALL_TILE, true)
	return 1


static func _cardinal(q: int) -> Vector2i:
	match q:
		0:
			return Vector2i(1, 0)
		1:
			return Vector2i(-1, 0)
		2:
			return Vector2i(0, 1)
		_:
			return Vector2i(0, -1)


static func _mix(seed_value: int, salt: int) -> int:
	var x := seed_value ^ (salt * 0x9E3779B9)
	x = (x ^ (x >> 16)) * 0x7FEB352D
	x = (x ^ (x >> 15)) * 0x846CA68B
	return absi(x ^ (x >> 16))
