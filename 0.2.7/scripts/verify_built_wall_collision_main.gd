extends SceneTree
## Regression: main-scene floor probe honors live builds (step 1-layer, block 2-layer).


const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _SmokeProbeHelpers = preload("res://scripts/smoke_probe_helpers.gd")
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")


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
	var wall_feat: Dictionary = _FeatureRegistry.get_feature(build_wx, build_wz)
	if str(wall_feat.get("build_id", "")) != "stone_wall":
		push_error("stone_wall WorldObject missing after build")
		failed = true
	elif absf(build_delta) > 0.01:
		push_error("wall raised the heightfield by %.2f" % build_delta)
		failed = true
	else:
		var blocked: Dictionary = _SmokeProbeHelpers.check_built_wall_collision(
			floor_probe, build_wx, build_wz, false, true
		)
		if not blocked.get("ok", false):
			push_error("wall collision: %s" % blocked.get("reason", "?"))
			failed = true
		else:
			print("OK WorldObject wall blocks entry")
		var h2: float = world.get_surface_height(float(build_wx), float(build_wz))
		if terrain_editor.try_build_wall(
			Vector3(float(build_wx) + 0.5, h2, float(build_wz) + 0.5), inv, true
		):
			push_error("second wall on the same cell should be refused")
			failed = true
		else:
			print("OK second wall refused")

	if not _live_floor_edit_same_frame(floor_probe, world, chunk_manager, player_col):
		failed = true

	if failed:
		_ProbeExit.finish_tree(self, 1, "Built wall collision main FAILED")
		return
	_ProbeExit.finish_tree(self, 0, "All built wall collision main tests OK")


func _near_layer(before: float, after: float, layer: float) -> bool:
	return absf((after - before) - layer) <= 0.05


## Sample, build, then dig to a negative delta this physics frame has not cached.
func _live_floor_edit_same_frame(floor_probe, world, chunk_manager, origin: Vector2i) -> bool:
	var cell := _find_flat_edit_column(floor_probe, chunk_manager, origin)
	if cell.x < -100000:
		push_error("no flat column for live floor-probe edit")
		return false
	var layer: float = _WorldSettings.get_active().layer_height()
	var sx := float(cell.x) + 0.5
	var sz := float(cell.y) + 0.5
	var saved_hint: float = float(floor_probe.feet_height_hint)
	var surf: float = world.get_surface_height(sx, sz)
	floor_probe.feet_height_hint = surf + layer
	var frame := Engine.get_physics_frames()
	var h0: float = floor_probe.walkable_height_at(sx, sz)
	var f0: float = floor_probe.sample_walkable_feet(sx, sz)
	var c0: float = floor_probe.cached_column_center_walkable(world, chunk_manager, cell.x, cell.y)
	var ok := true
	if not _TerrainEdits.build_wall(cell.x, cell.y, _VoxelTypes.STONE):
		push_error("live build failed at (%d,%d)" % [cell.x, cell.y])
		ok = false
	else:
		var h1: float = floor_probe.walkable_height_at(sx, sz)
		var f1: float = floor_probe.sample_walkable_feet(sx, sz)
		var c1: float = floor_probe.cached_column_center_walkable(world, chunk_manager, cell.x, cell.y)
		if (
			not _near_layer(h0, h1, layer)
			or not _near_layer(f0, f1, layer)
			or not _near_layer(c0, c1, layer)
		):
			push_error(
				"live build did not raise floor same frame h %.3f->%.3f feet %.3f->%.3f center %.3f->%.3f"
				% [h0, h1, f0, f1, c0, c1]
			)
			ok = false
		elif not _TerrainEdits.dig(cell.x, cell.y, 1) or not _TerrainEdits.dig(cell.x, cell.y, 1):
			push_error("live dig failed at (%d,%d)" % [cell.x, cell.y])
			ok = false
		else:
			var h2: float = floor_probe.walkable_height_at(sx, sz)
			var f2: float = floor_probe.sample_walkable_feet(sx, sz)
			var c2: float = floor_probe.cached_column_center_walkable(
				world, chunk_manager, cell.x, cell.y
			)
			if (
				not _near_layer(h2, h0, layer)
				or not _near_layer(f2, f0, layer)
				or not _near_layer(c2, c0, layer)
			):
				push_error(
					"live dig did not lower floor same frame h %.3f->%.3f feet %.3f->%.3f center %.3f->%.3f"
					% [h0, h2, f0, f2, c0, c2]
				)
				ok = false
	if Engine.get_physics_frames() != frame:
		push_error("live terrain edit check crossed a physics frame")
		ok = false
	floor_probe.feet_height_hint = saved_hint
	_clear_column_edit(cell.x, cell.y)
	if ok:
		print("OK probe live terrain edit same frame at (%d,%d)" % [cell.x, cell.y])
	return ok


func _find_flat_edit_column(floor_probe, chunk_manager, origin: Vector2i) -> Vector2i:
	var crystal = floor_probe.get("crystal_manager")
	for radius in range(2, 36):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var cx: int = origin.x + dx
				var cz: int = origin.y + dz
				if not _TerrainEdits.can_edit(cx, cz):
					continue
				if absf(_TerrainEdits.get_height_delta(cx, cz)) > 0.001:
					continue
				if _column_has_crystal(crystal, cx, cz):
					continue
				if chunk_manager != null and chunk_manager.has_method("get_ramp_entry_at_world"):
					var entry: Dictionary = chunk_manager.get_ramp_entry_at_world(
						float(cx) + 0.5, float(cz) + 0.5
					)
					if not entry.is_empty():
						continue
				return Vector2i(cx, cz)
	return Vector2i(-999999, -999999)


func _column_has_crystal(crystal, cx: int, cz: int) -> bool:
	if crystal == null or not crystal.has_method("get_depth_at"):
		return false
	var min_d := 0.04
	var cfg = crystal.get("sim_config")
	if cfg != null:
		min_d = float(cfg.min_depth)
	return float(crystal.get_depth_at(cx, cz)) >= min_d


func _clear_column_edit(cx: int, cz: int) -> void:
	for _i in 8:
		if (
			absf(_TerrainEdits.get_height_delta(cx, cz)) <= 0.001
			and _TerrainEdits.get_build_tile(cx, cz) < 0
		):
			return
		if not _TerrainEdits.unstack_build(cx, cz):
			return