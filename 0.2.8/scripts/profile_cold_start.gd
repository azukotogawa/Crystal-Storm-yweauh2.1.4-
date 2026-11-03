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


var _gate_ms: int = 0


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
		if st == 4 and Time.get_ticks_msec() - _gate_ms >= 500:
			_gate_ms = Time.get_ticks_msec()
			var gcm = get_tree().get_first_node_in_group("chunk_manager")
			if gcm != null and gcm.has_method("start_region_status"):
				var gs: Dictionary = gcm.start_region_status()
				print("GATE ms=%d needed=%d resident=%d packages=%d ready=%s chunks=%d" % [_gate_ms, int(gs.get("needed", 0)), int(gs.get("resident", 0)), int(gs.get("packages", 0)), str(gs.get("ready", false)), (gcm.chunks as Dictionary).size()])
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
	if OS.get_environment("CS_REGION_BENCH") == "1":
		_region_bench()
	_ProbeExit.finish_tree(get_tree(), 0, "COLD DONE total_ms=%d" % Time.get_ticks_msec())


func _measure(player, cm, tag: String, sec: float, speed: float) -> void:
	if OS.get_environment("CS_NO_CHIP") == "1":
		_kill_chip(get_tree().root)

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
		if float(now - last) > 150000.0:
			var sbk = load("res://world/world_bake_service.gd").get_active()
			print("SPIKE proc=%.1f phys=%.1f" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0]); print("SPIKE %s ms=%.1f t=%d bake_inflight=%d chunk_tasks=%d meshq=%d pkgs=%d" % [tag, float(now - last) / 1000.0, Time.get_ticks_msec(), (sbk.get("_job_inflight") as Dictionary).size() if sbk != null else -1, (cm.get("_chunk_tasks") as Dictionary).size(), (cm.get("_mesh_completion_queue") as Array).size(), (sbk.get("_packages_known") as Dictionary).size() if sbk != null else -1])
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

func _region_bench() -> void:
	var bk = load("res://world/world_bake_service.gd").get_active()
	if bk == null or str(bk.get("package_dir")).is_empty():
		print("REGION none")
		return
	var RP = load("res://world/region_pack.gd")
	var cdir: String = str(bk.package_dir).path_join("chunks")
	var coords: Array = []
	var da := DirAccess.open(cdir)
	da.list_dir_begin()
	var n := da.get_next()
	while n != "":
		if n.ends_with(".chk"):
			var p := n.get_basename().split("_")
			coords.append(Vector2i(int(p[0]), int(p[1])))
		n = da.get_next()
	da.list_dir_end()
	var t := Time.get_ticks_usec()
	var st: Dictionary = RP.pack_dir(cdir, bk.regions_dir())
	var pack_us := Time.get_ticks_usec() - t
	RP.clear_cache()
	var raw_loose := 0
	var raw_region := 0
	var same_bytes := 0
	for c_v in coords:
		var c: Vector2i = c_v
		t = Time.get_ticks_usec()
		var a := FileAccess.get_file_as_bytes(cdir.path_join("%d_%d.chk" % [c.x, c.y]))
		raw_loose += Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		var b: PackedByteArray = RP.read_chunk_bytes(bk.regions_dir(), c)
		raw_region += Time.get_ticks_usec() - t
		if a == b:
			same_bytes += 1
	var parse_loose := 0
	var parse_region := 0
	var same_parse := 0
	var ok_region := 0
	for c_v in coords:
		var c: Vector2i = c_v
		OS.set_environment("CRYSTALSTORM_BAKE_REGION", "0")
		t = Time.get_ticks_usec()
		var d1: Dictionary = bk._read_chunk_package(c)
		parse_loose += Time.get_ticks_usec() - t
		OS.set_environment("CRYSTALSTORM_BAKE_REGION", "1")
		t = Time.get_ticks_usec()
		var d2: Dictionary = bk._read_chunk_package(c)
		parse_region += Time.get_ticks_usec() - t
		if not d2.is_empty():
			ok_region += 1
		if str(d1) == str(d2):
			same_parse += 1
	OS.set_environment("CRYSTALSTORM_BAKE_REGION", "0")
	var k := maxi(coords.size(), 1)
	print("REGION chunks=%d regions=%d pack_ms=%.1f same_bytes=%d same_parse=%d ok_region=%d raw_loose_us=%.1f raw_region_us=%.1f parse_loose_us=%.1f parse_region_us=%.1f" % [
		coords.size(), int(st.get("regions", 0)), pack_us / 1000.0, same_bytes, same_parse, ok_region,
		float(raw_loose) / k, float(raw_region) / k, float(parse_loose) / k, float(parse_region) / k])

func _kill_chip(n: Node) -> void:
	if "_bake_chip" in n and n.get("_bake_chip") != null:
		var ch = n.get("_bake_chip")
		ch.visible = false
		n.set("_bake_chip", null)
		print("CHIPKILL")
	for k in n.get_children():
		_kill_chip(k)
