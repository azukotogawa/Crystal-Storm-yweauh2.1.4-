extends SceneTree
## Regression: attack path must classify tools via item def category (not GDScript.is_tool shadow).

const _ItemTypes = preload("res://helpers/item_types.gd")


func _init() -> void:
	var failed := false
	var def := _ItemTypes.get_def("stone_pick")
	if def.is_empty():
		push_error("stone_pick def missing")
		failed = true
	var cat := int(def.get("category", -1))
	if cat != _ItemTypes.Category.TOOL:
		push_error("stone_pick category should be TOOL got %d" % cat)
		failed = true
	else:
		print("OK stone_pick category TOOL via get_def")
	var kind := int(def.get("weapon_kind", -1))
	if kind != _ItemTypes.WeaponKind.DIG:
		push_error("stone_pick weapon_kind should be DIG")
		failed = true
	else:
		print("OK stone_pick weapon_kind DIG")
	if failed:
		quit(1)
	print("All weapon attack static tests OK")
	quit(0)