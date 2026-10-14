extends SceneTree
## Headless: bow and melee must aim at the cursor column the pick uses.
## The old melee check calls _do_melee_attack with the mouse off-screen, so the
## swing falls back to the camera and never sees an off-axis cursor. The bow
## never read the mouse at all. The root window's get_mouse_position stays at
## the corner under --headless (no mouse feature). A SubViewport reports the
## motion pushed into it, which is the position the same pick reads in game.
## This check pushes that cursor, lets the real highlight publish the column,
## and presses the attack action.
## Usage: godot --headless --path 0.2.8 -s res://scripts/verify_cursor_aim.gd

const _ActionTargeting = preload("res://player/action_targeting.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

var _failed: int = 0


class _Host extends Player:
	func _ready() -> void:
		pass


class _Dummy extends Node3D:
	var hits: int = 0

	func take_damage(_amount: float, _source: StringName = &"") -> void:
		hits += 1

	func is_combat_alive() -> bool:
		return true


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)


func _run() -> void:
	# Root get_mouse_position ignores push_input. A bare SubViewport does not.
	var view := SubViewport.new()
	view.name = "AimView"
	view.size = Vector2i(1280, 720)
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(view)
	var ws = _WorldSettings.get_active()
	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 5
	world.name = "World"
	world.add_to_group("world")
	view.add_child(world)

	var player := _Host.new()
	player.name = "Player"
	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	player.add_child(mesh)
	player.set_process(false)
	player.set_physics_process(false)
	var col := Vector3(20.5, 8.0, 20.5)
	player.voxel_position = col
	var inv := Inventory.new()
	inv.set_slot(0, "wooden_sword", 1)
	inv.set_slot(1, "shortbow", 1)
	inv.set_slot(2, "stone_pick", 1)
	player.inventory = inv
	player.world = world
	view.add_child(player)
	player.global_position = Vector3(ws.column_to_world(col.x), 8.0, ws.column_to_world(col.z))

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 16.0
	cam.current = true
	view.add_child(cam)
	var yaw := deg_to_rad(45.0)
	var hdist := 100.0 * sqrt(2.0)
	cam.global_position = player.global_position + Vector3(sin(yaw) * hdist, 101.0, cos(yaw) * hdist)
	cam.rotation_degrees = Vector3(-35.264, 45.0, 0.0)
	player.camera = cam

	var weapon := WeaponController.new()
	weapon.name = "WeaponController"
	weapon.set_process(false)
	player.add_child(weapon)
	var highlight := TargetHighlight.new()
	highlight.name = "TargetHighlight"
	highlight.set_process(false)
	player.add_child(highlight)
	await process_frame
	await process_frame

	var forward := _ActionTargeting.attack_forward(player)
	var side := Vector3(-forward.z, 0.0, forward.x)
	if side.length_squared() < 0.01:
		_fail("camera forward has no side axis")
		_finish()
		return
	side = side.normalized()
	# Two columns off the camera axis, inside the sword reach (2.8).
	var aim_voxel := Vector3(col.x + side.x * 2.0, col.y, col.z + side.z * 2.0)
	var aim_world := Vector3(
		ws.column_to_world(aim_voxel.x),
		player.global_position.y,
		ws.column_to_world(aim_voxel.z)
	)
	var screen := cam.unproject_position(aim_world)
	var rect := view.get_visible_rect()
	if screen.x < rect.position.x or screen.y < rect.position.y or screen.x > rect.end.x or screen.y > rect.end.y:
		_fail("off-axis column did not land on screen %s rect %s" % [screen, rect])
		_finish()
		return
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	view.push_input(motion, true)
	var mouse := view.get_mouse_position()
	highlight._process(0.016)
	var shared: Vector3 = highlight.get_action_column()
	if mouse.distance_to(screen) > 2.0:
		_fail("viewport mouse %s did not follow the cursor warp %s" % [mouse, screen])
		_finish()
		return
	var want_cell := Vector2i(floori(aim_voxel.x), floori(aim_voxel.z))
	var fwd_cell := Vector2i(floori(col.x + forward.x * 2.0), floori(col.z + forward.z * 2.0))
	if shared == Vector3.ZERO:
		_fail("highlight did not publish the cursor column")
		_finish()
		return
	var got := Vector2i(floori(shared.x), floori(shared.z))
	if got.distance_to(want_cell) > 1:
		_fail("cursor column %s is not the off-axis cell %s (camera cell %s)" % [got, want_cell, fwd_cell])
		_finish()
		return
	if got.distance_to(fwd_cell) <= got.distance_to(want_cell):
		_fail("cursor column %s is still the camera-forward cell %s" % [got, fwd_cell])
		_finish()
		return
	print("OK cursor column %s is off the camera cell %s" % [got, fwd_cell])

	var chest_y := weapon._attack_origin(0.5).y
	var on_cursor := _dummy(view, ws, got, chest_y, "OnCursor")
	var on_camera := _dummy(view, ws, fwd_cell, chest_y, "OnCamera")

	weapon.set_active_hotbar_index(0)
	weapon._cooldown_timer = 0.0
	_press_attack(weapon, 0.45)
	if on_cursor.hits < 1:
		_fail("sword attack missed the cursor dummy (hits %d) and hit the camera dummy %d" % [on_cursor.hits, on_camera.hits])
	elif on_camera.hits > 0:
		_fail("sword attack also hit the camera-axis dummy")
	else:
		print("OK sword hit the cursor dummy only")
	_face_matches(player, got, "sword")

	on_cursor.hits = 0
	on_camera.hits = 0
	weapon._cancel_pending_strike()
	weapon._cooldown_timer = 0.0
	weapon.set_active_hotbar_index(1)
	weapon._process(0.016)
	_face_matches(player, got, "bow")
	_line_matches(player, got, "bow")
	_press_attack(weapon, 0.9)
	var arrow := _live_arrow(weapon)
	if arrow == null:
		_fail("bow attack did not launch an arrow")
	else:
		var vel := Vector3(arrow.velocity.x, 0.0, arrow.velocity.z)
		if vel.length_squared() < 0.01:
			_fail("arrow velocity has no horizontal aim")
		else:
			vel = vel.normalized()
			var want := _flat_toward(player, got)
			var cam_dot := vel.dot(forward)
			var aim_dot := vel.dot(want)
			if aim_dot < 0.85 or cam_dot > 0.45:
				_fail("arrow flies along the camera (aim %.2f camera %.2f), not the cursor" % [aim_dot, cam_dot])
			else:
				print("OK arrow aim %.2f camera %.2f" % [aim_dot, cam_dot])

	_finish()


