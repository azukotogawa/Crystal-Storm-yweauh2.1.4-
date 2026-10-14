extends SceneTree
## Headless: bow, sword, and the crystal hammer must aim at the cursor column
## the pick uses. The old melee check calls _do_melee_attack with the mouse
## off-screen, so the swing falls back to the camera. The bow never read the
## mouse. The 2a cursor sat about two columns off axis, inside the hammer's
## 2.2 hit range, so a hammer that ignores a farther cursor and slams along
## the camera still passed. The root window's get_mouse_position stays at the
## corner under --headless. A SubViewport reports the motion pushed into it,
## which is the position the pick reads in game. This check pushes that
## cursor, lets the real highlight publish the column, and presses attack.
## The hammer press waits through the 0.62 wind-up of the 1.1 s swing.
## Usage: godot --headless --path 0.2.8 -s res://scripts/verify_cursor_aim.gd

const _ActionTargeting = preload("res://player/action_targeting.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")

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
	inv.set_slot(3, "crystal_hammer", 1)
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

	_check_hammer(view, player, weapon, highlight, cam, ws, col, side, forward)
	_finish()


## Cursor sits past the hammer's 2.2 hit range and inside the pick's reach.
## The slam still has to face that cursor, and the body on the cursor ray
## (inside the hit range) is the one that gets hit after the wind-up.
func _check_hammer(
	view: SubViewport,
	player: Player,
	weapon: WeaponController,
	highlight: TargetHighlight,
	cam: Camera3D,
	ws,
	col: Vector3,
	side: Vector3,
	camera_forward: Vector3
) -> void:
	var hammer_range := 2.2
	var far := 3.6
	var aim_voxel := Vector3(col.x + side.x * far, col.y, col.z + side.z * far)
	var aim_world := Vector3(
		ws.column_to_world(aim_voxel.x),
		player.global_position.y,
		ws.column_to_world(aim_voxel.z)
	)
	var screen := cam.unproject_position(aim_world)
	var rect := view.get_visible_rect()
	if screen.x < rect.position.x or screen.y < rect.position.y or screen.x > rect.end.x or screen.y > rect.end.y:
		_fail("hammer cursor did not land on screen %s" % screen)
		return
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	view.push_input(motion, true)
	highlight._process(0.016)
	var shared: Vector3 = highlight.get_action_column()
	if shared == Vector3.ZERO:
		_fail("hammer highlight did not publish the far cursor")
		return
	# The pitched iso ray does not land on the column the point was built from.
	# The highlight column is the one the pick uses, so the swing is judged
	# against that cell.
	var got := Vector2i(floori(shared.x), floori(shared.z))
	var cursor_delta := Vector2(float(got.x) + 0.5 - col.x, float(got.y) + 0.5 - col.z)
	var cursor_dist := cursor_delta.length()
	var cam_cell_far := Vector2i(
		floori(col.x + camera_forward.x * far),
		floori(col.z + camera_forward.z * far)
	)
	if cursor_dist <= hammer_range + 0.05 or cursor_dist > 8.0:
		_fail("hammer cursor dist %.2f should be outside 2.2 and inside the pick reach" % cursor_dist)
		return
	if got.distance_to(cam_cell_far) <= 1:
		_fail("hammer cursor %s is still the camera cell %s" % [got, cam_cell_far])
		return
	print("OK hammer cursor %s dist %.2f is past the hit range" % [got, cursor_dist])

	for old_name in ["OnCursor", "OnCamera"]:
		var old := view.get_node_or_null(old_name) as Node3D
		if old:
			old.global_position = Vector3(0.0, -400.0, 0.0)
	var near := 1.4
	var ray := cursor_delta / cursor_dist
	var hit_cell := Vector2i(
		floori(col.x + ray.x * near),
		floori(col.z + ray.y * near)
	)
	var cam_cell := Vector2i(
		floori(col.x + camera_forward.x * near),
		floori(col.z + camera_forward.z * near)
	)
	var chest_y := weapon._attack_origin(0.45).y
	var on_cursor := _dummy(view, ws, hit_cell, chest_y, "HammerCursor")
	var on_camera := _dummy(view, ws, cam_cell, chest_y, "HammerCamera")

	var def := _ItemTypes.get_def("crystal_hammer")
	if not is_equal_approx(float(def.get("impact_ratio", -1.0)), 0.62):
		_fail("hammer impact_ratio drifted from 0.62")
	if not is_equal_approx(float(def.get("anim_duration", -1.0)), 1.1):
		_fail("hammer anim_duration drifted from 1.1")
	var windup := 1.1 * 0.62

	weapon._cancel_pending_strike()
	weapon._cooldown_timer = 0.0
	weapon.set_active_hotbar_index(3)
	weapon._process(0.016)
	_face_matches(player, got, "hammer ready")
	_reticle_matches(player, got, camera_forward, "hammer")

	var hit_at := -1.0
	var elapsed := 0.0
	var faced_windup := false
	var strikes: Array[Vector3] = []
	weapon.attacked.connect(func(item_id: String, hit_pos: Vector3) -> void:
		if item_id == "crystal_hammer":
			strikes.append(hit_pos)
	)
	Input.action_release("attack")
	Input.action_press("attack")
	weapon._process(0.016)
	Input.action_release("attack")
	elapsed = 0.016
	while elapsed < 1.2:
		var step := 0.05
		var before := on_cursor.hits + on_camera.hits
		weapon._process(step)
		elapsed += step
		if not faced_windup and elapsed >= 0.30 and elapsed + 0.001 < windup:
			_face_matches(player, got, "hammer wind-up")
			faced_windup = true
		if before == 0 and on_cursor.hits + on_camera.hits > 0 and hit_at < 0.0:
			hit_at = elapsed
			break
	if not faced_windup:
		_fail("hammer wind-up facing was not sampled before impact")
	if hit_at < 0.0:
		_fail("hammer swing did not hit either dummy")
	elif hit_at + 0.001 < windup - 0.05:
		_fail("hammer hit at %.3f s, before the 0.62 wind-up" % hit_at)
	elif on_cursor.hits < 1:
		_fail("hammer hit the camera dummy (%d) and missed the cursor ray (%d) at %.3f s" % [on_camera.hits, on_cursor.hits, hit_at])
	elif on_camera.hits > 0:
		_fail("hammer also hit the camera-axis dummy")
	else:
		print("OK hammer hit the cursor ray at %.3f s (wind-up %.3f)" % [hit_at, windup])
	var strike_pos := strikes[0] if strikes.size() > 0 else Vector3.INF
	_marker_matches(player, strike_pos, got, camera_forward)


