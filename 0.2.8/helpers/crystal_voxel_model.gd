class_name CrystalVoxelModel
extends RefCounted

var model_name := ""
var size := Vector3i.ONE
var vpb := 16
var base_cell := 2
var scale_mode := "terrain_block"
var pivot := Vector3.ZERO
var palette := PackedColorArray()
var part_order := PackedStringArray()
var part_cells := {}


func voxel_count(part_name: String = "") -> int:
	if part_name == "":
		var total := 0
		for part_name_i in part_order:
			total += _part_len(str(part_name_i))
		return total
	return _part_len(part_name)


func cells_for(part_name: String) -> Array:
	if part_name != "":
		return part_cells.get(part_name, [])
	var all: Array = []
	for part_name_i in part_order:
		var chunk: Array = part_cells.get(str(part_name_i), [])
		all.append_array(chunk)
	return all


func color_at(x: int, y: int, z: int) -> Color:
	for part_name_i in part_order:
		var chunk: Array = part_cells.get(str(part_name_i), [])
		for cell in chunk:
			var c: Vector4i = cell
			if c.x == x and c.y == y and c.z == z:
				if c.w < 0 or c.w >= palette.size():
					return Color.WHITE
				return palette[c.w]
	return Color(0, 0, 0, 0)


func _part_len(part_name: String) -> int:
	if not part_cells.has(part_name):
		return 0
	return (part_cells[part_name] as Array).size()
