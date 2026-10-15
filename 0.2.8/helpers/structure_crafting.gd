class_name StructureCrafting
extends RefCounted

const _Blueprints = preload("res://helpers/structure_blueprints.gd")


static func item_id(blueprint_id: StringName) -> String:
	return String(blueprint_id)


static func is_piece(piece_id: String) -> bool:
	if not _Blueprints.LARGE_STRUCTURES:
		return false
	return _Blueprints.ids().has(StringName(piece_id))


static func can_craft(inventory, blueprint_id: StringName) -> bool:
	return not _quote(inventory, blueprint_id).is_empty()


static func craft(inventory, blueprint_id: StringName) -> bool:
	var quote := _quote(inventory, blueprint_id)
	if quote.is_empty():
		return false
	if not _consume(inventory, quote):
		return false
	var left: int = inventory.add_item(item_id(blueprint_id), 1)
	if left > 0:
		_refund(inventory, quote)
		return false
	return true


static func _quote(inventory, blueprint_id: StringName) -> Array:
	if inventory == null or not inventory.has_method("count_item"):
		return []
	var bp := _Blueprints.get_blueprint(blueprint_id)
	if bp.is_empty():
		return []
	var recipe: Array = bp.get("recipe", [])
	if _covers(inventory, recipe):
		return recipe.duplicate(true)
	var cost: Dictionary = bp.get("cost", {})
	var wood_n := int(cost.get("wood_fallback", 0))
	if str(cost.get("id", "")) == "stone" and wood_n > 0 and int(inventory.count_item("wood")) >= wood_n:
		return [{"id": "wood", "count": wood_n}]
	return []


static func _covers(inventory, lines: Array) -> bool:
	if lines.is_empty():
		return false
	for line in lines:
		var need := int((line as Dictionary).get("count", 0))
		if need <= 0:
			return false
		if int(inventory.count_item(str((line as Dictionary).get("id", "")))) < need:
			return false
	return true


static func _consume(inventory, lines: Array) -> bool:
	var spent: Array = []
	for line in lines:
		var id := str((line as Dictionary).get("id", ""))
		var need := int((line as Dictionary).get("count", 0))
		if not inventory.consume_item(id, need):
			_refund(inventory, spent)
			return false
		spent.append({"id": id, "count": need})
	return true


static func _refund(inventory, lines: Array) -> void:
	if not inventory.has_method("add_item"):
		return
	for line in lines:
		inventory.add_item(str((line as Dictionary).get("id", "")), int((line as Dictionary).get("count", 0)))
