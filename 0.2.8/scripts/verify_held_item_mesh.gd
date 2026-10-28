extends SceneTree
## readable at the game camera (ortho 16) and actually drawn.

const _WorldSettings = preload("res://config/world_settings.gd")

const ITEMS: Array[String] = ["wooden_sword", "spear", "stone_pick", "crystal_hammer", "shortbow"]
const CLEAR := Color(1.0, 0.0, 1.0)

var _failed: int = 0


class _Host extends Player:
	func _ready() -> void:
		pass


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)
	print("FAIL " + msg)


func _run() -> void:
	var headless := DisplayServer.get_name() == "headless"
	if not headless:
		DisplayServer.window_set_size(Vector2i(480, 360))
		DisplayServer.window_set_title("Crystal Storm held-item probe")
	var ws = _WorldSettings.get_active()
	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 5
	world.name = "World"
	world.add_to_group("world")
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = CLEAR
	var env_node := WorldEnvironment.new()
	env_node.environment = env
	root.add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.look_at_from_position(Vector3.ZERO, -Vector3(0.55, 0.82, 0.38), Vector3.UP)
	root.add_child(sun)

	var player := _Host.new()
	player.name = "Player"
	var body := MeshInstance3D.new()
	body.name = "MeshInstance3D"
	player.add_child(body)
	player.set_process(false)
	player.set_physics_process(false)
	var col := Vector3(20.5, 8.0, 20.5)
	player.voxel_position = col
	var inv := Inventory.new()
	for i in ITEMS.size():
		inv.set_slot(i, ITEMS[i], 1)
	player.inventory = inv
	player.world = world
	root.add_child(player)
	player.global_position = Vector3(ws.column_to_world(col.x), 8.0, ws.column_to_world(col.z))

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 16.0
	cam.current = true
	root.add_child(cam)
	player.camera = cam

	var weapon := WeaponController.new()
	weapon.name = "WeaponController"
	weapon.set_process(false)
	player.add_child(weapon)
	await process_frame
	await process_frame
	var view := player.get_node_or_null("HeldItemView")
	if view == null:
		_fail("WeaponController did not attach HeldItemView")
		_finish()
		return

	for i in ITEMS.size():
		var item_id := ITEMS[i]
		weapon._playback = null
		weapon._shown_item = ""
		weapon.set_active_hotbar_index(i)
		weapon._process(0.016)
		var held := view._item as Node3D
		if held == null:
			_fail("%s has no HeldItem after hotbar select" % item_id)
			continue
		if held is SpriteBase3D or _mesh_count(held) < 1:
			var drawn := -1
			if not headless:
				_hide_extras(view, player)
				_frame(cam, held)
				drawn = await _read_pixels()
			_fail("%s is a flat sprite in the hand (render pixels %d). The animation check measured Sprite3D pixel_size and never read this camera." % [item_id, drawn])
			continue
		var bounds := _local_bounds(held)
		var thin := minf(bounds.size.x, bounds.size.z)
		if bounds.size.y < ws.player_height() * 0.85:
			_fail("%s mesh height %.2f is below the body %.2f" % [item_id, bounds.size.y, ws.player_height()])
		elif thin < ws.voxel_scale * 0.12:
			_fail("%s mesh is a flat card (thickness %.3f)" % [item_id, thin])
		_hide_extras(view, player)
		_frame(cam, held)
		if headless:
			print("RENDER %s headless (no framebuffer) height %.2f thick %.2f" % [item_id, bounds.size.y, thin])
			continue
		var pixels := await _read_pixels()
		var img := root.get_texture().get_image() if root.get_texture() else null
		var screen_h := _screen_height(cam, held)
		if img == null or img.is_empty():
			_fail("%s window framebuffer is empty" % item_id)
		elif pixels < 150:
			_fail("%s mesh is not visible in the ortho-16 render (%d pixels)" % [item_id, pixels])
		elif screen_h < 48.0:
			_fail("%s reads small at ortho 16 (screen height %.0f px)" % [item_id, screen_h])
		else:
			print("RENDER %s pixels %d screen_h %.0f mesh %.2f x %.2f x %.2f" % [item_id, pixels, screen_h, bounds.size.x, bounds.size.y, bounds.size.z])
	_finish()


func _hide_extras(view: Node, player: Node) -> void:
	var arm := view.get_node_or_null("Arm") as Node3D
	if arm:
		arm.visible = false
	var aim := player.get_node_or_null("AimIndicator") as Node3D
	if aim:
		aim.visible = false
	var body := player.get_node_or_null("MeshInstance3D") as Node3D
	if body:
		body.visible = false


func _read_pixels() -> int:
	for _i in 3:
		await process_frame
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw(false)
	await RenderingServer.frame_post_draw
	var tex: Texture2D = root.get_texture()
	return _opaque_count(tex.get_image() if tex else null)


func _frame(cam: Camera3D, held: Node3D) -> void:
	var ab := _world_bounds(held)
	var focus := held.global_position
	if ab.size.length_squared() > 0.01:
		focus = ab.get_center()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 16.0
	cam.rotation_degrees = Vector3(-35.264, 45.0, 0.0)
	cam.global_position = focus + cam.global_transform.basis.z * 40.0


func _opaque_count(img: Image) -> int:
	if img == null or img.is_empty():
		return 0
	var n := 0
	var step := 2
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var c := img.get_pixel(x, y)
			var d := Vector3(c.r - CLEAR.r, c.g - CLEAR.g, c.b - CLEAR.b).length()
			if d > 0.35 and c.a > 0.2:
				n += 1
	return n * step * step


func _screen_height(cam: Camera3D, held: Node3D) -> float:
	var ab := _world_bounds(held)
	var min_y := 1.0e9
	var max_y := -1.0e9
	for corner in _corners(ab):
		if cam.is_position_behind(corner):
			continue
		var p := cam.unproject_position(corner)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	if max_y < min_y:
		return 0.0
	return max_y - min_y


func _mesh_count(node: Node) -> int:
	var n := 0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null and node.visible:
		n += 1
	for child in node.get_children():
		n += _mesh_count(child)
	return n


func _local_bounds(item: Node3D) -> AABB:
	return _bounds(item, item)


func _world_bounds(item: Node3D) -> AABB:
	return _bounds(item, null)


func _bounds(item: Node3D, space: Node3D) -> AABB:
	var merged := AABB()
	var any := false
	var pending: Array[Node] = [item]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			pending.append(child)
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.mesh == null or not mi.visible:
				continue
			var xf := mi.global_transform
			if space != null:
				xf = space.global_transform.affine_inverse() * xf
			var ab := mi.get_aabb()
			for corner in _corners(ab):
				var p: Vector3 = xf * corner
				if not any:
					merged = AABB(p, Vector3.ZERO)
					any = true
				else:
					merged = merged.expand(p)
	return merged


func _corners(ab: AABB) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in 8:
		out.append(ab.position + Vector3(
			ab.size.x if (i & 1) != 0 else 0.0,
			ab.size.y if (i & 2) != 0 else 0.0,
			ab.size.z if (i & 4) != 0 else 0.0
		))
	return out


func _finish() -> void:
	if _failed > 0:
		quit(1)
	else:
		print("All held item mesh tests OK")
		quit(0)
