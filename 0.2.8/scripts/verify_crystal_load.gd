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
var _peak_static := 0
var _prof := false
var _spikes := false
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
	call_deferred("_run")


func _mem() -> int:
	var m := OS.get_static_memory_usage()
	_peak_static = maxi(_peak_static, m)
	return m


func _run() -> void:
	var t0 := Time.get_ticks_msec()
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
	var boot_ms := Time.get_ticks_msec() - t0
	print("LOAD boot_ms=%d cells_natural=%d static_mb=%.1f" % [boot_ms, int(_crystal.covered_cells), _mem() / 1048576.0])
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


func _play() -> void:
	_hands = _Hands.new()
	var start := _col()
	var stone0 := _stone()
	var moved_max := 0.0
	var digs := 0
	var placed := 0
	var dig_gain := 0
	var hitch := 0
	var toward := await _pick_move(-start.normalized())
	var min_hp := float(_player.get("health"))
	var died_at := -1.0
	start = _col()
	var frames := int(_play_sec * 60.0)
	_last_usec = Time.get_ticks_usec()
	for f in frames:
		var t := float(f) / 60.0
		var phase := fmod(t, 20.0)
		_hands.begin_tick()
		var held := PackedStringArray()
		var here := _col()
		if phase < 9.0:
			held.append(toward)
		elif phase < 10.0:
			held.append(toward)
		elif phase < 14.0:
			_hands.aim_column(_player, here.x + 1.5, here.y + 1.5)
			held.append("attack")
		elif phase < 17.0:
			_hands.aim_column(_player, here.x + 2.0, here.y)
			if f % 20 == 0:
				_hands.pulse("build_place")
		else:
			held.append(toward)
		if phase >= 14.0 and phase < 14.0 + 1.0 / 60.0:
			var s := _stone()
			dig_gain += maxi(s - stone0, 0)
			digs += 1
			stone0 = s
		if phase >= 17.0 and phase < 17.0 + 1.0 / 60.0:
			var s2 := _stone()
			placed += maxi(stone0 - s2, 0)
			stone0 = s2
		_hands.set_held(held)
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := now - _last_usec
		_last_usec = now
		_frame_us.append(dt)
		if dt > 100000:
			hitch += 1
		_crystal_us.append(int(_crystal.get("_last_process_us")))
		if _spikes:
			var snap := _snapshot()
			if dt > 60000:
				_spike_rows.append([dt, t, int(_crystal.get("_last_process_us")), int(_crystal.get("_last_tick_us")), snap, _snap_prev])
			_snap_prev = snap
		_tick_us.append(int(_crystal.get("_last_tick_us")))
		min_hp = minf(min_hp, float(_player.get("health")))
		if paused and died_at < 0.0:
			died_at = t
		moved_max = maxf(moved_max, _col().distance_to(start))
		if f % 300 == 0:
			print("PLAY paused=%s blocked=%s fwd=%s t=%.0f pos=%.1f,%.1f stone=%d dirt=%d hp=%.0f cells=%d static_mb=%.1f" % [str(paused), str(_GI.blocks_actions()), str(Input.is_action_pressed("move_forward")), t, _col().x, _col().y, _stone(), _count("dirt"), float(_player.get("health")), int(_crystal.covered_cells), _mem() / 1048576.0])
	_hands.release_all()
	print("PLAYER dir=%s min_hp=%.1f died_at=%.1f moved_max=%.1f dig_windows=%d stone_from_dig=%d stone_spent_placing=%d hitches_over_100ms=%d" % [toward, min_hp, died_at, moved_max, digs, dig_gain, placed, hitch])


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
