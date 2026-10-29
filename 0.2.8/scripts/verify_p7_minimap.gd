extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")
const GI = preload("res://helpers/gameplay_input.gd")


func _run() -> void:
	var tag := OS.get_environment("P7_TAG")
	var p = await C.boot(self)
	GI.world_loading = false
	GI.modal_open = false
	await C.clear_mites(self)
	var map = root.find_children("*", "", true, false).filter(func(n): return n.has_method("get_minimap_screen_rect"))[0]
	map.set_process(false)
	if "max_health" in p:
		p.max_health = 1000000.0
	var ms: Array = []
	var errs: Array = []
	var updates := 0
	var last_c = null
	var stale := 0
	var stale_runs: Array = []
	var first_ok := -1
	var tex0 = null
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var p0: Vector3 = p.global_position
	for f in 900:
		await process_frame
		p.health = p.max_health
		var t0 := Time.get_ticks_usec()
		map._process(1.0 / 60.0)
		ms.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		var pc: Vector2i = map._player_center_cell()
		var mc = map._idle_minimap_job.get("center", null) if not map._idle_minimap_job.is_empty() else null
		if map._minimap_rect.texture != tex0:
			tex0 = map._minimap_rect.texture
			updates += 1
		if mc != null:
			var e: float = (pc - mc).length()
			errs.append(e)
			if first_ok < 0 and e < 4.0:
				first_ok = f
			if e >= 4.0:
				stale += 1
			elif stale > 0:
				stale_runs.append(stale)
				stale = 0
	Input.action_release("move_forward")
	Input.action_release("sprint")
	ms.sort()
	var sum := 0.0
	for v in ms:
		sum += v
	var esum := 0.0
	var emax := 0.0
	for v in errs:
		esum += v
		emax = maxf(emax, v)
	var lmax := 0
	var lsum := 0
	for v in stale_runs:
		lmax = maxi(lmax, v)
		lsum += v
	print("P7_E tag=%s frames=900 moved_m=%.1f ms_avg=%.3f ms_p99=%.3f ms_max=%.3f tex_updates=%d center_err_avg=%.2f center_err_max=%.2f stale_runs=%d stale_avg_frames=%.1f stale_max_frames=%d first_accurate_frame=%d" % [tag, (p.global_position - p0).length(), sum / ms.size(), ms[int(ms.size() * 0.99)], ms[-1], updates, esum / maxf(errs.size(), 1.0), emax, stale_runs.size(), float(lsum) / maxf(stale_runs.size(), 1.0), lmax, first_ok])
	quit()


func _init() -> void:
	call_deferred("_run")
