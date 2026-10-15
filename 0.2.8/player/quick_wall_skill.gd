class_name QuickWallSkill
extends RefCounted

const _Blueprints = preload("res://helpers/structure_blueprints.gd")

const SKILL_ID := &"quick_wall"
const BLUEPRINT_ID := &"wall_segment"
const COST_SCALE := 0.5


static func full_count() -> int:
	return int(_Blueprints.get_blueprint(BLUEPRINT_ID).get("cost", {}).get("count", 0))


static func wood_full() -> int:
	return int(_Blueprints.get_blueprint(BLUEPRINT_ID).get("cost", {}).get("wood_fallback", 0))


static func material_id() -> String:
	return str(_Blueprints.get_blueprint(BLUEPRINT_ID).get("cost", {}).get("id", "stone"))


static func reduced_count(full: int) -> int:
	if full <= 0:
		return 0
	return maxi(1, int(ceil(float(full) * COST_SCALE)))


static func forward_step(facing: Vector2) -> Vector2i:
	var dir := facing
	if dir.length_squared() < 0.0001:
		dir = Vector2(0.0, -1.0)
	else:
		dir = dir.normalized()
	var step := Vector2i(int(round(dir.x)), int(round(dir.y)))
	if step != Vector2i.ZERO:
		return step
	if absf(dir.x) >= absf(dir.y):
		return Vector2i(1 if dir.x >= 0.0 else -1, 0)
	return Vector2i(0, 1 if dir.y >= 0.0 else -1)


static func quarter_for_facing(facing: Vector2) -> int:
	var dir := facing
	if dir.length_squared() < 0.0001:
		dir = Vector2(0.0, -1.0)
	if absf(dir.x) > absf(dir.y):
		return 3 if dir.x >= 0.0 else 1
	return 0


static func anchor_column(feet: Vector2i, facing: Vector2) -> Vector2i:
	return feet + forward_step(facing)


static func place(editor, inventory, feet: Vector2i, facing: Vector2) -> Dictionary:
	var anchor := anchor_column(feet, facing)
	var quarter := quarter_for_facing(facing)
	var result := {"placed": false, "anchor": anchor, "quarter": quarter}
	if editor == null or not editor.has_method("try_place_blueprint"):
		return result
	var column := Vector3(float(anchor.x), 0.0, float(anchor.y))
	result["placed"] = bool(editor.try_place_blueprint(column, inventory, BLUEPRINT_ID, quarter, COST_SCALE))
	return result
