class_name StructureOrientation
extends RefCounted
## Shared yaw for authored structures. Gameplay stores it; visuals and collision read it.

const _FeatureRegistry = preload("res://world/feature_registry.gd")


static func yaw_for(wx: int, wz: int, visual_id: String) -> float:
	if visual_id == "bridge":
		return _run_yaw(wx, wz, true)
	if visual_id in ["wood_wall", "stone_wall", "gate"]:
		return _run_yaw(wx, wz, false)
	return 0.0


static func dir_from_yaw(yaw: float) -> Vector2i:
	var step: int = int(round(yaw / (PI * 0.5)))
	match posmod(step, 4):
		1:
			return Vector2i(0, 1)
		2:
			return Vector2i(-1, 0)
		3:
			return Vector2i(0, -1)
		_:
			return Vector2i(1, 0)


static func _run_yaw(wx: int, wz: int, bridges_only: bool) -> float:
	var ew := _connects(wx - 1, wz, bridges_only) or _connects(wx + 1, wz, bridges_only)
	var ns := _connects(wx, wz - 1, bridges_only) or _connects(wx, wz + 1, bridges_only)
	if ns and not ew:
		return PI * 0.5
	return 0.0


static func _connects(wx: int, wz: int, bridges_only: bool) -> bool:
	var feat: Dictionary = _FeatureRegistry.get_feature(wx, wz)
	if feat.is_empty():
		return false
	var id := visual_id_from_feature(feat)
	if bridges_only:
		return id == "bridge"
	return id in ["wood_wall", "stone_wall", "gate"]


static func persist_yaw(wx: int, wz: int) -> float:
	var feat: Dictionary = _FeatureRegistry.get_feature(wx, wz)
	if feat.is_empty():
		return 0.0
	var vid := visual_id_from_feature(feat)
	if vid.is_empty():
		return 0.0
	if vid not in ["wood_wall", "stone_wall", "gate", "bridge"]:
		return float(feat.get("yaw", 0.0))
	var yaw: float = yaw_for(wx, wz, vid)
	feat["yaw"] = yaw
	feat["dir"] = dir_from_yaw(yaw)
	var kind: int = int(feat.get("kind", 0))
	_FeatureRegistry.register_feature(wx, wz, kind, feat)
	return yaw


static func persist_yaw_neighborhood(wx: int, wz: int) -> void:
	persist_yaw(wx, wz)
	persist_yaw(wx - 1, wz)
	persist_yaw(wx + 1, wz)
	persist_yaw(wx, wz - 1)
	persist_yaw(wx, wz + 1)


static func visual_id_from_feature(feat: Dictionary) -> String:
	var build_id := str(feat.get("build_id", "")).strip_edges()
	if bool(feat.get("is_passage", false)) or build_id == "gate":
		return "gate"
	if bool(feat.get("is_bridge", false)) or build_id == "bridge":
		return "bridge"
	if build_id == "wood_wall" or build_id == "stone_wall":
		return build_id
	return build_id
