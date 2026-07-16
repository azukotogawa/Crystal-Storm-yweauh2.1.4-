class_name VisualProximity
extends RefCounted

const _WorldSettings = preload("res://config/world_settings.gd")


static func player_column_distance(tree: SceneTree, wx: int, wz: int) -> float:
	if tree == null:
		return 0.0
	var player = tree.get_first_node_in_group("player")
	if player == null:
		return 0.0
	var px: float
	var pz: float
	if player.has_method("get_voxel_position"):
		var vp: Vector3 = player.get_voxel_position()
		px = vp.x
		pz = vp.z
	elif player.get("voxel_position") is Vector3:
		var vp: Vector3 = player.get("voxel_position")
		px = vp.x
		pz = vp.z
	else:
		var ws = _WorldSettings.get_active()
		px = ws.world_to_column(player.global_position.x)
		pz = ws.world_to_column(player.global_position.z)
	return Vector2(float(wx) + 0.5 - px, float(wz) + 0.5 - pz).length()


static func use_voxel_within_distance(
	tree: SceneTree,
	voxel_models_enabled: bool,
	distance_columns: int,
	wx: int,
	wz: int
) -> bool:
	if not voxel_models_enabled:
		return false
	if distance_columns <= 0:
		return true
	return player_column_distance(tree, wx, wz) <= float(distance_columns)