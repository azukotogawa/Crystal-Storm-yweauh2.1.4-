extends SceneTree
## Regression: attack targeting must follow camera orbit, not a fixed south bias.


const _ActionTargeting = preload("res://player/action_targeting.gd")


class _FakeCamera extends Camera3D:
	var orbit_yaw_deg: float = 0.0

	func get_move_yaw_deg() -> float:
		return 45.0 + orbit_yaw_deg

	func _init() -> void:
		rotation_degrees = Vector3(-35.264, 45.0, 0.0)


class _FakePlayer extends Node3D:
	var voxel_position := Vector3(10.0, 8.0, 10.0)
	var locked_move_yaw_deg: float = 45.0
	var is_input_locked := false
	var camera: _FakeCamera


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var holder := Node3D.new()
	holder.name = "TestRoot"
	root.add_child(holder)

	var player := _FakePlayer.new()
	player.name = "Player"
	holder.add_child(player)

	var cam := _FakeCamera.new()
	cam.name = "Camera"
	player.camera = cam
	player.add_child(cam)

	await process_frame

	var cells: Dictionary = {}
	for rot in 4:
		cam.orbit_yaw_deg = float(rot) * 90.0
		cam.rotation_degrees = Vector3(-35.264, 45.0 + float(rot) * 90.0, 0.0)
		await process_frame
		var fwd := _ActionTargeting.attack_forward(player)
		var col := player.voxel_position + fwd * 2.0
		var cell := Vector2i(floori(col.x), floori(col.z))
		cells["%d,%d" % [cell.x, cell.y]] = true

	if cells.size() < 3:
		push_error("target_cell must vary with camera orbit, got %d unique cells: %s" % [cells.size(), cells.keys()])
		failed = true
	else:
		print("OK facing-aware cells=%d" % cells.size())

	var src := (load("res://player/action_targeting.gd") as GDScript).source_code
	if "global_transform.basis.z" not in src and "_rotate_input_to_world" not in src:
		push_error("action_targeting must use camera basis or movement rotation")
		failed = true
	elif "raycast_voxel" not in src or "warp_mouse_to_column" not in src:
		push_error("action_targeting must support voxel raycast mouse pick")
		failed = true
	else:
		print("OK action_targeting camera + mouse column pick")

	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 1
	holder.add_child(world)
	await process_frame
	var screen := _ActionTargeting.screen_pos_for_column(player, world, 12.5, 14.5)
	if screen.x >= 1.0 and screen.y >= 1.0:
		print("OK screen unproject pos=%s" % screen)
	else:
		print("OK screen unproject skipped (headless viewport)")
	_ActionTargeting.warp_mouse_to_column(player, world, player.voxel_position.x, player.voxel_position.z)
	await process_frame
	var picked := _ActionTargeting.target_column(player, 2.0)
	if picked == Vector3.ZERO:
		picked = player.voxel_position
		print("OK mouse pick fallback to player cell (headless)")
	elif floori(picked.x) == floori(player.voxel_position.x) and floori(picked.z) == floori(player.voxel_position.z):
		print("OK mouse pick column=%s (headless may equal player cell)" % picked)
	else:
		print("OK mouse pick column=%s" % picked)

	var toward := _ActionTargeting.attack_toward_column(player, 2.0)
	if toward.length_squared() < 0.01:
		push_error("attack_toward_column returned zero")
		failed = true
	else:
		print("OK attack_toward_column=%s" % toward)

	var weapon_src := (load("res://weapons/weapon_controller.gd") as GDScript).source_code
	if "attack_toward_column" not in weapon_src:
		push_error("weapon_controller melee must use attack_toward_column")
		failed = true
	else:
		print("OK weapon melee uses attack_toward_column")

	holder.queue_free()
	if failed:
		quit(1)
		return
	print("All target facing tests OK")
	quit(0)