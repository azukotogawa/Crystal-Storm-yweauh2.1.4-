extends SceneTree
## Windowed production gameplay profile of background world-bake fill.
## Measurement only. Does not change bake or gameplay architecture.
## Env:
##   CRYSTALSTORM_FILL_PROFILE_PHASE=A|BC
##   CRYSTALSTORM_FILL_PROFILE_SEC=20
## Writes user://deferred_fill_profile_<phase>.json

const MAIN_SCENE := "res://scenes/main.tscn"
const _WorldBakeService = preload("res://world/world_bake_service.gd")
const _CrystalTextureGenerator = preload("res://systems/crystal_texture_generator.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _BuildingRegistry = preload("res://building/building_registry.gd")

const SECTION_KEYS: Array[String] = [
	"world_bake_fill",
	"bake_one_chunk",
	"bake_sample",
	"bake_mesh",
	"bake_write",
	"chunk_manager",
	"chunk_mesh",
	"chunk_column",
	"chunk_apply",
	"chunk_upload",
	"stream_schedule",
	"stream_update",
	"terrain_editor",
	"voxel_fluid",
	"crystal_manager",
	"crystal_sim",
	"crystal_mesh",
	"player_physics",
]


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	if root.get_node_or_null("CrystalTextureGenerator") == null:
		var gen := _CrystalTextureGenerator.new()
		gen.name = "CrystalTextureGenerator"
		root.add_child(gen)
	call_deferred("_run")


func _phase() -> String:
	var raw := OS.get_environment("CRYSTALSTORM_FILL_PROFILE_PHASE").strip_edges().to_upper()
	if raw == "A" or raw == "BC" or raw == "T":
		return raw
	return "BC"


func _window_sec() -> float:
	var raw := OS.get_environment("CRYSTALSTORM_FILL_PROFILE_SEC").strip_edges()
	if raw.is_empty():
		return 20.0
	return clampf(float(raw), 8.0, 90.0)


func _run() -> void:
	var phase := _phase()
	var win_sec := _window_sec()
	var t_boot := Time.get_ticks_msec()
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_ProbeExit.finish_tree(self, 1, "FILL PROFILE FAIL no main")
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var ready_ms := -1
	var frames := 0
	while frames < 7200:
		if compose != null and int(compose.stage) >= compose.Stage.INITIAL_STREAM_READY:
			ready_ms = Time.get_ticks_msec() - t_boot
			break
		await process_frame
		frames += 1
	if ready_ms < 0:
		_write_fail(phase, "no INITIAL_STREAM_READY")
		_ProbeExit.finish_tree(self, 1, "FILL PROFILE FAIL no INITIAL_STREAM_READY")
		return

	var player = get_first_node_in_group("player")
	var editor = get_first_node_in_group("terrain_editor")
	var cm = get_first_node_in_group("chunk_manager")
	var crystal = get_first_node_in_group("crystal_manager")
	var world = get_first_node_in_group("world")
	var bake = _WorldBakeService.get_active()
	var profiler = root.get_node_or_null("/root/PerfProfiler")
	if player == null or cm == null:
		_write_fail(phase, "missing player/chunk_manager")
		_ProbeExit.finish_tree(self, 1, "FILL PROFILE FAIL missing nodes")
		return

	if player.has_method("take_damage") or "health" in player:
		player.set("health", maxf(float(player.get("max_health")), 1000.0))
		player.set("max_health", maxf(float(player.get("max_health")), 1000.0))
	var gm = get_first_node_in_group("game_manager")
	if gm != null and "crystal_damage_per_second" in gm:
		gm.set("crystal_damage_per_second", 0.0)
	if gm != null and "run_state" in gm:
		gm.set("run_state", 0)
	_BuildingRegistry.ensure_builtins()
	var inv = player.get("inventory") if player else null
	if inv:
		inv.add_item("wood", 400)
		inv.add_item("stone", 400)

	var boot := {
		"phase": phase,
		"ready_ms": ready_ms,
		"valid": bool(bake.valid) if bake else false,
		"bake_in_progress": bool(bake.bake_in_progress) if bake else false,
		"fill": bake.fill_status() if bake and bake.has_method("fill_status") else {},
		"chunks_resident": cm.chunks.size() if cm.chunks else 0,
		"defer_env": OS.get_environment("CRYSTALSTORM_BAKE_DEFER_FILL"),
		"thread_note": "tick_background_fill and _bake_one_chunk are invoked from ChunkManager._process (main thread)",
	}

	var idle: Dictionary = {}
	var play: Dictionary = {}
	if phase == "T":
		play = await _sample_window("travel", mini(win_sec, 12.0), true, player, editor, cm, crystal, world, bake, profiler)
		var hops: Array = []
		var travel_info: Dictionary = {}
		var dummy_actions := {"travel": 0}
		for _hop in 4:
			var waits: Array = []
			await _travel_step(player, cm, world, bake, travel_info, waits, dummy_actions)
			hops.append(travel_info.duplicate(true))
		if play.has("edit"):
			play["edit"]["travel"] = travel_info
			play["edit"]["travel_hops"] = hops
	else:
		idle = await _sample_window("idle", win_sec, false, player, editor, cm, crystal, world, bake, profiler)
		play = await _sample_window("play", win_sec, true, player, editor, cm, crystal, world, bake, profiler)

	var out := {
		"ok": true,
		"phase": phase,
		"boot": boot,
		"idle": idle,
		"play": play,
		"final_fill": bake.fill_status() if bake and bake.has_method("fill_status") else {},
		"final_valid": bool(bake.valid) if bake else false,
		"bake_one_count": int(bake.bake_one_count) if bake else 0,
		"last_bake": bake.last_bake_cost() if bake and bake.has_method("last_bake_cost") else {},
	}
	_write_json(phase, out)
	print("FILL_PROFILE_OK phase=%s ready_ms=%d idle_avg=%.2f play_avg=%.2f fill_ops_idle=%d fill_ops_play=%d" % [
		phase,
		ready_ms,
		float(idle.get("frame", {}).get("avg_ms", 0.0)),
		float(play.get("frame", {}).get("avg_ms", 0.0)),
		int(idle.get("bake", {}).get("ops", 0)),
		int(play.get("bake", {}).get("ops", 0)),
	])
	_ProbeExit.finish_tree(self, 0, "FILL PROFILE OK")


func _sample_window(
	name: String,
	sec: float,
	active: bool,
	player,
	editor,
	cm,
	crystal,
	world,
	bake,
	profiler
) -> Dictionary:
	var frame_ms: Array[float] = []
	var bake_tick_ms: Array[float] = []
	var bake_total_ms: Array[float] = []
	var bake_sample_ms: Array[float] = []
	var bake_mesh_ms: Array[float] = []
	var bake_write_ms: Array[float] = []
	var bake_ops_per_frame: Array[int] = []
	var bake_main_thread_n := 0
	var bake_off_thread_n := 0
	var sections: Dictionary = {}
	for key in SECTION_KEYS:
		sections[key] = []
	var dig_ms: Array[float] = []
	var build_ms: Array[float] = []
	var water_ms: Array[float] = []
	var crystal_ms: Array[float] = []
	var stream_wait_ms: Array[float] = []
	var meshq: Array[int] = []
	var streamq: Array[int] = []
	var fill_skip_meshq := 0
	var start_fill_done := 0
	if bake and bake.has_method("fill_status"):
		start_fill_done = int(bake.fill_status().get("done", 0))
	var start_count := int(bake.bake_one_count) if bake else 0
	var prev_count := start_count
	var action_ok := {"dig": 0, "build": 0, "water": 0, "crystal": 0, "move": 0, "travel": 0}
	var travel_unbaked := {}
	var end_ms := Time.get_ticks_msec() + int(sec * 1000.0)
	var i := 0
	var origin: Vector3 = player.get_voxel_position() if player and player.has_method("get_voxel_position") else Vector3.ZERO
	while Time.get_ticks_msec() < end_ms:
		if active:
			await _do_active_step(i, origin, player, editor, cm, crystal, world, bake, action_ok, travel_unbaked, dig_ms, build_ms, water_ms, crystal_ms, stream_wait_ms)
		await process_frame
		i += 1
		if profiler and profiler.has_method("get_snapshot"):
			var snap: Dictionary = profiler.get_snapshot()
			frame_ms.append(float(snap.get("frame_ms", 0.0)))
			var secs: Dictionary = snap.get("sections", {})
			for key in SECTION_KEYS:
				var ms := 0.0
				if secs.has(key):
					ms = float(secs[key].get("last_ms", 0.0))
				(sections[key] as Array).append(ms)
			var counters: Dictionary = snap.get("frame_counters", {})
			if int(counters.get("world_bake_fill_skip_meshq", 0)) > 0:
				fill_skip_meshq += 1
		if cm:
			if " _mesh_completion_queue" in cm or true:
				meshq.append(int(cm._mesh_completion_queue.size()) if "_mesh_completion_queue" in cm else 0)
				streamq.append(int(cm._stream_load_pending.size()) if "_stream_load_pending" in cm else 0)
		var ops := 0
		if bake:
			var now_count := int(bake.bake_one_count)
			if now_count > prev_count:
				ops = now_count - prev_count
				prev_count = now_count
				bake_tick_ms.append(float(bake.last_tick_us) / 1000.0)
				bake_total_ms.append(float(bake.last_one_total_us) / 1000.0)
				bake_sample_ms.append(float(bake.last_one_sample_us) / 1000.0)
				bake_mesh_ms.append(float(bake.last_one_mesh_us) / 1000.0)
				bake_write_ms.append(float(bake.last_one_write_us) / 1000.0)
				if bool(bake.last_one_main_thread):
					bake_main_thread_n += ops
				else:
					bake_off_thread_n += ops
		bake_ops_per_frame.append(ops)
	var end_fill_done := start_fill_done
	if bake and bake.has_method("fill_status"):
		end_fill_done = int(bake.fill_status().get("done", 0))
	return {
		"name": name,
		"active": active,
		"frames": frame_ms.size(),
		"seconds": sec,
		"frame": _dist(frame_ms),
		"bake": {
			"ops": int(bake.bake_one_count) - start_count if bake else 0,
			"ops_per_frame": _int_dist(bake_ops_per_frame),
			"tick_ms": _dist(bake_tick_ms),
			"one_ms": _dist(bake_total_ms),
			"sample_ms": _dist(bake_sample_ms),
			"mesh_ms": _dist(bake_mesh_ms),
			"write_ms": _dist(bake_write_ms),
			"main_thread_ops": bake_main_thread_n,
			"off_thread_ops": bake_off_thread_n,
			"fill_done_start": start_fill_done,
			"fill_done_end": end_fill_done,
			"fill_skip_meshq_frames": fill_skip_meshq,
		},
		"sections": _section_dists(sections),
		"edit": {
			"dig_ms": _dist(dig_ms),
			"build_ms": _dist(build_ms),
			"water_ms": _dist(water_ms),
			"crystal_ms": _dist(crystal_ms),
			"stream_wait_ms": _dist(stream_wait_ms),
			"actions": action_ok,
			"travel": travel_unbaked,
		},
		"queues": {
			"meshq": _int_dist(meshq),
			"streamq": _int_dist(streamq),
		},
	}


func _do_active_step(
	i: int,
	origin: Vector3,
	player,
	editor,
	cm,
	crystal,
	world,
	bake,
	action_ok: Dictionary,
	travel_unbaked: Dictionary,
	dig_ms: Array,
	build_ms: Array,
	water_ms: Array,
	crystal_ms: Array,
	stream_wait_ms: Array
) -> void:
	var cycle := i % 90
	var col: Vector3 = player.get_voxel_position() if player.has_method("get_voxel_position") else player.global_position
	if cycle < 18:
		# Cross chunk boundaries with repeated small steps.
		player.voxel_position.x += 0.85
		if player.has_method("_sync_global_from_voxel"):
			player._sync_global_from_voxel()
		action_ok["move"] = int(action_ok["move"]) + 1
	elif cycle < 36 and editor:
		var wx := int(floor(col.x)) + (cycle % 6)
		var wz := int(floor(col.z)) + 2
		var t0 := Time.get_ticks_usec()
		var ok: bool = editor.try_dig(Vector3(float(wx) + 0.5, 0.0, float(wz) + 0.5))
		dig_ms.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		if ok:
			action_ok["dig"] = int(action_ok["dig"]) + 1
	elif cycle < 50 and editor:
		var inv = player.get("inventory")
		var wx2 := int(floor(col.x)) + (cycle % 5)
		var wz2 := int(floor(col.z)) + 5
		var t1 := Time.get_ticks_usec()
		var bok: bool = editor.try_build(Vector3(float(wx2) + 0.5, 0.0, float(wz2) + 0.5), inv, &"wood_wall")
		build_ms.append(float(Time.get_ticks_usec() - t1) / 1000.0)
		if bok:
			action_ok["build"] = int(action_ok["build"]) + 1
	elif cycle < 62 and editor:
		var inv2 = player.get("inventory")
		var wx3 := int(floor(col.x)) + (cycle % 4)
		var wz3 := int(floor(col.z)) + 8
		var t2 := Time.get_ticks_usec()
		var wok: bool = editor.try_channel_water(Vector3(float(wx3) + 0.5, 0.0, float(wz3) + 0.5), inv2)
		water_ms.append(float(Time.get_ticks_usec() - t2) / 1000.0)
		if wok:
			action_ok["water"] = int(action_ok["water"]) + 1
	elif cycle < 72 and crystal and crystal.has_method("damage_spawn_at_world"):
		var t3 := Time.get_ticks_usec()
		var cok: bool = crystal.damage_spawn_at_world(Vector2i(0, 0), 4.0, 3.0)
		if not cok:
			var pc := Vector2i(int(floor(col.x)), int(floor(col.z)))
			cok = crystal.damage_spawn_at_world(pc, 4.0, 4.0)
		crystal_ms.append(float(Time.get_ticks_usec() - t3) / 1000.0)
		if cok:
			action_ok["crystal"] = int(action_ok["crystal"]) + 1
	elif cycle == 80:
		await _travel_step(player, cm, world, bake, travel_unbaked, stream_wait_ms, action_ok)


func _travel_step(player, cm, world, bake, travel_unbaked: Dictionary, stream_wait_ms: Array, action_ok: Dictionary) -> void:
	var start: Vector3 = player.get_voxel_position()
	var scx := int(floor(start.x / 16.0))
	var scz := int(floor(start.z / 16.0))
	var dest := Vector2i(scx + 4, scz)
	var unbaked := false
	if bake:
		for step in range(2, 24):
			var cand := Vector2i(scx + step, scz)
			if bake.has_method("coord_in_package") and not bake.coord_in_package(cand):
				break
			if bake.has_method("package_ready") and not bake.package_ready(cand):
				dest = cand
				unbaked = true
				break
			dest = cand
		if bake.has_method("coord_in_package") and not bake.coord_in_package(dest):
			dest = Vector2i(scx, scz)
	var wx := dest.x * 16 + 8
	var wz := dest.y * 16 + 8
	var y := start.y
	if world and world.has_method("get_surface_height"):
		y = float(world.get_surface_height(float(wx), float(wz))) + 1.0
	player.voxel_position = Vector3(float(wx) + 0.5, y, float(wz) + 0.5)
	if player.has_method("_sync_global_from_voxel"):
		player._sync_global_from_voxel()
	var t0 := Time.get_ticks_msec()
	var resident := false
	var void_like := false
	for _w in 180:
		if cm and cm.chunks.has(dest):
			resident = true
			var view = cm.chunks[dest]
			if view and "chunk_data" in view and view.chunk_data:
				var src := ""
				if bake:
					src = str(bake.last_column_source)
				if src == "blocked" or src == "empty":
					void_like = true
			break
		await process_frame
	var wait := float(Time.get_ticks_msec() - t0)
	stream_wait_ms.append(wait)
	action_ok["travel"] = int(action_ok["travel"]) + 1
	travel_unbaked["attempted"] = true
	travel_unbaked["dest"] = [dest.x, dest.y]
	travel_unbaked["was_unbaked"] = unbaked
	travel_unbaked["became_resident"] = resident
	travel_unbaked["void_like"] = void_like
	travel_unbaked["wait_ms"] = wait
	if bake and bake.has_method("package_ready"):
		travel_unbaked["package_ready_after"] = bool(bake.package_ready(dest))
	if bake:
		travel_unbaked["ondemand_us"] = int(bake.last_ondemand_us)
		travel_unbaked["last_source"] = str(bake.last_one_source)


func _dist(values: Array) -> Dictionary:
	if values.is_empty():
		return {"n": 0, "avg_ms": 0.0, "p50_ms": 0.0, "p95_ms": 0.0, "max_ms": 0.0, "min_ms": 0.0}
	var copy: Array = values.duplicate()
	copy.sort()
	var sum := 0.0
	for v in copy:
		sum += float(v)
	var n := copy.size()
	return {
		"n": n,
		"avg_ms": sum / float(n),
		"p50_ms": float(copy[int(float(n - 1) * 0.50)]),
		"p95_ms": float(copy[int(float(n - 1) * 0.95)]),
		"max_ms": float(copy[n - 1]),
		"min_ms": float(copy[0]),
	}


func _int_dist(values: Array) -> Dictionary:
	if values.is_empty():
		return {"n": 0, "avg": 0.0, "max": 0, "sum": 0}
	var sum := 0
	var mx := 0
	for v in values:
		sum += int(v)
		mx = maxi(mx, int(v))
	return {"n": values.size(), "avg": float(sum) / float(values.size()), "max": mx, "sum": sum}


func _section_dists(sections: Dictionary) -> Dictionary:
	var out := {}
	for key in sections.keys():
		out[key] = _dist(sections[key])
	return out


func _write_json(phase: String, data: Dictionary) -> void:
	var text := JSON.stringify(data, "\t")
	var path := "user://deferred_fill_profile_%s.json" % phase.to_lower()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
	var abs_path := ProjectSettings.globalize_path(path)
	print("FILL_PROFILE_JSON=%s" % abs_path)


func _write_fail(phase: String, reason: String) -> void:
	_write_json(phase, {"ok": false, "phase": phase, "error": reason})
