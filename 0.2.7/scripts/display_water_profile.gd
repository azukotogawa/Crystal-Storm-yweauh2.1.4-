extends SceneTree
## Live water phase profile on production main.tscn.
## Idle sample, then a real TerrainEditor channel, then post-edit sample.

const MAIN_SCENE := "res://scenes/main.tscn"
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _LiveWorldQuery = preload("res://helpers/live_world_query.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")


func _init() -> void:
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	if OS.get_environment("CRYSTALSTORM_SCRATCH").is_empty():
		OS.set_environment("CRYSTALSTORM_SCRATCH", "C:/Users/cwith/AppData/Local/Temp/grok-goal-58b4c9b1d20d/implementer")
	call_deferred("_run")


func _run() -> void:
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	DirAccess.make_dir_recursive_absolute(scratch)
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_done(false, "no main scene", {})
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
		_done(false, "start region not ready", {})
		return
	for _w in 12:
		await process_frame

	var idle: Dictionary = await _sample_window(15)
	var player = get_first_node_in_group("player")
	var world = get_first_node_in_group("world")
	var cm = get_first_node_in_group("chunk_manager")
	var editor = get_first_node_in_group("terrain_editor")
	var fluid = get_first_node_in_group("voxel_fluid_service")
	if player == null or world == null or editor == null or fluid == null:
		_done(false, "missing gameplay nodes", {"idle": idle})
		return

	var cell := _find_dry_solid(player, world, cm)
	var edit := {
		"cell": [cell.x, cell.y],
		"ok": false,
		"before_level": 0.0,
		"after_level": 0.0,
	}
	if cell != Vector2i.ZERO:
		var y: float = world.get_surface_height(float(cell.x), float(cell.y))
		var pos := Vector3(float(cell.x) + 0.5, y, float(cell.y) + 0.5)
		var inv = player.get("inventory")
		if inv and inv.has_method("add_item"):
			inv.add_item("stone", 8)
		edit["before_level"] = _ChannelRegistry.get_water_level(cell.x, cell.y)
		if editor.has_method("try_channel_water"):
			edit["ok"] = bool(editor.try_channel_water(pos, inv))
		elif editor.has_method("try_dig"):
			edit["ok"] = bool(editor.try_dig(pos))
			_ChannelRegistry.register_channel(cell.x, cell.y, Vector2i(1, 0), 0.75)
			if fluid.has_method("recompute_region_now"):
				fluid.recompute_region_now(cell.x, cell.y, 2, 1)
		edit["after_level"] = _ChannelRegistry.get_water_level(cell.x, cell.y)
		var insp = game.get_node_or_null("LiveWorldInspector")
		if insp:
			insp.panel_open = true
			insp.pin_cell = cell
		player.voxel_position.x = float(cell.x) + 0.5
		player.voxel_position.z = float(cell.y) - 2.0
		if player.has_method("_sync_global_from_voxel"):
			player._sync_global_from_voxel()
		if player.has_method("_snap_to_ground"):
			player._snap_to_ground()

	var after_edit: Dictionary = await _sample_window(20)
	# Second: channel on a river tile — this used to explode dirty to ~3500 / 220ms.
	var river_edit := {"cell": [0, 0], "ok": false, "tile": -1}
	var river_cell := Vector2i(24, 24)
	if world:
		river_edit["tile"] = int(world.get_tile_type(24.0, 24.0))
		var ry: float = world.get_surface_height(24.0, 24.0)
		var rpos := Vector3(24.5, ry, 24.5)
		if editor.has_method("try_channel_water"):
			river_edit["ok"] = bool(editor.try_channel_water(rpos, player.get("inventory")))
		river_edit["cell"] = [24, 24]
	var after_river: Dictionary = await _sample_window(25)
	var inspect: Dictionary = {}
	if cell != Vector2i.ZERO:
		inspect = _LiveWorldQuery.inspect_cell(self, cell.x, cell.y)
	_shot(scratch, "water_profile_cell")
	var report := {
		"idle": idle,
		"edit": edit,
		"after_edit": after_edit,
		"river_edit": river_edit,
		"after_river": after_river,
		"inspect": {
			"wx": inspect.get("wx", cell.x),
			"wz": inspect.get("wz", cell.y),
			"surface": inspect.get("surface_height", 0.0),
			"walk": inspect.get("walkable_height", 0.0),
			"tile": inspect.get("tile", -1),
			"covered": inspect.get("column_mesh_covered", false),
			"disc": inspect.get("discrepancies", []),
			"origin": inspect.get("origin", ""),
		},
		"input_blocked": _GameplayInput.blocks_actions(),
	}
	var path := scratch.path_join("water_profile.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()
	print("WATER_PROFILE idle_sleep=%s/%s worst_idle_us=%s edit_ok=%s after_sleep=%s/%s worst_after_us=%s subset=%s phases=%s" % [
		str(idle.get("sleep_frames")), str(idle.get("frames")),
		str(idle.get("worst_tick_us")),
		str(edit.get("ok")),
		str(after_edit.get("sleep_frames")), str(after_edit.get("frames")),
		str(after_edit.get("worst_tick_us")),
		str((after_edit.get("last", {}) as Dictionary).get("subset_cells", -1)),
		str((after_edit.get("last", {}) as Dictionary).get("phase_us", {})),
	])
	_done(true, "WATER PROFILE OK", report)


func _sample_window(n: int) -> Dictionary:
	var worst := 0
	var slept := 0
	var last: Dictionary = {}
	var peak_subset := 0
	var peak_phase: Dictionary = {}
	for _i in n:
		await process_frame
		var fluid = get_first_node_in_group("voxel_fluid_service")
		if fluid == null or not fluid.has_method("get_sim_diagnostics"):
			continue
		last = fluid.get_sim_diagnostics()
		var us: int = int(last.get("last_tick_us", 0))
		if us > worst:
			worst = us
			peak_phase = last.get("phase_us", {})
		if int(last.get("subset_cells", 0)) > peak_subset:
			peak_subset = int(last.get("subset_cells", 0))
		if bool(last.get("sleeping", false)):
			slept += 1
	return {
		"frames": n,
		"sleep_frames": slept,
		"worst_tick_us": worst,
		"peak_subset": peak_subset,
		"peak_phase_us": peak_phase,
		"last": last,
	}


func _find_dry_solid(player: Node, world, cm) -> Vector2i:
	var start := Vector2i(floori(player.get("voxel_position").x), floori(player.get("voxel_position").z))
	for radius in range(0, 24):
		for gx in range(start.x - radius, start.x + radius + 1):
			for gz in range(start.y - radius, start.y + radius + 1):
				if not _ActionTargeting._is_solid_column(world, cm, gx, gz):
					continue
				var tile: int = world.get_tile_type(float(gx), float(gz))
				if tile in [_VoxelTypes.OCEAN, _VoxelTypes.OCEAN2, _VoxelTypes.OCEAN3, _VoxelTypes.RIVER, _VoxelTypes.WATER]:
					continue
				return Vector2i(gx, gz)
	return Vector2i.ZERO


func _shot(scratch: String, name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var tex: Texture2D = root.get_texture()
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return
	img.save_png(scratch.path_join("%s.png" % name))
	print("SHOT %s" % scratch.path_join("%s.png" % name))


func _done(ok: bool, marker: String, _report: Dictionary) -> void:
	if not ok:
		push_error(marker)
	_ProbeExit.finish_tree(self, 0 if ok else 1, marker)