func _marker_matches(player: Player, strike_pos: Vector3, cell: Vector2i, camera_forward: Vector3) -> void:
	# attacked() is the splash marker. It has to lie toward the cursor, not
	# on the camera-forward cell the 2.2 range gate used to pick.
	if strike_pos == Vector3.INF:
		_fail("hammer swing did not publish a strike")
		return
	var flat := strike_pos - player.global_position
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		_fail("hammer strike sits on the player")
		return
	flat = flat.normalized()
	var want := _flat_toward(player, cell)
	if flat.dot(want) < 0.85 or flat.dot(camera_forward) > 0.45:
		_fail("hammer strike follows the camera (aim %.2f camera %.2f)" % [flat.dot(want), flat.dot(camera_forward)])
	else:
		print("OK hammer strike follows the cursor")


func _reticle_matches(player: Player, cell: Vector2i, camera_forward: Vector3, label: String) -> void:
	var ring := player.get_node_or_null("AimIndicator/MeleeReticle") as Node3D
	if ring == null or not ring.visible:
		_fail("%s reticle is hidden" % label)
		return
	var flat := ring.global_position - player.global_position
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		_fail("%s reticle sits on the player" % label)
		return
	flat = flat.normalized()
	var want := _flat_toward(player, cell)
	if flat.dot(want) < 0.85 or flat.dot(camera_forward) > 0.45:
		_fail("%s reticle follows the camera (aim %.2f camera %.2f)" % [label, flat.dot(want), flat.dot(camera_forward)])
	else:
		print("OK %s reticle follows the cursor" % label)


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
