class_name PlaceableCatalog
extends RefCounted
## Place-tool palette. Hotbar still holds materials/weapons; Tab cycles this list.
## RMB places the selected id. LMB removes using the existing subtract contract.

const IDS: PackedStringArray = [
	"fill",
	"cardinal_ramp",
	"corner_ramp",
	"stone_wall",
	"gate",
	"bridge",
]


static func count() -> int:
	return IDS.size()


static func id_at(index: int) -> String:
	if IDS.is_empty():
		return "fill"
	var i: int = posmod(index, IDS.size())
	return str(IDS[i])


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
		_:
			return place_id


static func is_structure(place_id: String) -> bool:
	return place_id in ["stone_wall", "gate", "bridge"]


static func is_terrain_edit(place_id: String) -> bool:
	return place_id in ["fill", "cardinal_ramp", "corner_ramp"]
