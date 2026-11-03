extends Node
## Cold-start + fly-through probe (autoload via override.cfg with run/main_scene=main.tscn). Env: CS_SEED, CS_FLY_SEC (default 20), CS_FLY_SPEED cells/s (default 24),
## CS_IDLE_SEC (default 5). Prints COLD/STAGE/FLY/BAKEPROG/CHUNKSTAT lines.

const _GI = preload("res://helpers/gameplay_input.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _Worlds = preload("res://systems/world_manager.gd")
const MAIN_SCENE := "res://scenes/main.tscn"

var _first_frame_ms := -1


func _init() -> void:
	if OS.get_environment("CS_SEED") != "":
		_Worlds.start_fresh_run(int(OS.get_environment("CS_SEED")))
	else:
		_Worlds.start_fresh_run()


func _ready() -> void:
	call_deferred("_run")


func _envf(k: String, d: float) -> float:
	var r := OS.get_environment(k)
	return float(r) if r.is_valid_float() else d


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	print("COLD script_start_ms=%d" % t0)
	var compose = null
	var last_stage := -1
	var frames := 0
	while frames < 200000:
		await get_tree().process_frame
		if _first_frame_ms < 0:
			_first_frame_ms = Time.get_ticks_msec()
			print("COLD first_frame_ms=%d" % _first_frame_ms)
		frames += 1
		if compose == null:
			compose = get_tree().get_first_node_in_group("composition_root")
		var st := int(compose.stage) if compose != null else -1
		if st != last_stage:
			print("STAGE %d ms=%d" % [st, Time.get_ticks_msec()])
			last_stage = st
		if st >= 9:
			_ProbeExit.finish_tree(get_tree(), 1, "COLD FAIL stage=failed")
			return
		if st >= 5 and not _GI.blocks_actions():
			break
	var player = get_tree().get_first_node_in_group("player")
	var cm = get_tree().get_first_node_in_group("chunk_manager")
	if player == null or cm == null:
		_ProbeExit.finish_tree(get_tree(), 1, "COLD FAIL no player")
		return
	var play_ms := Time.get_ticks_msec()
	var resident := (cm.chunks as Dictionary).size()
	print("COLD playable_ms=%d frames=%d resident=%d" % [play_ms, frames, resident])
	_chunk_stat(cm, "playable")
	_bake_prog("playable")
	player.set("dev_god", true)
	await _measure(player, cm, "IDLE", _envf("CS_IDLE_SEC", 5.0), 0.0)
	await _measure(player, cm, "FLY", _envf("CS_FLY_SEC", 20.0), _envf("CS_FLY_SPEED", 24.0))
	_chunk_stat(cm, "end")
	_bake_prog("end")
	_ProbeExit.finish_tree(get_tree(), 0, "COLD DONE total_ms=%d" % Time.get_ticks_msec())


func _measure(player, cm, tag: String, sec: float, speed: float) -> void:
	var dts := PackedFloat64Array()
	var world = cm.get("world")
	var b0 := _bake_done()
	var t_start := Time.get_ticks_usec()
	var last := t_start
	var v: Vector3 = player.get_voxel_position()
	var x0 := v.x
	while float(Time.get_ticks_usec() - t_start) < sec * 1000000.0:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		dts.append(float(now - last) / 1000.0)
		last = now
		if speed > 0.0:
			var wx := x0 + speed * float(now - t_start) / 1000000.0
			var wz := v.z
			var sy := v.y
			if world != null and world.has_method("get_surface_height"):
				sy = float(world.get_surface_height(wx, wz)) + 2.0
			player.voxel_position = Vector3(wx, sy, wz)
			if player.has_method("_sync_global_from_voxel"):
				player._sync_global_from_voxel()
			if "velocity" in player:
				player.velocity = Vector3.ZERO
	var s := dts.duplicate()
	s.sort()
	var n := s.size()
	var over33 := 0
	var over50 := 0
	var sum := 0.0
	for d in s:
		sum += d
		if d > 33.3:
			over33 += 1
		if d > 50.0:
			over50 += 1
	var b1 := _bake_done()
	print("%s n=%d sec=%.1f avg_ms=%.2f p50_ms=%.2f p95_ms=%.2f p99_ms=%.2f max_ms=%.2f over33=%d over50=%d baked=%d resident=%d" % [
		tag, n, sec, sum / maxf(n, 1), s[n / 2] if n > 0 else 0.0, s[mini(n - 1, int(n * 0.95))] if n > 0 else 0.0,
		s[mini(n - 1, int(n * 0.99))] if n > 0 else 0.0, s[n - 1] if n > 0 else 0.0, over33, over50, b1 - b0,
		(cm.chunks as Dictionary).size()])


func _bake_done() -> int:
	var bk = load("res://world/world_bake_service.gd").get_active()
	return int(bk.get("_fill_done")) if bk != null else 0


func _chunk_stat(cm, tag: String) -> void:
	var wn := int(cm.get("stat_worker_n"))
	var mn := int(cm.get("stat_main_n"))
	var un := int(cm.get("stat_upload_n"))
	print("CHUNKSTAT %s worker_n=%d worker_avg_ms=%.2f main_n=%d main_avg_ms=%.2f upload_n=%d upload_avg_ms=%.2f worker_total_ms=%.1f" % [
		tag, wn, float(cm.get("stat_worker_us")) / 1000.0 / maxf(wn, 1), mn, float(cm.get("stat_main_us")) / 1000.0 / maxf(mn, 1),
		un, float(cm.get("stat_upload_us")) / 1000.0 / maxf(un, 1), float(cm.get("stat_worker_us")) / 1000.0])


func _bake_prog(tag: String) -> void:
	var bk = load("res://world/world_bake_service.gd").get_active()
	if bk == null:
		print("BAKEPROG %s none" % tag)
		return
	print("BAKEPROG %s t_ms=%d done=%d total=%d active=%s submits=%d completed=%d bake_one=%d" % [
		tag, Time.get_ticks_msec(), int(bk.get("_fill_done")), int(bk.get("_fill_total")), str(bk.get("bake_in_progress")),
		int(bk.get("budget_submits")), int(bk.get("worker_jobs_completed")), int(bk.get("bake_one_count"))])
	print("BUDGET %s pkgs=%d workers=%d peak=%d target_ms=%.2f up=%d down=%d skip_stream=%d skip_frame=%d skip_load=%d" % [
		tag, (bk.get("_packages_known") as Dictionary).size(), int(bk.get("budget_workers")), int(bk.get("budget_workers_peak")), float(bk.get("budget_target_ms")),
		int(bk.get("budget_ramp_up")), int(bk.get("budget_ramp_down")), int(bk.get("budget_skips_stream")), int(bk.get("budget_skips_frame")), int(bk.get("budget_skips_load"))])