func _dummy(parent: Node, ws, cell: Vector2i, chest_y: float, node_name: String) -> _Dummy:
	var body := _Dummy.new()
	body.name = node_name
	body.add_to_group("crystal_enemy")
	parent.add_child(body)
	body.global_position = Vector3(
		ws.column_to_world(float(cell.x) + 0.5),
		chest_y,
		ws.column_to_world(float(cell.y) + 0.5)
	)
	return body


func _flat_toward(player: Player, cell: Vector2i) -> Vector3:
	var offset := Vector3(
		float(cell.x) + 0.5 - player.voxel_position.x,
		0.0,
		float(cell.y) + 0.5 - player.voxel_position.z
	)
	return offset.normalized()


func _face_matches(player: Player, cell: Vector2i, label: String) -> void:
	var held := player.get_node_or_null("HeldItemView") as Node3D
	if held == null:
		_fail("%s has no held item to aim" % label)
		return
	var flat := -held.global_transform.basis.z
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		_fail("%s held item has no facing" % label)
		return
	flat = flat.normalized()
	var want := _flat_toward(player, cell)
	var cam := _ActionTargeting.attack_forward(player)
	if flat.dot(want) < 0.85 or flat.dot(cam) > 0.45:
		_fail("%s points along the camera (aim %.2f camera %.2f)" % [label, flat.dot(want), flat.dot(cam)])
	else:
		print("OK %s faces the cursor" % label)


func _line_matches(player: Player, cell: Vector2i, label: String) -> void:
	var line := player.get_node_or_null("AimIndicator/AimLine") as Node3D
	if line == null or not line.visible:
		_fail("%s aim line is hidden" % label)
		return
	var flat := -line.global_transform.basis.z
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		_fail("%s aim line has no direction" % label)
		return
	flat = flat.normalized()
	var want := _flat_toward(player, cell)
	if flat.dot(want) < 0.85:
		_fail("%s aim line is not the cursor (%.2f)" % [label, flat.dot(want)])
	else:
		print("OK %s aim line follows the cursor" % label)


func _press_attack(weapon: WeaponController, seconds: float) -> void:
	Input.action_release("attack")
	Input.action_press("attack")
	weapon._process(0.016)
	Input.action_release("attack")
	var left := seconds
	while left > 0.0:
		var step := minf(0.05, left)
		weapon._process(step)
		left -= step


func _live_arrow(weapon: Node) -> Node3D:
	for child in weapon.get_children():
		if child is Projectile and (child as Projectile).active:
			return child
	return null


func _finish() -> void:
	if _failed == 0:
		print("All cursor aim tests OK")
		quit(0)
	else:
		push_error("verify_cursor_aim: %d failure(s)" % _failed)
		quit(1)
