extends SceneTree

const _Hands = preload("res://scripts/honest_bot/honest_input.gd")
const _GI = preload("res://helpers/gameplay_input.gd")
const _Tutorial = preload("res://ui/tutorial_overlay.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _WorldBorder = preload("res://helpers/world_border.gd")
const _Worlds = preload("res://systems/world_manager.gd")
const MAIN_SCENE := "res://scenes/main.tscn"
const MAX_COVERAGE := 0.72
const BINS := 4096
const PATH_HALF := 30.0
const MOVES := ["move_forward", "move_back", "move_left", "move_right"]

var _pct := 0.0
var _play_sec := 120.0
var _player: Node = null
var _crystal: Node = null
var _hands = null
var _frame_us: PackedInt64Array = PackedInt64Array()
var _crystal_us: PackedInt64Array = PackedInt64Array()
var _tick_us: PackedInt64Array = PackedInt64Array()
var _last_usec := 0
var _harness_us: Array = []
var _peak_static := 0
var _prof := false
var _spikes := false
var _god := false
var _fixed: Array = []
var _spike_rows: Array = []
var _snap_prev := ""


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pct="):
			_pct = float(a.substr(6))
		elif a.begins_with("--sec="):
			_play_sec = float(a.substr(6))
		elif a == "--prof":
			_prof = true
		elif a == "--spikes":
			_spikes = true
		elif a.begins_with("--fixed="):
			for s in a.substr(8).split(","):
				_fixed.append(float(s))
		elif a == "--god":
			_god = true
	call_deferred("_run")


func _mem() -> int:
	var m := OS.get_static_memory_usage()
	_peak_static = maxi(_peak_static, m)
	return m


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	if OS.get_environment("CS_SEED") != "":
		_Worlds.start_fresh_run(int(OS.get_environment("CS_SEED")))
	else:
		_Worlds.start_fresh_run()
	var game: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while frames < 4000:
		if compose != null and int(compose.stage) >= compose.Stage.INITIAL_STREAM_READY:
			break
		await process_frame
		frames += 1
	for _w in 240:
		await process_frame
		if not _GI.blocks_actions():
			break
	_player = get_first_node_in_group("player")
	_crystal = get_first_node_in_group("crystal_manager")
	if _player == null or _crystal == null or _GI.blocks_actions():
		_ProbeExit.finish_tree(self, 1, "CRYSTAL LOAD FAIL boot")
		return
	if _god:
		_player.set("dev_god", true)
	var boot_ms := Time.get_ticks_msec() - t0
	print("LOAD boot_ms=%d cells_natural=%d static_mb=%.1f" % [boot_ms, int(_crystal.covered_cells), _mem() / 1048576.0])
	print("COLDLOAD playable_launch_ms=%d playable_script_ms=%d" % [Time.get_ticks_msec(), boot_ms])
	if OS.get_environment("CS_LOADWATCH") != "":
		await _load_watch(t0)
	var target := int(round(_pct / 100.0 * MAX_COVERAGE * float(_WorldBorder.PLAYABLE_HALF_X * 2 * _WorldBorder.PLAYABLE_HALF_Z * 2)))
	var mem_before := _mem()
	var s0 := Time.get_ticks_msec()
	if target > 0:
		var rows := _seed_rows(_crystal.get_origin_cell(), target, _col())
		var gen_ms := Time.get_ticks_msec() - s0
		var state: Dictionary = _crystal.export_state()
		state["depth"] = rows
		var i0 := Time.get_ticks_msec()
		_crystal.import_state(state)
		print("SEED target=%d rows=%d gen_ms=%d import_ms=%d" % [target, rows.size(), gen_ms, Time.get_ticks_msec() - i0])
	var settle := 0
	var last_dirty := -1
	var same := 0
	while settle < 900:
		await process_frame
		settle += 1
		var pres = _crystal.get("_presentation")
		var dirty := int(pres.dirty_chunk_count()) if pres != null else 0
		same = same + 1 if dirty == last_dirty else 0
		last_dirty = dirty
		if settle > 30 and (dirty == 0 or same > 120):
			break
	var seed_ms := Time.get_ticks_msec() - s0
	var mem_after := _mem()
	print("SEED cells=%d coverage=%.4f dirty_left=%d settle_frames=%d seed_total_ms=%d crystal_static_delta_mb=%.1f" % [
		int(_crystal.covered_cells), float(_crystal.get_coverage_ratio()), last_dirty, settle, seed_ms, (mem_after - mem_before) / 1048576.0])
	await _dismiss_tutorial()
	var fluid = _crystal.get("_sim")
	if _prof and fluid != null and fluid.has_method("set_sim_profile_enabled"):
		fluid.reset_sim_profile()
		fluid.set_sim_profile_enabled(true)
	await _play()
	if _prof and fluid != null and fluid.has_method("get_sim_profile"):
		var prof: Dictionary = fluid.get_sim_profile()
		for ph in prof.get("phases", []):
			print("PROF phase=%s total_ms=%.1f max_ms=%.2f" % [str(ph.phase), float(ph.total_us) / 1000.0, float(ph.max_us) / 1000.0])
	if _spikes:
		_print_spikes()
	_report(boot_ms + seed_ms)


func _clear_path(x: int, z: int, spawn: Vector2) -> bool:
	var p := Vector2(x, z)
	var seg := -spawn
	var t := clampf((p - spawn).dot(seg) / seg.length_squared(), 0.0, 1.0)
	return p.distance_to(spawn + seg * t) < PATH_HALF


func _seed_rows(origin: Vector2i, target: int, spawn: Vector2) -> Array:
	var noise := FastNoiseLite.new()
	noise.seed = 4242
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	var radius := int(ceil(sqrt(float(target) / PI) * 1.9)) + 8
	var xs := PackedInt32Array()
	var zs := PackedInt32Array()
	var sc := PackedFloat32Array()
	var smax := 0.0
	for z in range(origin.y - radius, origin.y + radius + 1):
		for x in range(origin.x - radius, origin.x + radius + 1):
			if not _WorldBorder.allows_crystal(float(x), float(z)) or _clear_path(x, z, spawn):
				continue
			var d := Vector2(x - origin.x, z - origin.y).length()
			var n := noise.get_noise_2d(float(x), float(z)) * 0.5 + 0.5
			var s := d / (0.35 + 1.3 * n)
			xs.append(x)
			zs.append(z)
			sc.append(s)
			smax = maxf(smax, s)
	var hist := PackedInt32Array()
	hist.resize(BINS)
	for s in sc:
		hist[mini(int(s / smax * float(BINS - 1)), BINS - 1)] += 1
	var acc := 0
	var cut := BINS - 1
	for b in BINS:
		if acc + hist[b] >= target:
			cut = b
			break
		acc += hist[b]
	var need_in_cut := target - acc
	var cut_score := float(cut + 1) / float(BINS - 1) * smax
	var rows: Array = []
	for i in sc.size():
		var b := mini(int(sc[i] / smax * float(BINS - 1)), BINS - 1)
		if b < cut or (b == cut and need_in_cut > 0):
			if b == cut:
				need_in_cut -= 1
			var t := clampf(sc[i] / cut_score, 0.0, 1.0)
			rows.append([xs[i], zs[i], lerpf(2.6, 0.25, t), -1])
	return rows


func _dismiss_tutorial() -> void:
	var open := false
	for node in root.get_children():
		if node.get_script() == _Tutorial and bool(node.visible):
			open = true
	if not open:
		return
	var h := _Hands.new()
	h.pulse("pause")
	await process_frame
	h.begin_tick()
	await process_frame
	h.pulse("pause")
	await process_frame
	h.begin_tick()


func _col() -> Vector2:
	var v: Vector3 = _player.voxel_position
	return Vector2(v.x, v.z)


func _stone() -> int:
	var inv = _player.get("inventory")
	return int(inv.count_item("stone")) if inv != null else -1


func _count(id: String) -> int:
	var inv = _player.get("inventory")
	return int(inv.count_item(id)) if inv != null else -1


func _chunk_stat(tag: String) -> void:
	var cm = _player.get("chunk_manager")
	if cm == null:
		return
	var wn := int(cm.get("stat_worker_n"))
	var mn := int(cm.get("stat_main_n"))
	var un := int(cm.get("stat_upload_n"))
	print("CHUNKSTAT %s worker_n=%d worker_avg_ms=%.2f main_n=%d main_complete_avg_ms=%.2f upload_n=%d upload_avg_ms=%.2f main_total_ms=%.1f worker_total_ms=%.1f" % [tag, wn, float(cm.get("stat_worker_us")) / 1000.0 / maxf(wn, 1), mn, float(cm.get("stat_main_us")) / 1000.0 / maxf(mn, 1), un, float(cm.get("stat_upload_us")) / 1000.0 / maxf(un, 1), (float(cm.get("stat_main_us")) + float(cm.get("stat_upload_us"))) / 1000.0, float(cm.get("stat_worker_us")) / 1000.0])


func _load_watch(t0: int) -> void:
	var cm = _player.get("chunk_manager")
	_chunk_stat("playable")
	var rd := int(cm.get("RENDER_DISTANCE"))
	for f in 7200:
		var pc := Vector2i(floori(_col().x / 16.0), floori(_col().y / 16.0))
		var need := 0
		var have := 0
		for z in range(pc.y - rd, pc.y + rd + 2):
			for x in range(pc.x - rd, pc.x + rd + 2):
				if cm.call("_WorldBakeService_is_outside", Vector2i(x, z)):
					continue
				need += 1
				if cm.call("_is_chunk_resident", Vector2i(x, z)):
					have += 1
		var pend := (cm.get("_chunk_tasks") as Dictionary).size() + (cm.get("_mesh_completion_queue") as Array).size() + (cm.get("_stream_load_pending") as Dictionary).size()
		if have >= need and pend == 0:
			print("NEARLOAD rd=%d need=%d have=%d launch_ms=%d after_playable_ms=%d frames=%d" % [rd, need, have, Time.get_ticks_msec(), Time.get_ticks_msec() - t0, f])
			_chunk_stat("nearload")
			return
		if f % 600 == 0:
			print("NEARWAIT rd=%d need=%d have=%d pend=%d" % [rd, need, have, pend])
		await process_frame
	print("NEARLOAD TIMEOUT rd=%d" % rd)
	_chunk_stat("timeout")


func _bake_prog(tag: String) -> void:
	var bk = load("res://world/world_bake_service.gd").get_active()
	if bk == null:
		print("BAKEPROG %s none t_ms=%d" % [tag, Time.get_ticks_msec()])
		return
	print("BAKEPROG %s t_ms=%d done=%d total=%d active=%s submits=%d skip_frame=%d skip_move=%d skip_load=%d completed=%d" % [tag, Time.get_ticks_msec(), int(bk.get("_fill_done")), int(bk.get("_fill_total")), str(bk.get("bake_in_progress")), int(bk.get("budget_submits")), int(bk.get("budget_skips_frame")), int(bk.get("budget_skips_move")), int(bk.get("budget_skips_load")), int(bk.get("worker_jobs_completed"))])


func _play() -> void:
	var hitch := 0
	var min_hp := float(_player.get("health"))
	if _fixed.size() == 3:
		_player.set("voxel_position", Vector3(_fixed[0], _fixed[2] + 3.0, _fixed[1]))
		if _player.has_method("_sync_global_from_voxel"):
			_player.call("_sync_global_from_voxel")
	_cs_light()
	if OS.get_environment("CS_NOPROPS") != "":
		var cmp = _player.get("chunk_manager")
		var np = cmp.get("_near_props") if cmp != null else null
		if np != null:
			np.set_process(false)
			np.visible = false
			for ch in np.get_children():
				ch.queue_free()
		print("ABL noprops np=", np)
	if OS.get_environment("CS_NOFILL") != "":
		var bkh = load("res://world/world_bake_service.gd").get_active()
		if bkh != null:
			bkh.set("hold_fill", true)
		print("ABL nofill bk=", bkh)
	if OS.get_environment("CS_RD0") != "":
		var cmr = _player.get("chunk_manager")
		cmr.set("RENDER_DISTANCE", int(OS.get_environment("CS_RD0")))
		cmr.set("_last_chunk_key", Vector2i(-99999, -99999))
		var pc := Vector2i(floori(_col().x / 16.0), floori(_col().y / 16.0))
		cmr.call("update_stream", pc.x, pc.y)
		for _w in 600:
			await process_frame
		print("ABL rd0=", cmr.get("RENDER_DISTANCE"), " n=", (cmr.get("chunks") as Dictionary).size())
	var zz := OS.get_environment("CS_ZOOM")
	if zz != "":
		var cn: Node = get_root().get_camera_3d()
		while cn != null and not ("zoom_level" in cn):
			cn = cn.get_parent()
		if cn != null:
			cn.set("zoom_level", float(zz))
			print("ZOOM set ", zz, " on ", cn.name)
	for _w in 900:
		await process_frame
	var start := _col()
	print("FIXED warm pos=%.1f,%.1f y=%.1f static_mb=%.1f" % [start.x, start.y, float(_player.voxel_position.y), _mem() / 1048576.0])
	_cs_light()
	await process_frame
	_cs_eff("warm")
	_peak_static = 0
	var moved_max := 0.0
	var frames := int(_play_sec * 60.0)
	_bake_prog("start")
	_last_usec = Time.get_ticks_usec()
	for f in frames:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := now - _last_usec
		_last_usec = now
		_frame_us.append(dt)
		_pm_sample()
		if dt > 100000:
			hitch += 1
		_crystal_us.append(int(_crystal.get("_last_process_us")))
		_tick_us.append(int(_crystal.get("_last_tick_us")))
		min_hp = minf(min_hp, float(_player.get("health")))
		moved_max = maxf(moved_max, _col().distance_to(start))
		if f % 300 == 0:
			print("PLAY t=%.0f pos=%.1f,%.1f hp=%.0f cells=%d static_mb=%.1f" % [float(f) / 60.0, _col().x, _col().y, float(_player.get("health")), int(_crystal.covered_cells), _mem() / 1048576.0])
			_last_usec = Time.get_ticks_usec()
	_bake_prog("end")
	_chunk_stat("end")
	print("PLAYER dir=fixed min_hp=%.1f died_at=-1.0 moved_max=%.1f dig_windows=0 stone_from_dig=0 stone_spent_placing=0 hitches_over_100ms=%d" % [min_hp, moved_max, hitch])
	_cs_eff("end")
	if OS.get_environment("CS_CROSS") != "":
		await _cs_cross()
	await _cs_geo()


func _pick_move(goal: Vector2) -> String:
	var best := "move_forward"
	var best_dot := -2.0
	for m in MOVES:
		var a := _col()
		for _i in 24:
			_hands.set_held(PackedStringArray([m]))
			await process_frame
		_hands.set_held(PackedStringArray())
		for _i in 6:
			await process_frame
		var d := _col() - a
		if d.length() > 0.5 and d.normalized().dot(goal) > best_dot:
			best_dot = d.normalized().dot(goal)
			best = m
	print("MOVE pick=%s dot=%.2f" % [best, best_dot])
	return best


func _stats(a: PackedInt64Array) -> Array:
	var v := Array(a)
	v.sort()
	var sum := 0
	for x in v:
		sum += int(x)
	var n := maxi(v.size(), 1)
	return [float(sum) / n / 1000.0, float(v[int(n * 0.99) - 1 if n > 1 else 0]) / 1000.0, float(v[n - 1]) / 1000.0]


func _report(load_ms: int) -> void:
	_pm_report()
	var fr := _stats(_frame_us)
	var cr := _stats(_crystal_us)
	var tk := _stats(_tick_us)
	print("RESULT pct=%.1f load_ms=%d cells=%d frame_avg_ms=%.2f frame_p99_ms=%.2f frame_max_ms=%.2f crystal_proc_avg_ms=%.3f crystal_proc_max_ms=%.2f sim_tick_avg_ms=%.3f sim_tick_max_ms=%.2f peak_static_mb=%.1f" % [
		_pct, load_ms, int(_crystal.covered_cells), fr[0], fr[1], fr[2], cr[0], cr[2], tk[0], tk[2], _peak_static / 1048576.0])
	_ProbeExit.finish_tree(self, 0, "CRYSTAL LOAD OK")


func _snapshot() -> String:
	var p = root.get_node_or_null("PerfProfiler")
	if p == null:
		return ""
	var parts: Array = []
	var secs: Dictionary = p.get("_sections")
	for k in secs:
		var us := int(secs[k].get("last_us", 0))
		if us >= 3000:
			parts.append([us, "S:" + str(k)])
	var fns: Dictionary = p.get("_funcs")
	for k in fns:
		var us2 := int(fns[k].get("last_us", 0))
		if us2 >= 3000:
			parts.append([us2, "F:" + str(k)])
	parts.sort_custom(func(a, b): return a[0] > b[0])
	var out := PackedStringArray()
	for i in mini(parts.size(), 10):
		out.append("%s=%.1f" % [parts[i][1], float(parts[i][0]) / 1000.0])
	return ",".join(out)


func _print_spikes() -> void:
	_spike_rows.sort_custom(func(a, b): return a[0] > b[0])
	for i in mini(_spike_rows.size(), 30):
		var r: Array = _spike_rows[i]
		print("SPIKE dt_ms=%.1f t=%.1f crystal_ms=%.1f tick_ms=%.1f now[%s] prev[%s]" % [float(r[0]) / 1000.0, r[1], float(r[2]) / 1000.0, float(r[3]) / 1000.0, r[4], r[5]])
	print("SPIKE_COUNT over60=%d" % _spike_rows.size())


func _cs_wenv() -> Environment:
	var we = get_root().find_child("WorldEnvironment", true, false)
	if we is WorldEnvironment:
		return (we as WorldEnvironment).environment
	return null


func _cs_dl() -> DirectionalLight3D:
	return get_root().find_child("DirectionalLight3D", true, false) as DirectionalLight3D


func _cs_light() -> void:
	var l := OS.get_environment("CS_L")
	var all := l.contains("all") or l.contains("full")
	var full := l.contains("full")
	if full or l.contains("fogd"):
		var e0 := _cs_wenv()
		if e0 != null:
			e0.fog_density = 0.00032
	if full or l.contains("blur"):
		var d0 := _cs_dl()
		if d0 != null:
			d0.shadow_blur = 0.55
	var env := _cs_wenv()
	if env != null:
		if all or l.contains("scat"):
			env.fog_sun_scatter = 0.08
		if all or l.contains("aer"):
			env.fog_aerial_perspective = 0.12
		if all or l.contains("ssao"):
			env.ssao_light_affect = 0.0
		if all or l.contains("fogc"):
			env.fog_light_color = Color(0.72, 0.78, 0.9, 1)
	if all or l.contains("sun"):
		var s := Vector3(0.55, 0.82, 0.38)
		RenderingServer.global_shader_parameter_set("terrain_sun_dir", s)
		var dl := _cs_dl()
		if dl != null:
			var o := dl.global_transform.origin
			dl.global_transform = Transform3D(Basis.looking_at(Vector3(0.82273, 0.440574, -0.359179), Vector3.UP), o)


func _cs_eff(tag: String) -> void:
	var cm = get_root().find_child("ChunkManager", true, false)
	if cm == null:
		var g := get_nodes_in_group("chunk_manager")
		cm = g[0] if g.size() > 0 else null
	var rd := int(cm.get("RENDER_DISTANCE")) if cm != null else -1
	var js := -1
	var jp := -1
	var f := FileAccess.open("user://player_settings.json", FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			js = int(d.get("render_distance", -1))
			jp = int(d.get("quality_preset", -1))
	var env := _cs_wenv()
	var e := "env=null"
	if env != null:
		e = "fog=%s fog_density=%.4f scat=%.3f aer=%.3f ssao=%s ssao_la=%.3f fogc=%s" % [str(env.fog_enabled), env.fog_density, env.fog_sun_scatter, env.fog_aerial_perspective, str(env.ssao_enabled), env.ssao_light_affect, str(env.fog_light_color)]
	var dl := _cs_dl()
	var sd := "light=null"
	if dl != null:
		sd = "light_fwd=%s shadows=%s shadow_blur=%.2f" % [str(-dl.global_transform.basis.z), str(dl.shadow_enabled), dl.shadow_blur]
	print("EFFECTIVE %s CS_L=%s CS_RD=%s rd=%d json_rd=%d json_preset=%d user_dir=%s %s %s terrain_sun_dir=%s" % [tag, OS.get_environment("CS_L"), OS.get_environment("CS_RD"), rd, js, jp, OS.get_user_data_dir(), e, sd, str(RenderingServer.global_shader_parameter_get("terrain_sun_dir"))])


func _cs_geo() -> void:
	if OS.get_environment("CS_QC") != "1":
		return
	var shot := OS.get_environment("CS_SHOT")
	if shot != "":
		await process_frame
		await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(shot)
		print("CSGEO shot=%s" % shot)
	var t0 := Time.get_ticks_msec()
	var meshes := 0
	var verts := 0
	var quads := 0
	var vq := 0
	var small := 0
	var dup := 0
	var seen := {}
	var hist := {}
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		if not (mi.mesh is ArrayMesh):
			continue
		meshes += 1
		var xf := mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(s)
			var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			verts += pos.size()
			if idx.size() < 6:
				continue
			var q := 0
			while q + 5 < idx.size():
				quads += 1
				var a := xf * pos[idx[q]]
				var b := xf * pos[idx[q + 1]]
				var c := xf * pos[idx[q + 2]]
				var nrm := (b - a).cross(c - a)
				if nrm.length() > 0.0000001 and absf(nrm.normalized().y) < 0.1:
					vq += 1
					var mn := a.min(b).min(c).min(xf * pos[idx[q + 4]]).min(xf * pos[idx[q + 5]])
					var mx := a.max(b).max(c).max(xf * pos[idx[q + 4]]).max(xf * pos[idx[q + 5]])
					var hgt := snappedf(mx.y - mn.y, 0.01)
					if hgt < 0.99:
						small += 1
						hist[hgt] = int(hist.get(hgt, 0)) + 1
						var key := "%.3f,%.3f,%.3f,%.3f,%.3f,%.3f" % [mn.x, mn.y, mn.z, mx.x, mx.y, mx.z]
						if seen.has(key):
							dup += 1
						else:
							seen[key] = 1
				q += 6
	var hk := hist.keys()
	hk.sort_custom(func(x, y): return int(hist[x]) > int(hist[y]))
	var hs := ""
	for k in hk.slice(0, 6):
		hs += "%s:%d " % [str(k), int(hist[k])]
	print("CSGEO meshes=%d verts=%d quads=%d vert_quads=%d small_vert_quads=%d small_dup_positions=%d verts_per_mesh=%d quads_per_mesh=%d hist=[%s] ms=%d" % [meshes, verts, quads, vq, small, dup, verts / maxi(meshes, 1), quads / maxi(meshes, 1), hs.strip_edges(), Time.get_ticks_msec() - t0])
	var mpc = load("res://world/mesh_plan_cache.gd").get_active()
	if mpc != null:
		print("PLANSTATS valid=%s streamed=%s hits=%d misses=%d" % [str(mpc.valid), str(mpc.streamed_from_bake), mpc.stats_hits, mpc.stats_misses])


func _cs_cross() -> void:
	var base := OS.get_environment("CS_SHOT").get_basename()
	var cm0: Node = _player.get("chunk_manager")
	var rdv := OS.get_environment("CS_RD")
	if cm0 != null and rdv != "":
		cm0.set("RENDER_DISTANCE", int(rdv))
		cm0.call("update_stream", int(floor(_col().x / 16.0)), int(floor(_col().y / 16.0)))
		for _w in 600:
			await process_frame
		print("CROSS rd=", cm0.get("RENDER_DISTANCE"), " n=", (cm0.get("chunks") as Dictionary).size())
	await _cs_snap(base + "_cross0.png")
	for i in 3:
		var vp: Vector3 = _player.get("voxel_position")
		_player.set("voxel_position", vp + Vector3(16, 0, 0))
		if _player.has_method("_sync_global_from_voxel"):
			_player.call("_sync_global_from_voxel")
		var cm: Node = _player.get("chunk_manager")
		print("CROSS cm=", cm)
		if cm != null:
			print("CROSS paused=", cm.get("stream_paused"))
			cm.set("stream_paused", false)
			cm.call("update_stream", int(floor(_col().x / 16.0)), int(floor(_col().y / 16.0)))
		print("CROSS step=%d col=%.1f,%.1f" % [i + 1, _col().x, _col().y])
		var hmax := 0
		var hsum := 0
		var hbig := 0
		var tprev := Time.get_ticks_usec()
		for _w in 300:
			await process_frame
			var tnow := Time.get_ticks_usec()
			var dt := tnow - tprev
			tprev = tnow
			hmax = maxi(hmax, dt)
			hsum += dt
			if dt > 50000:
				hbig += 1
		print("CROSS hitch step=%d max_ms=%.1f avg_ms=%.1f frames_over_50ms=%d" % [i + 1, hmax / 1000.0, hsum / 300000.0, hbig])
		print("CROSS after col=", _col(), " key=", cm.get("_last_chunk_key") if cm != null else null, " lodc=", ChunkSurfaceMeshBuilder.wave_lod_center, " n=", (cm.get("chunks") as Dictionary).size(), " r=", ChunkSurfaceMeshBuilder.WAVE_LOD_R, " sample=", (cm.get("chunks") as Dictionary).keys().slice(0, 4))
		await _cs_snap(base + "_cross%d.png" % (i + 1))
	var cam: Camera3D = get_root().get_camera_3d()
	if cam != null:
		cam.set("zoom_level", 120.0)
		cam.size = 120.0
		for _w in 240:
			await process_frame
		cam.size = 120.0
		await process_frame
		await _cs_snap(base + "_far.png")
		print("FARCAM size=", cam.size)


func _cs_snap(p: String) -> void:
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(p)
	print("SNAP ", p)

var _pm := {}


func _pm_add(k: String, v: float) -> void:
	if not _pm.has(k):
		_pm[k] = PackedFloat64Array()
	_pm[k].append(v)


func _pm_sample() -> void:
	if _pm.is_empty():
		RenderingServer.viewport_set_measure_render_time(get_root().get_viewport_rid(), true)
	var vp := get_root().get_viewport_rid()
	_pm_add("process_ms", Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_pm_add("physics_ms", Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_pm_add("render_cpu_ms", RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu())
	_pm_add("render_gpu_ms", RenderingServer.viewport_get_measured_render_time_gpu(vp))
	_pm_add("draw_calls", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_pm_add("primitives", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_pm_add("objects", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	_pm_add("nodes", Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_pm_add("vmem_mb", Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)
	var bk = load("res://world/world_bake_service.gd").get_active()
	if bk != null:
		_pm_add("fill_tick_ms", float(bk.get("last_tick_us")) / 1000.0)
		_pm_add("fill_inflight", float((bk.get("_job_inflight") as Dictionary).size()))
		_pm_add("fill_active", 1.0 if bool(bk.get("bake_in_progress")) else 0.0)
		_pm_add("fill_done", float(bk.get("_fill_done")))
		_pm_add("budget_submits", float(bk.get("budget_submits")))


func _pm_report() -> void:
	var fr := Array(_frame_us)
	fr.sort()
	if fr.size() > 0:
		print("PM frame_p95_ms=%.2f frame_p50_ms=%.2f" % [float(fr[int(fr.size() * 0.95)]) / 1000.0, float(fr[int(fr.size() * 0.5)]) / 1000.0])
	for k in _pm.keys():
		var v := Array(_pm[k])
		v.sort()
		var s := 0.0
		for x in v:
			s += float(x)
		print("PM %s avg=%.3f p50=%.3f p95=%.3f max=%.3f" % [k, s / maxf(v.size(), 1), float(v[int(v.size() * 0.5)]), float(v[int(v.size() * 0.95)]), float(v[v.size() - 1])])
	var mp = load("res://world/mesh_plan_cache.gd")
	var mpc = mp.get_active() if mp != null and mp.has_method("get_active") else null
	if mpc != null:
		print("PLANSTATS2 valid=%s hits=%d misses=%d" % [str(mpc.valid), int(mpc.stats_hits), int(mpc.stats_misses)])
	else:
		print("PLANSTATS2 none")
