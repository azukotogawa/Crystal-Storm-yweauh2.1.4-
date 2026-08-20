extends SceneTree
## Windowed A (fill off) / C (worker fill) gameplay profile.
## B = previous main-thread fill baseline in deferred_fill_gameplay_profile.md
## Env: CRYSTALSTORM_FILL_PROFILE_PHASE=A|C  CRYSTALSTORM_FILL_PROFILE_SEC=16

const MAIN_SCENE := "res://scenes/main.tscn"
const _WorldBakeService = preload("res://world/world_bake_service.gd")
const _CrystalTextureGenerator = preload("res://systems/crystal_texture_generator.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _BuildingRegistry = preload("res://building/building_registry.gd")

const SECTION_KEYS: Array[String] = [
	"world_bake_fill", "bake_one_chunk", "chunk_apply", "stream_schedule",
	"voxel_fluid", "crystal_sim", "crystal_manager", "terrain_editor",
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
	return raw if raw == "A" or raw == "C" else "C"


func _window_sec() -> float:
	var raw := OS.get_environment("CRYSTALSTORM_FILL_PROFILE_SEC").strip_edges()
	return 16.0 if raw.is_empty() else clampf(float(raw), 8.0, 40.0)


func _run() -> void:
	var phase := _phase()
	if phase == "A":
		OS.set_environment("CRYSTALSTORM_BAKE_DEFER_FILL", "0")
	else:
		OS.set_environment("CRYSTALSTORM_BAKE_DEFER_FILL", "1")
		OS.set_environment("CRYSTALSTORM_BAKE_FILL_SYNC", "0")
	var t_boot := Time.get_ticks_msec()
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_ProbeExit.finish_tree(self, 1, "WORKER FILL PROFILE FAIL no main")
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
		_write(phase, {"ok": false, "error": "no INITIAL_STREAM_READY"})
		_ProbeExit.finish_tree(self, 1, "WORKER FILL PROFILE FAIL ready")
		return
	var player = get_first_node_in_group("player")
	var editor = get_first_node_in_group("terrain_editor")
	var cm = get_first_node_in_group("chunk_manager")
	var crystal = get_first_node_in_group("crystal_manager")
	var bake = _WorldBakeService.get_active()
	var profiler = root.get_node_or_null("/root/PerfProfiler")
	if player and ("health" in player):
		player.set("health", 1000.0)
		player.set("max_health", 1000.0)
	var gm = get_first_node_in_group("game_manager")
	if gm != null:
		if "crystal_damage_per_second" in gm:
			gm.set("crystal_damage_per_second", 0.0)
		if "run_state" in gm:
			gm.set("run_state", 0)
	_BuildingRegistry.ensure_builtins()
	if player and player.get("inventory"):
		player.inventory.add_item("wood", 400)
		player.inventory.add_item("stone", 400)
	var idle: Dictionary = await _sample("idle", _window_sec(), false, player, editor, cm, crystal, bake, profiler)
	var play: Dictionary = await _sample("play", _window_sec(), true, player, editor, cm, crystal, bake, profiler)
	var out := {
		"ok": true,
		"phase": phase,
		"ready_ms": ready_ms,
		"valid": bool(bake.valid) if bake else false,
		"bake_in_progress": bool(bake.bake_in_progress) if bake else false,
		"fill": bake.fill_status() if bake and bake.has_method("fill_status") else {},
		"last_bake": bake.last_bake_cost() if bake and bake.has_method("last_bake_cost") else {},
		"idle": idle,
		"play": play,
		"worker_fill": bake.use_worker_fill_from_env() if bake else false,
	}
	_write(phase, out)
	print("WORKER_FILL_PROFILE_OK phase=%s ready_ms=%d idle_p50=%.2f play_p50=%.2f fill_done=%s main_thread_last=%s" % [
		phase, ready_ms,
		float(idle.get("frame", {}).get("p50_ms", 0.0)),
		float(play.get("frame", {}).get("p50_ms", 0.0)),
		str(out["fill"].get("done", 0)),
		str(out["last_bake"].get("main_thread", "?")),
	])
	_ProbeExit.finish_tree(self, 0, "WORKER FILL PROFILE OK")


func _sample(name: String, sec: float, active: bool, player, editor, cm, crystal, bake, profiler) -> Dictionary:
	var frame_ms: Array[float] = []
	var bake_fill_ms: Array[float] = []
	var bake_one_ms: Array[float] = []
	var fluid_ms: Array[float] = []
	var crystal_ms: Array[float] = []
	var apply_ms: Array[float] = []
	var stream_ms: Array[float] = []
	var dig_ms: Array[float] = []
	var build_ms: Array[float] = []
	var water_ms: Array[float] = []
	var start_done := 0
	var start_completed := 0
	if bake and bake.has_method("fill_status"):
		start_done = int(bake.fill_status().get("done", 0))
		start_completed = int(bake.fill_status().get("worker_completed", 0))
	var end_ms := Time.get_ticks_msec() + int(sec * 1000.0)
	var i := 0
	while Time.get_ticks_msec() < end_ms:
		if active and player and editor:
			_play_step(i, player, editor, crystal, dig_ms, build_ms, water_ms)
		await process_frame
		i += 1
		if profiler == null or not profiler.has_method("get_snapshot"):
			continue
		var snap: Dictionary = profiler.get_snapshot()
		frame_ms.append(float(snap.get("frame_ms", 0.0)))
		var secs: Dictionary = snap.get("sections", {})
		bake_fill_ms.append(_sec(secs, "world_bake_fill"))
		bake_one_ms.append(_sec(secs, "bake_one_chunk"))
		fluid_ms.append(_sec(secs, "voxel_fluid"))
		crystal_ms.append(_sec(secs, "crystal_sim"))
		apply_ms.append(_sec(secs, "chunk_apply"))
		stream_ms.append(_sec(secs, "stream_schedule"))
	var end_done := start_done
	var end_completed := start_completed
	var util := 0.0
	if bake and bake.has_method("fill_status"):
		var st: Dictionary = bake.fill_status()
		end_done = int(st.get("done", 0))
		end_completed = int(st.get("worker_completed", 0))
		util = float(st.get("worker_util", 0.0))
	return {
		"name": name,
		"frames": frame_ms.size(),
		"frame": _dist(frame_ms),
		"world_bake_fill": _dist(bake_fill_ms),
		"bake_one_chunk_section": _dist(bake_one_ms),
		"voxel_fluid": _dist(fluid_ms),
		"crystal_sim": _dist(crystal_ms),
		"chunk_apply": _dist(apply_ms),
		"stream_schedule": _dist(stream_ms),
		"dig_ms": _dist(dig_ms),
		"build_ms": _dist(build_ms),
		"water_ms": _dist(water_ms),
		"packages_start": start_done,
		"packages_end": end_done,
		"packages_delta": end_done - start_done,
		"worker_completed_delta": end_completed - start_completed,
		"worker_util": util,
		"pkg_per_sec": float(end_done - start_done) / maxf(sec, 0.001),
	}


func _play_step(i: int, player, editor, crystal, dig_ms: Array, build_ms: Array, water_ms: Array) -> void:
	var cycle := i % 60
	var col: Vector3 = player.get_voxel_position() if player.has_method("get_voxel_position") else Vector3.ZERO
	if cycle < 12:
		player.voxel_position.x += 0.7
		if player.has_method("_sync_global_from_voxel"):
			player._sync_global_from_voxel()
	elif cycle < 24 and editor:
		var t0 := Time.get_ticks_usec()
		editor.try_dig(Vector3(floor(col.x) + float(cycle % 5) + 0.5, 0, floor(col.z) + 2.5))
		dig_ms.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	elif cycle < 34 and editor:
		var t1 := Time.get_ticks_usec()
		editor.try_build(Vector3(floor(col.x) + float(cycle % 4) + 0.5, 0, floor(col.z) + 5.5), player.get("inventory"), &"wood_wall")
		build_ms.append(float(Time.get_ticks_usec() - t1) / 1000.0)
	elif cycle < 44 and editor:
		var t2 := Time.get_ticks_usec()
		editor.try_channel_water(Vector3(floor(col.x) + float(cycle % 3) + 0.5, 0, floor(col.z) + 8.5), player.get("inventory"))
		water_ms.append(float(Time.get_ticks_usec() - t2) / 1000.0)
	elif cycle < 50 and crystal and crystal.has_method("damage_spawn_at_world"):
		crystal.damage_spawn_at_world(Vector2i(-10, 10), 3.0, 3.0)


func _sec(secs: Dictionary, key: String) -> float:
	if not secs.has(key):
		return 0.0
	return float(secs[key].get("last_ms", 0.0))


func _dist(values: Array) -> Dictionary:
	if values.is_empty():
		return {"n": 0, "avg_ms": 0.0, "p50_ms": 0.0, "p95_ms": 0.0, "max_ms": 0.0}
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
	}


func _write(phase: String, data: Dictionary) -> void:
	var text := JSON.stringify(data, "\t")
	var uf := FileAccess.open("user://deferred_fill_workers_profile_%s.json" % phase.to_lower(), FileAccess.WRITE)
	if uf:
		uf.store_string(text)
		uf.close()
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH").strip_edges()
	if scratch.is_empty():
		scratch = "C:/Users/cwith/AppData/Local/Temp/grok-goal-ee59e237bf34/implementer"
	var sf := FileAccess.open(scratch.path_join("deferred_fill_workers_profile_%s.json" % phase.to_lower()), FileAccess.WRITE)
	if sf:
		sf.store_string(text)
		sf.close()
	print("WORKER_FILL_JSON phase=%s" % phase)
