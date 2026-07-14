extends SceneTree
## Regression: melee targeting uses camera-forward raycast (not mouse-only / fixed north).


const MAIN_SCENE := "res://scenes/main.tscn"
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _SmokeProbeHelpers = preload("res://scripts/smoke_probe_helpers.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var weapon_src := (load("res://weapons/weapon_controller.gd") as GDScript).source_code
	if 'resolve_action' not in weapon_src or '&"attack"' not in weapon_src:
		push_error("weapon_controller melee must call resolve_action with attack mode")
		failed = true
	else:
		print("OK weapon melee uses resolve_action attack")

	var targeting_src := (load("res://player/action_targeting.gd") as GDScript).source_code
	if '&"dig", &"build", &"attack", &"ranged"' not in targeting_src or "mouse_only = false" not in targeting_src:
		push_error("action_targeting must forward-fallback tool modes without mouse")
		failed = true
	else:
		print("OK action_targeting weapon forward fallback")

	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		push_error("main scene load failed")
		_ProbeExit.finish_tree(self, 1, "Melee forward targeting FAILED")
		return

	var game: Node = main_packed.instantiate()
	root.add_child(game)

	var player: Node = null
	var world: InfiniteNoiseWorld = null
	var chunk_manager: ChunkManager = null
	var weapon: Node = null

	for _attempt in 600:
		player = get_first_node_in_group("player")
		world = get_first_node_in_group("world")
		chunk_manager = get_first_node_in_group("chunk_manager")
		weapon = player.get_node_or_null("WeaponController") if player else null
		if (
			player != null and world != null and chunk_manager != null and weapon != null
			and bool(player.get("world_ready"))
		):
			break
		await process_frame

	if player == null or weapon == null:
		push_error("bootstrap timeout")
		_ProbeExit.finish_tree(self, 1, "Melee forward targeting FAILED")
		return

	for _w in 60:
		await process_frame

	var inv = player.get("inventory")
	if inv:
		inv.set_slot(0, "wooden_sword", 1)
	if weapon.has_method("set_active_hotbar_index"):
		weapon.set_active_hotbar_index(0)

	var sword_def: Dictionary = _ItemTypes.get_def("wooden_sword")
	var range_v: float = float(sword_def.get("range", 2.0))
	var player_col := Vector2i(
		floori(float(player.get("voxel_position").x)),
		floori(float(player.get("voxel_position").z))
	)
	var atk_wx := -1
	var atk_wz := -1
	for radius in range(1, 10):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var wx: int = player_col.x + dx
				var wz: int = player_col.y + dz
				if _ActionTargeting._is_solid_column(world, chunk_manager, wx, wz):
					atk_wx = wx
					atk_wz = wz
					break
			if atk_wx >= 0:
				break
		if atk_wx >= 0:
			break
	if atk_wx < 0:
		push_error("no solid column for melee forward probe")
		failed = true
	else:
		_SmokeProbeHelpers.position_player_for_forward_dig(
			player, world, chunk_manager, atk_wx, atk_wz, range_v, &"attack"
		)
		_SmokeProbeHelpers.clear_mouse_offscreen(player)
		for _w in 60:
			await process_frame

	var cam: Camera3D = player.get("camera") as Camera3D if "camera" in player else null
	var forwards: Dictionary = {}
	var resolve_cells: Dictionary = {}
	var yaws: Array[float] = [0.0, 90.0, 180.0, 270.0]
	for yaw in yaws:
		if cam:
			if "orbit_yaw_deg" in cam:
				cam.orbit_yaw_deg = yaw
				if "_orbit_target_deg" in cam:
					cam._orbit_target_deg = yaw
			if cam.has_method("_apply_orbit_rotation"):
				cam.call("_apply_orbit_rotation")
			else:
				cam.rotation_degrees = Vector3(-35.264, 45.0 + yaw, 0.0)
		_SmokeProbeHelpers.position_player_for_forward_dig(
			player, world, chunk_manager, atk_wx, atk_wz, range_v, &"attack"
		)
		_SmokeProbeHelpers.clear_mouse_offscreen(player)
		for _w in 8:
			await process_frame
		var fwd := _ActionTargeting.attack_forward(player)
		forwards["%.3f,%.3f" % [fwd.x, fwd.z]] = true
		var yaw_info: Dictionary = _ActionTargeting.resolve_action(
			player, world, chunk_manager, range_v, false, &"attack"
		)
		if yaw_info.get("valid", false) and yaw_info.get("mode", &"") == &"attack":
			var yaw_cell: Vector2i = yaw_info.get("cell", Vector2i.ZERO)
			resolve_cells["%d,%d" % [yaw_cell.x, yaw_cell.y]] = true

	if forwards.size() < 2:
		push_error("attack_forward must vary with camera yaw, got %d dirs: %s" % [forwards.size(), forwards.keys()])
		failed = true
	else:
		print("OK attack_forward dirs=%d across yaw rotations" % forwards.size())

	if resolve_cells.is_empty():
		push_error("attack must resolve via forward fallback with mouse off-screen")
		failed = true
	else:
		print("OK attack resolves without mouse at cells=%s" % resolve_cells.keys())

	# Production melee must damage a spawned entity ahead along attack_forward (not co-located).
	var entity_mgr = get_first_node_in_group("entity_manager")
	if entity_mgr and entity_mgr.has_method("_spawn_world_entity"):
		if cam:
			if "orbit_yaw_deg" in cam:
				cam.orbit_yaw_deg = 45.0
				if "_orbit_target_deg" in cam:
					cam._orbit_target_deg = 45.0
			if cam.has_method("_apply_orbit_rotation"):
				cam.call("_apply_orbit_rotation")
		_SmokeProbeHelpers.position_player_for_forward_dig(
			player, world, chunk_manager, atk_wx, atk_wz, range_v, &"attack"
		)
		_SmokeProbeHelpers.clear_mouse_offscreen(player)
		for _w in 8:
			await process_frame
		var aim_fwd := _ActionTargeting.attack_forward(player)
		var entity_cell := Vector2i(atk_wx, atk_wz)
		if chunk_manager.has_method("update_stream"):
			var ecoord := chunk_manager.world_to_chunk_coord(entity_cell.x, entity_cell.y)
			chunk_manager.update_stream(ecoord.x, ecoord.y)
			for _w in 60:
				await process_frame
		for node in get_nodes_in_group("world_entity"):
			if is_instance_valid(node):
				node.queue_free()
		for _w in 24:
			await process_frame
		var brain = load("res://entities/entity_brain_registry.gd")
		var brain_cfg = brain.get_def(&"rabbit") if brain else null
		if brain_cfg:
			entity_mgr.call(
				"_spawn_world_entity", entity_cell.x, entity_cell.y, brain_cfg, entity_cell, Color.WHITE
			)
			var spawned: Node = null
			for _w in 60:
				for node in get_nodes_in_group("world_entity"):
					if not is_instance_valid(node):
						continue
					if node.get("home_cell") == entity_cell:
						spawned = node
						break
				if spawned != null:
					break
				await process_frame
			if spawned == null or not is_instance_valid(spawned):
				push_error("probe entity missing at spawn cell %s" % entity_cell)
				failed = true
			elif spawned.get("home_cell") != entity_cell:
				push_error(
					"probe entity home %s != spawn %s"
					% [spawned.get("home_cell"), entity_cell]
				)
				failed = true
			elif spawned and weapon.has_method("_do_melee_attack"):
				spawned.set_process(false)
				var melee: Dictionary = _SmokeProbeHelpers.try_forward_arc_melee_damage(
					player, world, chunk_manager, weapon, spawned, "wooden_sword", sword_def
				)
				if not melee.get("ok", false):
					push_error(
						"forward-arc melee failed reason=%s dist=%.1f"
						% [melee.get("reason", "?"), float(melee.get("dist_cells", 0.0))]
					)
					failed = true
				else:
					print(
						"OK forward-arc melee HP %.1f→%.1f entity=%s player=%s dist=%.1f pre_hits=%d"
						% [
							melee.get("hp_before", 0.0),
							melee.get("hp_after", 0.0),
							spawned.get("home_cell"),
							melee.get("player_cell"),
							melee.get("dist_cells", 0.0),
							melee.get("pre_hits", 0),
						]
					)

	if failed:
		_ProbeExit.finish_tree(self, 1, "Melee forward targeting FAILED")
		return
	_ProbeExit.finish_tree(self, 0, "All melee forward targeting tests OK")