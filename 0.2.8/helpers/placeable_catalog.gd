class_name PlaceableCatalog
extends RefCounted
## Only dig tools break blocks.

const _Blueprints = preload("res://helpers/structure_blueprints.gd")

const IDS: PackedStringArray = [
	"fill",
	"cardinal_ramp",
	"corner_ramp",
	"stone_wall",
	"gate",
	"bridge",
]


static func entries() -> PackedStringArray:
	var out: PackedStringArray = IDS.duplicate()
	if not _Blueprints.LARGE_STRUCTURES:
		return out
	for id in _Blueprints.ids():
		var key := String(id)
		if not out.has(key):
			out.append(key)
	return out


static func count() -> int:
	return entries().size()


static func id_at(index: int) -> String:
	var list := entries()
	if list.is_empty():
		return "fill"
	return str(list[posmod(index, list.size())])


static func display_name(place_id: String) -> String:
	match place_id:
		"fill":
			return "Fill"
		"cardinal_ramp":
			return "Ramp"
		"corner_ramp":
			return "Corner ramp"
		"stone_wall":
			return "Wall"
		"gate":
			return "Gate"
		"bridge":
			return "Bridge"
		"wall_segment":
			return "Wall Segment"
		"wall_corner":
			return "Wall Corner"
		"stairs":
			return "Stairs"
		"small_tower":
			return "Small Tower"
		_:
			return place_id


static func is_structure(place_id: String) -> bool:
	return place_id in ["stone_wall", "gate", "bridge", "wall_segment", "wall_corner", "stairs", "small_tower"]


static func is_terrain_edit(place_id: String) -> bool:
	return place_id in ["fill", "cardinal_ramp", "corner_ramp"]
