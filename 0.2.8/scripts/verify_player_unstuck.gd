extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const _DIRS := {
	"move_forward": Vector2(0, -1),
	"move_back": Vector2(0, 1),
	"move_left": Vector2(-1, 0),
	"move_right": Vector2(1, 0),
}

var _failed: int = 0


func _init() -> void:
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	if OS.get_environment("CRYSTALSTORM_BAKE_RADIUS").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	if OS.get_environment("CRYSTALSTORM_FULL_WORLD_BAKE").is_empty():
		OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	if OS.get_environment("CRYSTALSTORM_BAKE_ON_NEW").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL %s" % msg)


func _ok(msg: String) -> void:
	print("OK %s" % msg)


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("no main scene")
		_finish()
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while frames < 3600:
		if compose != null and int(compose.stage) >= compose.Stage.INITIAL_STREAM_READY:
			break
		await process_frame
		frames += 1
	if compose == null or int(compose.stage) < compose.Stage.INITIAL_STREAM_READY:
		_fail("start region not ready")
		_finish()
		return
	var gameplay = load("res://helpers/gameplay_input.gd")
	for _w in 90:
		await process_frame
		if gameplay and not gameplay.blocks_actions():
			break
	if gameplay.blocks_actions():
		_fail("gameplay input stayed blocked after boot")
		_finish()
		return

	var player = get_first_node_in_group("player")
	var world = get_first_node_in_group("world")
	if player == null or world == null:
		_fail("missing player or world")
		_finish()
		return
	var home: Vector3 = player.voxel_position
	print("SPAWN voxel=%s global=%s" % [home, player.global_position])
	_assert_column(player, world, home.x, home.z, "spawn")
	_assert_column(player, world, 0.5, 0.5, "origin")
	if _buried(player):
		_fail("player spawned inside terrain at %s" % player.voxel_position)
	else:
		_ok("spawn is not inside terrain")

	for action in _DIRS.keys():
		player.voxel_position = home
		await physics_frame
		if _buried(player):
			_fail("restore buried the player before %s" % action)
			break
		var start: Vector3 = player.voxel_position
		Input.action_press(action)
		var buried_frames := 0
		for _i in 24:
			await physics_frame
			if _buried(player):
				buried_frames += 1
		Input.action_release(action)
		var moved := Vector2(player.voxel_position.x - start.x, player.voxel_position.z - start.z).length()
		var world_dir: Vector2 = player.rotate_input_to_world(_DIRS[action], float(player.camera.yaw_degrees))
		var step: Vector3 = start + Vector3(world_dir.x, 0.0, world_dir.y) * 0.45
		var can: bool = player._can_move_to(step, false)
		if buried_frames > 0:
			_fail("%s buried the player for %d frames at %s" % [action, buried_frames, player.voxel_position])
		elif can and moved < 0.08:
			_fail("%s could step but only moved %.3f" % [action, moved])
		else:
			_ok("%s moved %.2f buried=0 can_step=%s" % [action, moved, can])

	player.voxel_position = home
	await physics_frame
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	var jump_buried := 0
	for _j in 36:
		await physics_frame
		if _buried(player):
			jump_buried += 1
	if jump_buried > 0:
		_dump_stand(player, world, "jump")
		_fail("jump buried the player for %d frames" % jump_buried)
	else:
		_ok("jump did not bury the player")

	player.voxel_position = home
	await physics_frame
	var editor = get_first_node_in_group("terrain_editor")
	if editor and editor.has_method("try_dig"):
		var ahead := Vector2i(floori(player.voxel_position.x) + 1, floori(player.voxel_position.z))
		var sy: float = world.get_surface_height(float(ahead.x) + 0.5, float(ahead.y) + 0.5)
		var dug: bool = editor.try_dig(Vector3(float(ahead.x) + 0.5, sy, float(ahead.y) + 0.5))
		print("DIG front cell %s ok=%s" % [ahead, dug])
		for _d in 10:
			await physics_frame
			if _buried(player):
				_fail("digging ahead buried the player")
				break
		var under := Vector2i(floori(player.voxel_position.x), floori(player.voxel_position.z))
		var uy: float = world.get_surface_height(float(under.x) + 0.5, float(under.y) + 0.5)
		var dug_under: bool = editor.try_dig(Vector3(float(under.x) + 0.5, uy, float(under.y) + 0.5))
		print("DIG under cell %s ok=%s" % [under, dug_under])
		var under_buried := 0
		for _u in 24:
			await physics_frame
			if _buried(player):
				under_buried += 1
		if under_buried > 0:
			_dump_stand(player, world, "dig-under")
			_fail("digging the cell under the player buried them for %d frames" % under_buried)
		else:
			_ok("dig in front and below left the player free")
	else:
		_fail("no terrain editor")

	if not InputMap.has_action("unstuck"):
		_fail("unstuck action missing")
		_finish()
		return
	var probe = player._floor_probe
	var layer: float = _WorldSettings.get_active().layer_height()
	var stand_x: float = player.voxel_position.x
	var stand_z: float = player.voxel_position.z
	var top: float = probe.rendered_top_at(stand_x, stand_z)
	player.voxel_position.y = top - layer * 0.55
	player._overlap_tick = 0
	player._unstuck_cooldown = 0.0
	Input.action_release("unstuck")
	if not _buried(player):
		_fail("forced bury did not overlap (y %.2f top %.2f)" % [player.voxel_position.y, top])
	var freed := -1
	for i in 10:
		await physics_frame
		if not _buried(player):
			freed = i + 1
			break
	if freed < 0:
		_fail("auto unstuck did not free y %.2f" % player.voxel_position.y)
	else:
		_ok("auto unstuck freed the player in %d physics frames" % freed)

	top = probe.rendered_top_at(player.voxel_position.x, player.voxel_position.z)
	player.voxel_position.y = top - layer * 0.55
	player._overlap_tick = 0
	player._unstuck_cooldown = 0.0
	Input.action_press("unstuck")
	await physics_frame
	Input.action_release("unstuck")
	if _buried(player):
		_dump_stand(player, world, "manual")
		_fail("manual unstuck left the player at %s" % player.voxel_position)
	elif float(player._unstuck_cooldown) <= 0.0:
		_fail("manual unstuck did not start the cooldown")
	else:
		var safe: float = probe.rendered_top_at(player.voxel_position.x, player.voxel_position.z)
		if player.voxel_position.y < safe - 0.35:
			_fail("manual unstuck stand %.2f is below rendered top %.2f" % [player.voxel_position.y, safe])
		else:
			_ok("manual unstuck stand %s cooldown %.2f" % [player.voxel_position, float(player._unstuck_cooldown)])
	_finish()


