extends SceneTree
## Regression: main-scene floor probe honors live builds (step 1-layer, block 2-layer).


const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _SmokeProbeHelpers = preload("res://scripts/smoke_probe_helpers.gd")
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		push_error("main scene load failed")
		_ProbeExit.finish_tree(self, 1, "Built wall collision main FAILED")
		return

	var game: Node = main_packed.instantiate()
	root.add_child(game)

	var player: Node = null
	var chunk_manager: ChunkManager = null
	var world: InfiniteNoiseWorld = null
	var terrain_editor: TerrainEditor = null

	var bootstrap_frames := 0
	for _attempt in 600:
		bootstrap_frames += 1
		player = get_first_node_in_group("player")
		chunk_manager = get_first_node_in_group("chunk_manager")
		world = get_first_node_in_group("world")
		terrain_editor = get_first_node_in_group("terrain_editor") as TerrainEditor
		if (
			player != null and chunk_manager != null and world != null
			and terrain_editor != null and terrain_editor.chunk_manager != null
			and bool(player.get("world_ready"))
		):
			break
		await process_frame

	if player == null or chunk_manager == null or world == null:
		push_error("bootstrap timeout (player/chunk/world) after %d frames" % bootstrap_frames)
		_ProbeExit.finish_tree(self, 1, "Built wall collision main FAILED")
		return

	for _w in 120:
		if terrain_editor != null and terrain_editor.chunk_manager != null:
			break
		terrain_editor = get_first_node_in_group("terrain_editor") as TerrainEditor
		await process_frame

	if terrain_editor == null or terrain_editor.chunk_manager == null:
		push_error("terrain_editor not bound")
		_ProbeExit.finish_tree(self, 1, "Built wall collision main FAILED")
		return

	for _w in 60:
		await process_frame

	var inv = player.get("inventory")
	if inv == null:
		push_error("inventory missing")
		failed = true
	else:
		if inv.count_item("stone") < 4:
			inv.add_item("stone", 8)
		inv.set_slot(0, "stone", 8)

	var floor_probe = player.get("_floor_probe")
	if floor_probe == null:
		push_error("player floor probe missing")
		failed = true
		_ProbeExit.finish_tree(self, 1, "Built wall collision main FAILED")
		return

	var player_col := Vector2i(
		floori(float(player.get("voxel_position").x)),
		floori(float(player.get("voxel_position").z))
	)
	var build_wx := -1
	var build_wz := -1
	for radius in range(2, 14):
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
				build_wx = wx
				build_wz = wz
				break
			if build_wx >= 0:
				break
		if build_wx >= 0:
			break

	if build_wx < 0:
		push_error("no buildable column near player")
		failed = true
		_ProbeExit.finish_tree(self, 1, "Built wall collision main FAILED")
		return

	var chunk_coord := chunk_manager.world_to_chunk_coord(build_wx, build_wz)
	if chunk_manager.has_method("update_stream"):
		chunk_manager.update_stream(chunk_coord.x, chunk_coord.y)
	for _w in 80:
		await process_frame
		if chunk_manager.chunks.has(chunk_coord):
			break

	var build_h: float = world.get_surface_height(float(build_wx), float(build_wz))
	var build_target := Vector3(float(build_wx) + 0.5, build_h, float(build_wz) + 0.5)
	if not terrain_editor.try_build_wall(build_target, inv, true):
		push_error("try_build_wall failed at (%d,%d)" % [build_wx, build_wz])
		failed = true

	var build_delta: float = _TerrainEdits.get_height_delta(build_wx, build_wz)
	if build_delta > 0.01:
		var pre_rebuild: Dictionary = _SmokeProbeHelpers.check_built_wall_collision(
			floor_probe, build_wx, build_wz, true, false
		)
		if not pre_rebuild.get("ok", false):
			push_error("pre-rebuild collision: %s" % pre_rebuild.get("reason", "?"))
			failed = true
		else:
			print(
				"OK pre-rebuild collision raise=%.2f step=%s"
				% [pre_rebuild.get("raise", 0.0), pre_rebuild.get("can_step", false)]
			)

	if chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle()
	for _w in 40:
		await process_frame

	build_delta = _TerrainEdits.get_height_delta(build_wx, build_wz)
	if build_delta <= 0.01:
		push_error("build delta not recorded")
		failed = true
	else:
		var one_layer: Dictionary = _SmokeProbeHelpers.check_built_wall_collision(
			floor_probe, build_wx, build_wz, true, false
		)
		if not one_layer.get("ok", false):
			push_error("1-layer collision: %s" % one_layer.get("reason", "?"))
			failed = true
		else:
			print(
				"OK main 1-layer collision raise=%.2f step=%s"
				% [one_layer.get("raise", 0.0), one_layer.get("can_step", false)]
			)

		var h2: float = world.get_surface_height(float(build_wx), float(build_wz))
		if terrain_editor.try_build_wall(
			Vector3(float(build_wx) + 0.5, h2, float(build_wz) + 0.5), inv, true
		):
			if chunk_manager.has_method("await_rebuild_idle"):
				await chunk_manager.await_rebuild_idle()
			for _w in 40:
				await process_frame
		var stacked: Dictionary = _SmokeProbeHelpers.check_built_wall_collision(
			floor_probe, build_wx, build_wz, false, true
		)
		if not stacked.get("ok", false):
			push_error("stacked collision: %s" % stacked.get("reason", "?"))
			failed = true
		else:
			print("OK main stacked wall blocks natural-feet entry")

	var probe_src := (load("res://player/voxel_floor_probe.gd") as GDScript).source_code
	if "live_delta - snap_delta" not in probe_src:
		push_error("voxel_floor_probe must apply live terrain edits")
		failed = true
	else:
		print("OK probe live terrain edit contract")

	if failed:
		_ProbeExit.finish_tree(self, 1, "Built wall collision main FAILED")
		return
	_ProbeExit.finish_tree(self, 0, "All built wall collision main tests OK")