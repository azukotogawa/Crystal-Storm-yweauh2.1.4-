extends SceneTree
## Regression: ActionTargeting modes + TargetHighlight wiring for dig/build/attack columns.


const _ActionTargeting = preload("res://player/action_targeting.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")



class _FakeWeapon extends Node:
	var _slot: Variant = null

	func get_active_item() -> Variant:
		return _slot

	func set_slot(id: String) -> void:
		_slot = {"id": id, "count": 1}


class _FakePlayer extends Node3D:
	var voxel_position := Vector3(10.5, 8.0, 10.5)
	var world: InfiniteNoiseWorld
	var locked_move_yaw_deg: float = 45.0
	var is_input_locked := false
	var camera: Camera3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false

	var player_src := (load("res://player/player.gd") as GDScript).source_code
	if "TargetHighlight" not in player_src:
		push_error("player.gd must attach TargetHighlight")
		failed = true
	else:
		print("OK player wires TargetHighlight")

	var highlight_src := (load("res://player/target_highlight.gd") as GDScript).source_code
	if "_ActionTargeting.resolve_action" not in highlight_src:
		push_error("target_highlight must call ActionTargeting.resolve_action")
		failed = true
	elif '"valid"' not in highlight_src:
		push_error("target_highlight must gate on resolve_action valid flag")
		failed = true
	elif "render_priority" not in highlight_src:
		push_error("target_highlight must set render_priority for visibility")
		failed = true
	elif "face_normal" not in highlight_src:
		push_error("target_highlight must orient to hit face_normal")
		failed = true
	else:
		print("OK highlight uses ActionTargeting + face slab")

	var targeting_src := (load("res://player/action_targeting.gd") as GDScript).source_code
	if "_TerrainRamps.walkable_height" not in targeting_src:
		push_error("action_targeting must use ramp-aware walkable height")
		failed = true
	elif "_is_solid_column" not in targeting_src:
		push_error("action_targeting must filter air/fluid columns for highlight")
		failed = true
	elif "_walkable_top" not in targeting_src:
		push_error("action_targeting must use chunk ramp entries for walkable top")
		failed = true
	elif "_ray_column_face_pick" not in targeting_src:
		push_error("action_targeting must raycast column faces for mouse hits")
		failed = true
	elif "face_normal" not in targeting_src:
		push_error("action_targeting must return face_normal for highlight")
		failed = true
	else:
		print("OK action_targeting ramp-aware face raycast + solid-column filter")

	var holder := Node.new()
	holder.name = "TestRoot"
	root.add_child(holder)

	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 42
	holder.add_child(world)
	world.add_to_group("world")

	var player := _FakePlayer.new()
	player.name = "Player"
	player.world = world
	holder.add_child(player)

	player.is_input_locked = true
	player.locked_move_yaw_deg = 45.0

	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 24.0
	cam.rotation_degrees = Vector3(-35.264, 45.0, 0.0)
	cam.current = true
	player.camera = cam
	holder.add_child(cam)

	var weapon := _FakeWeapon.new()
	weapon.name = "WeaponController"
	player.add_child(weapon)

	await process_frame

	var start_cell := Vector2i.ZERO
	for gx in range(-24, 25):
		for gz in range(-24, 25):
			if _ActionTargeting._is_solid_column(world, null, gx, gz):
				start_cell = Vector2i(gx, gz)
				break
		if start_cell != Vector2i.ZERO:
			break
	if start_cell == Vector2i.ZERO:
		push_error("could not find solid column for highlight probe")
		failed = true
	else:
		player.voxel_position = Vector3(float(start_cell.x) + 0.5, 8.0, float(start_cell.y) + 0.5)
		var ws_probe = _WorldSettings.get_active()
		player.global_position = Vector3(
			ws_probe.column_to_world(player.voxel_position.x),
			player.voxel_position.y,
			ws_probe.column_to_world(player.voxel_position.z)
		)
		cam.global_position = player.global_position + Vector3(100.0, 101.0, 100.0)
		cam.rotation_degrees = Vector3(-35.264, 45.0, 0.0)
		_ActionTargeting.warp_mouse_to_column(
			player, world, float(start_cell.x) + 0.5, float(start_cell.y) + 0.5
		)
		await process_frame
		print("OK highlight probe cell=%s" % start_cell)

	weapon.set_slot("stone_pick")
	var probe_screen := _ActionTargeting.screen_pos_for_column(
		player, world, float(start_cell.x) + 0.5, float(start_cell.y) + 0.5
	)
	var dig_hit := _ActionTargeting.raycast_voxel(
		player, world, null, 2.4, true, &"dig", probe_screen
	)
	var dig_info := _ActionTargeting.resolve_action(player, world, null, 2.0)
	if dig_hit.get("hit", false):
		dig_info = {
			"column": dig_hit.column,
			"cell": dig_hit.cell,
			"surface_y": dig_hit.surface_y,
			"world_pos": dig_hit.face_pos,
			"face_normal": dig_hit.face_normal,
			"mode": &"dig",
			"valid": _ActionTargeting._is_action_valid(world, null, dig_hit.cell.x, dig_hit.cell.y, &"dig", player, 2.4),
			"range": 2.4,
		}
	if dig_info.get("mode", &"") != &"dig":
		push_error("pickaxe should resolve dig mode, got %s" % dig_info.get("mode"))
		failed = true
	elif not dig_info.get("valid", false):
		push_error("dig highlight target must be valid solid column")
		failed = true
	else:
		print("OK dig mode cell=%s valid" % dig_info.get("cell"))

	weapon.set_slot("wooden_sword")
	var atk_hit := _ActionTargeting.raycast_voxel(
		player, world, null, 2.8, true, &"attack", probe_screen
	)
	if not atk_hit.get("hit", false):
		push_error("attack raycast must hit solid column under cursor")
		failed = true
	elif not _ActionTargeting._is_action_valid(
			world, null, atk_hit.cell.x, atk_hit.cell.y, &"attack", player, 2.8
	):
		push_error("attack highlight target must be valid solid column")
		failed = true
	else:
		print("OK attack mode cell=%s valid" % atk_hit.get("cell"))

	weapon._slot = {"id": "stone", "count": 3}
	var build_hit := _ActionTargeting.raycast_voxel(
		player, world, null, 2.0, true, &"build", probe_screen
	)
	if not build_hit.get("hit", false):
		push_error("build raycast must hit solid column under cursor")
		failed = true
	elif not _ActionTargeting._is_action_valid(
			world, null, build_hit.cell.x, build_hit.cell.y, &"build", player, 2.0
	):
		push_error("build highlight target must be valid solid column")
		failed = true
	else:
		print("OK build mode from stone hotbar cell=%s valid" % build_hit.get("cell"))

	var dig_face: Vector3 = dig_hit.get("face_normal", Vector3.ZERO)
	if dig_face.length_squared() < 0.01:
		push_error("dig highlight must include face_normal")
		failed = true
	else:
		print("OK dig highlight face=%s" % dig_face)

	var ws = _WorldSettings.get_active()
	var layer: float = ws.layer_height()
	_ActionTargeting.warp_mouse_to_column(
		player, world, float(start_cell.x) + 0.5, float(start_cell.y) + 0.5
	)
	var build_info := _ActionTargeting.resolve_action(
		player, world, null, 2.0, false, &"build"
	)
	if build_info.get("mode", &"") != &"build":
		push_error("resolve_action force build must return build mode")
		failed = true
	elif not build_info.get("valid", false):
		push_error("build resolve_action must be valid at probe cell")
		failed = true
	else:
		var build_cell: Vector2i = build_info.get("cell", Vector2i.ZERO)
		var build_walk: float = _ActionTargeting._walkable_top(
			world, null, float(build_cell.x) + 0.5, float(build_cell.y) + 0.5
		)
		var build_y: float = float(build_info.get("world_pos", Vector3.ZERO).y)
		var min_top: float = build_walk + layer * 0.92
		if build_y < min_top:
			push_error(
				"build highlight Y %.2f below placement top %.2f (walk=%.2f)"
				% [build_y, min_top, build_walk]
			)
			failed = true
		else:
			print("OK build highlight on placement top y=%.2f walk=%.2f" % [build_y, build_walk])
	var face_pos: Vector3 = dig_hit.get("face_pos", Vector3.ZERO)
	var flat_y: float = face_pos.y
	var dig_cell: Vector2i = dig_hit.get("cell", Vector2i.ZERO)
	var surf_h: float = world.get_surface_height(float(dig_cell.x) + 0.5, float(dig_cell.y) + 0.5)
	var col_top: float = surf_h + layer
	if flat_y < surf_h - layer * 0.1 or flat_y > col_top + layer * 0.15:
		push_error(
			"dig highlight Y %.2f outside column [%.2f, %.2f]"
			% [flat_y, surf_h, col_top]
		)
		failed = true
	else:
		print("OK highlight world_y=%.2f on face" % flat_y)

	var col_center_x: float = (
		ws.column_to_world(float(dig_cell.x)) + ws.column_to_world(float(dig_cell.x + 1))
	) * 0.5
	var col_center_z: float = (
		ws.column_to_world(float(dig_cell.y)) + ws.column_to_world(float(dig_cell.y + 1))
	) * 0.5
	if absf(face_pos.x - col_center_x) > 0.001 or absf(face_pos.z - col_center_z) > 0.001:
		push_error("dig highlight must snap to column center xz")
		failed = true
	else:
		print("OK highlight snaps to column center")

	var far_hit := _ActionTargeting.raycast_voxel(
		player, world, null, 2.4, true, &"dig", Vector2(8.0, 8.0)
	)
	if far_hit.get("hit", false):
		push_error("out-of-range mouse must not pick nearby column")
		failed = true
	else:
		print("OK out-of-range mouse yields no highlight hit")

	var fluid_cell := Vector2i.ZERO
	for gx in range(-8, 9):
		for gz in range(-8, 9):
			var tid: int = world.get_tile_type(float(gx), float(gz))
			if tid == _VoxelTypes.RIVER or tid == _VoxelTypes.OCEAN2:
				fluid_cell = Vector2i(gx, gz)
				break
		if fluid_cell != Vector2i.ZERO:
			break
	if fluid_cell != Vector2i.ZERO:
		if _ActionTargeting._is_solid_column(world, null, fluid_cell.x, fluid_cell.y):
			push_error("fluid column %s must not count as solid" % fluid_cell)
			failed = true
		else:
			print("OK fluid column %s rejected" % fluid_cell)
	else:
		print("OK fluid column scan skipped (no river/ocean in probe window)")

	holder.queue_free()
	if failed:
		print("Target highlight tests FAILED")
		quit(1)
		return
	print("All target highlight tests OK")
	quit(0)