func _assert_column(player, world, x: float, z: float, tag: String) -> void:
	var probe = player._floor_probe
	var layer: float = _WorldSettings.get_active().layer_height()
	var surf: float = world.get_surface_height(x, z)
	var cave: float = world.get_cave_floor_height(x, z)
	if cave > surf + 0.05 and cave < surf + layer - 0.05:
		_fail("%s cave floor %.2f is inside the slab surf %.2f" % [tag, cave, surf])
	probe.feet_height_hint = 0.0
	var low: float = probe.sample_walkable_feet(x, z)
	if low > surf + 0.15 and low < surf + layer - 0.15:
		_fail("%s low hint %.2f is inside slab [%.2f, %.2f]" % [tag, low, surf, surf + layer])
	probe.feet_height_hint = surf + layer
	var hi: float = probe.sample_walkable_feet(x, z)
	var top: float = probe.rendered_top_at(x, z)
	var stand := Vector3(x, hi, z)
	var inside: bool = probe.body_overlaps_terrain(stand, player._player_height())
	print("%s surf=%.2f cave=%.2f low=%.2f hi=%.2f top=%.2f inside=%s" % [tag, surf, cave, low, hi, top, inside])
	if inside:
		_fail("%s surface stand overlaps terrain" % tag)
	elif absf(hi - top) > 0.45:
		_fail("%s surface feet %.2f disagree with rendered top %.2f" % [tag, hi, top])
	else:
		_ok("%s surface stand matches the rendered top" % tag)


func _dump_stand(player, world, tag: String) -> void:
	var probe = player._floor_probe
	var pos: Vector3 = player.voxel_position
	var surf: float = world.get_surface_height(pos.x, pos.z)
	var top: float = probe.rendered_top_at(pos.x, pos.z)
	var saved: float = probe.feet_height_hint
	probe.feet_height_hint = pos.y
	var walk: float = probe.sample_walkable_feet(pos.x, pos.z)
	probe.feet_height_hint = saved
	print("%s y=%.2f surf=%.2f top=%.2f walk=%.2f state=%s cd=%.2f" % [
		tag, pos.y, surf, top, walk, player.current_state, float(player._unstuck_cooldown)
	])


func _buried(player) -> bool:
	var probe = player._floor_probe
	if probe == null:
		return false
	return probe.body_overlaps_terrain(player.voxel_position, player._player_height())


func _finish() -> void:
	for action in _DIRS.keys():
		Input.action_release(action)
	Input.action_release("jump")
	Input.action_release("unstuck")
	if _failed > 0:
		_ProbeExit.finish_tree(self, 1, "Player unstuck FAILED")
	else:
		_ProbeExit.finish_tree(self, 0, "All player unstuck tests OK")
