extends SceneTree
## Regression: build highlight anchors on placement top (not buried in terrain).


const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _SmokeProbeHelpers = preload("res://scripts/smoke_probe_helpers.gd")
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _WorldSettings = preload("res://config/world_settings.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		push_error("main scene load failed")
		_ProbeExit.finish_tree(self, 1, "Build highlight placement FAILED")
		return

	var game: Node = main_packed.instantiate()
	root.add_child(game)

	var player: Node = null
	var chunk_manager: ChunkManager = null
	var world: InfiniteNoiseWorld = null
	var weapon: Node = null

	for _attempt in 600:
		player = get_first_node_in_group("player")
		chunk_manager = get_first_node_in_group("chunk_manager")
		world = get_first_node_in_group("world")
		weapon = player.get_node_or_null("WeaponController") if player else null
		if (
			player != null and chunk_manager != null and world != null and weapon != null
			and bool(player.get("world_ready"))
		):
			break
		await process_frame

	if player == null:
		push_error("bootstrap timeout")
		_ProbeExit.finish_tree(self, 1, "Build highlight placement FAILED")
		return

	for _w in 60:
		await process_frame

	var inv = player.get("inventory")
	if inv == null or not inv.has_method("add_item"):
		push_error("player inventory missing")
		failed = true
	else:
		inv.add_item("stone", 4)
		inv.set_slot(0, "stone", 4)
	if weapon.has_method("set_active_hotbar_index"):
		weapon.set_active_hotbar_index(0)

	var layer: float = _WorldSettings.get_active().layer_height()
	var player_col := Vector2i(
		floori(float(player.get("voxel_position").x)),
		floori(float(player.get("voxel_position").z))
	)
	var targeting_src := (load("res://player/action_targeting.gd") as GDScript).source_code
	if "built_layers + 1" not in targeting_src:
		push_error("action_targeting must anchor build highlight on placement top face")
		failed = true
	else:
		print("OK action_targeting build top-face anchor")

	var placement_ok := false
	for radius in range(1, 12):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var wx: int = player_col.x + dx
				var wz: int = player_col.y + dz
				if not _ActionTargeting._is_solid_column(world, chunk_manager, wx, wz):
					continue
				if not _ActionTargeting._can_build_column(world, chunk_manager, wx, wz):
					continue
				_SmokeProbeHelpers.position_player_for_forward_dig(
					player, world, chunk_manager, wx, wz, 2.0, &"build"
				)
				_ActionTargeting.warp_mouse_to_column(
					player, world, float(wx) + 0.5, float(wz) + 0.5
				)
				for _w in 12:
					await process_frame
				var build_info: Dictionary = _ActionTargeting.resolve_action(
					player, world, chunk_manager, 2.0, false, &"build"
				)
				if build_info.get("mode", &"") != &"build" or not build_info.get("valid", false):
					continue
				var walk: float = _ActionTargeting._walkable_top(
					world, chunk_manager, float(wx) + 0.5, float(wz) + 0.5
				)
				var build_y: float = float(build_info.get("world_pos", Vector3.ZERO).y)
				if build_y < walk + layer * 0.92:
					continue
				for _w in 8:
					await process_frame
				var highlight: Node = player.get_node_or_null("TargetHighlight")
				var box: MeshInstance3D = highlight.get_node_or_null("TargetBox") as MeshInstance3D if highlight else null
				var hl_visible := box != null and box.visible
				var hl_green := false
				if box != null and box.material_override is StandardMaterial3D:
					var c: Color = (box.material_override as StandardMaterial3D).albedo_color
					hl_green = c.g > 0.75 and c.r < 0.55
				if not hl_visible or not hl_green:
					continue
				print(
					"OK build highlight visible cell=%s y=%.2f walk=%.2f green=%s"
					% [build_info.get("cell"), build_y, walk, hl_green]
				)
				placement_ok = true
				break
			if placement_ok:
				break
		if placement_ok:
			break

	if not placement_ok:
		push_error("build highlight never visible green on placement top in main scene")
		failed = true

	if failed:
		_ProbeExit.finish_tree(self, 1, "Build highlight placement FAILED")
		return
	_ProbeExit.finish_tree(self, 0, "All build highlight placement tests OK")