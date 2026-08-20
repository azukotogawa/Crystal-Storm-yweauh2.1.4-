extends SceneTree
## Windowed/headless quality sample during live activity (crystal front + melee).

const MAIN_SCENE := "res://scenes/main.tscn"
const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _WorldVisualCoords = preload("res://helpers/world_visual_coords.gd")


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


func _run() -> void:
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch.is_empty():
		scratch = "C:/Users/cwith/AppData/Local/Temp/grok-goal-961aca94c53e/implementer"
	DirAccess.make_dir_recursive_absolute(scratch)
	var preset := OS.get_environment("CRYSTALSTORM_PERF_PRESET")
	if preset.is_empty():
		preset = "medium"
	print("QUALITY_ACTIVITY_START preset=%s windowed=%s" % [
		preset, str(DisplayServer.get_name() != "headless")
	])
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_ProbeExit.finish_tree(self, 1, "QUALITY ACTIVITY FAILED")
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
	for _w in 40:
		await process_frame
		if not _GameplayInput.world_loading:
			break
	var player = get_first_node_in_group("player")
	var crystal = get_first_node_in_group("crystal_manager")
	if crystal and crystal.has_method("get_origin_cell") and player:
		var oc: Vector2i = crystal.get_origin_cell()
		player.voxel_position.x = float(oc.x) + 2.5
		player.voxel_position.z = float(oc.y) + 2.5
		if player.has_method("_sync_global_from_voxel"):
			player._sync_global_from_voxel()
		if player.has_method("_snap_to_ground"):
			player._snap_to_ground()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 28000:
		await process_frame
		if get_nodes_in_group("crystal_enemy").size() > 0:
			break
	var weapon = player.get_node_or_null("WeaponController") if player else null
	if weapon and weapon.has_method("set_active_hotbar_index"):
		weapon.set_active_hotbar_index(0)
	var acc: Dictionary = {}
	var n := 0
	var worst := 0.0
	var sum := 0.0
	var last_f3 := ""
	for i in 90:
		await process_frame
		if weapon and i % 8 == 0 and weapon.has_method("_try_attack"):
			var enemies: Array = get_nodes_in_group("crystal_enemy")
			if not enemies.is_empty() and enemies[0] is Node3D:
				var col: Vector2 = _WorldVisualCoords.column_from_node(enemies[0])
				var world = get_first_node_in_group("world")
				_ActionTargeting.warp_mouse_to_column(player, world, col.x, col.y)
				weapon._try_attack()
		var profiler = root.get_node_or_null("/root/PerfProfiler")
		if profiler == null or not profiler.has_method("get_snapshot"):
			continue
		if profiler.has_method("sample_scene_stats"):
			profiler.sample_scene_stats(self)
		var snap: Dictionary = profiler.get_snapshot()
		var fm := float(snap.get("frame_ms", 0.0))
		sum += fm
		if fm > worst:
			worst = fm
		n += 1
		var secs: Dictionary = snap.get("sections", {})
		for k in secs.keys():
			var e: Dictionary = secs[k]
			var ms: float = float(e.get("last_ms", 0.0))
			if ms <= 0.0 and e.has("last_us"):
				ms = float(e.last_us) / 1000.0
			if not acc.has(k):
				acc[k] = {"sum": 0.0, "max": 0.0, "n": 0}
			var a: Dictionary = acc[k]
			a.sum += ms
			a.max = maxf(float(a.max), ms)
			a.n += 1
			acc[k] = a
		var panel = get_first_node_in_group("debug_panel")
		if panel and panel.has_method("refresh_now"):
			last_f3 = str(panel.refresh_now())
	var hot: Array = []
	for k in acc.keys():
		var a: Dictionary = acc[k]
		var nn: int = maxi(int(a.n), 1)
		hot.append({"name": str(k), "avg_ms": float(a.sum) / float(nn), "max_ms": float(a.max)})
	hot.sort_custom(func(a, b): return float(a.avg_ms) > float(b.avg_ms))
	if hot.size() > 12:
		hot = hot.slice(0, 12)
	var cm = get_first_node_in_group("chunk_manager")
	var out := {
		"preset": preset,
		"mode": "activity",
		"samples": n,
		"avg_frame_ms": (sum / float(maxi(n, 1))),
		"worst_frame_ms": worst,
		"hottest": hot,
		"f3": last_f3,
		"enemies": get_nodes_in_group("crystal_enemy").size(),
		"stream": cm.get_stream_status() if cm and cm.has_method("get_stream_status") else {},
	}
	var path := scratch.path_join("quality_activity_%s.json" % preset)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "\t"))
		f.close()
		print("WROTE %s" % path)
	print("QUALITY_ACTIVITY preset=%s avg_ms=%.2f worst=%.2f enemies=%d hot=%s" % [
		preset, float(out.avg_frame_ms), worst, int(out.enemies),
		str(hot.slice(0, 5) if hot.size() >= 5 else hot)
	])
	_ProbeExit.finish_tree(self, 0, "All quality activity OK")
