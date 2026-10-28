extends SceneTree

const _Nav = preload("res://entities/entity_navigation.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _Cut = preload("res://helpers/camera_cutaway.gd")
const _Coords = preload("res://helpers/world_visual_coords.gd")
const _Cfg = preload("res://config/entity_brain_config.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	var player = null
	for _i in 1800:
		player = get_first_node_in_group("player")
		if player and bool(player.get("world_ready")):
			break
		await process_frame
	for _i in 120:
		await physics_frame
	var ws = WorldSettings.get_active()
	var L: float = ws.layer_height()
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var feet: Vector3 = player.global_position
	var to_cam := Vector2(cam.global_position.x - feet.x, cam.global_position.z - feet.z).normalized()
	var fwd := Vector2i(roundi(to_cam.x), roundi(to_cam.y))
	var pc: Vector2i = _Nav.column_pos(feet)
	var walls := {"front": [], "behind": []}
	for side in [1, -1]:
		var perp := Vector2i(-fwd.y, fwd.x)
		for k in range(-2, 3):
			var c: Vector2i = pc + fwd * side + perp * k
			for _n in 3:
				_TerrainEdits.build_wall(c.x, c.y, _VoxelTypes.STONE)
			walls["front" if side == 1 else "behind"].append(c)
	for _f in 30:
		await physics_frame
	feet = player.global_position
	var campos: Vector3 = cam.global_position
	var result := ""
	for key in ["front", "behind"]:
		var covering := 0
		for c in walls[key]:
			for layer in 3:
				var center: Vector3 = _Coords.column_to_world_pos(float(c.x) + 0.5, feet.y + (float(layer) + 0.5) * L, float(c.y) + 0.5)
				var box := AABB(center - Vector3(L, L, L) * 0.5, Vector3(L, L, L))
				var clear_y: float = feet.y + _Cut.FEET_CLEAR
				var low := AABB(box.position, Vector3(L, clampf(clear_y - box.position.y, 0.0, L), L))
				var cut: bool = _Cut.contains(center, feet, campos, _Cut.RADIUS_AT_PLAYER, _Cut.FEET_CLEAR, _Cut.PAST_DISTANCE)
				var hit := false
				for s in 5:
					var body_pt: Vector3 = feet + Vector3(0, L * (0.15 + 0.3 * s), 0)
					if not cut and box.intersects_segment(campos, body_pt) != null:
						hit = true
					if low.size.y > 0.0 and low.intersects_segment(campos, body_pt) != null:
						hit = true
				if hit:
					covering += 1
		result += " %s_covering_voxels=%d" % [key, covering]
	print("P5_OCCLUDE voxel=%.2f feet_clear=%.2f%s" % [L, _Cut.FEET_CLEAR, result])
	quit()
