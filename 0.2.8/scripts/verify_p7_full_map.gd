extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _LiveWorldQuery = preload("res://helpers/live_world_query.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _ValidationYard = preload("res://world/validation_yard.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ActionTargeting = preload("res://player/action_targeting.gd")


var _failed: int = 0
var _scratch: String = ""
var _windowed: bool = false
var _game: Node = null


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


func _fail(m: String) -> void:
	_failed += 1
	push_error(m)
	print("FAIL %s" % m)


func _ok(m: String) -> void:
	print("OK %s" % m)


func _run() -> void:
	_scratch = OS.get_environment("CRYSTALSTORM_SCRATCH")
	if _scratch.is_empty():
		_scratch = "C:/Users/cwith/AppData/Local/Temp/grok-goal-961e51b3a68c/implementer"
	DirAccess.make_dir_recursive_absolute(_scratch)
	_windowed = DisplayServer.get_name() != "headless"
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("no main scene")
		_finish()
		return
	_game = packed.instantiate()
	root.add_child(_game)
	var compose = _game.get_node_or_null("CompositionRoot")
	var loading = _capture_loading(compose)
	var frames := 0
	var loading_shot := false
	while frames < 3600:
		var mid := _capture_loading(compose)
		var phase := str(mid.get("phase_label", "")).to_lower()
		if str(mid.get("bake_label", "")).begins_with("Start region") or "cannot play" in phase or "nearby chunks" in phase:
			loading = mid
		if compose != null and int(compose.stage) >= compose.Stage.INITIAL_STREAM_READY:
			break
		await process_frame
		frames += 1
	if compose == null or int(compose.stage) < compose.Stage.INITIAL_STREAM_READY:
		_fail("start region not ready")
		_finish()
		return
	for _w in 30:
		await process_frame
	var map = _game.find_child("TopographicalMap", true, false)
	if map == null:
		for n in _game.get_tree().get_nodes_in_group("topographical_map"):
			map = n
	if map == null:
		_fail("no map")
		_finish()
		return
	var is_new: bool = map.has_method("get_open_metrics")
	print("P7_P version=%s" % ("new" if is_new else "old"))
	map._idle_minimap_job = {}
	map._minimap_tex = null
	map._active_map_job = {}
	map._map_job_queue.clear()
	map._rebuild_timer = 0.0
	var t0 := Time.get_ticks_usec()
	var f := 0
	while map._minimap_tex == null and f < 2000:
		await process_frame
		f += 1
	print("P7_P minimap_build_ms=%.1f frames=%d" % [(Time.get_ticks_usec() - t0) / 1000.0, f])
	_accuracy("minimap", map, map._idle_minimap_job)
	var player = _game.get_tree().get_first_node_in_group("player")
	for _w in 20:
		await process_frame
	t0 = Time.get_ticks_usec()
	map.toggle_fullscreen_map()
	var first_ms := -1.0
	var done_ms := -1.0
	var first_f := -1
	f = 0
	var canvas = map._fullscreen_rect
	while f < 4000:
		await process_frame
		f += 1
		if first_ms < 0.0 and canvas.texture != null:
			first_ms = (Time.get_ticks_usec() - t0) / 1000.0
			first_f = f
		var busy := false
		if not map._active_map_job.is_empty() and bool(map._active_map_job.get("fullscreen", false)):
			busy = true
		for q in map._map_job_queue:
			if bool(q.get("fullscreen", false)):
				busy = true
		if not busy and map._full_tex != null:
			done_ms = (Time.get_ticks_usec() - t0) / 1000.0
			break
	print("P7_P open_first_texture_ms=%.1f frames=%d full_done_ms=%.1f frames=%d" % [first_ms, first_f, done_ms, f])
	var pc: Vector2i = map._player_center_cell()
	print("P7_P player_cell=%s" % pc)
	if is_new:
		var m: Dictionary = map.get_open_metrics()
		print("P7_P metrics first_draw_ms=%.1f refined_ms=%.1f" % [float(m.first_draw_ms_x1000) / 1000.0, float(m.refined_ms_x1000) / 1000.0])
		var cov_lo: Vector2 = canvas.tex_origin
		var cov_hi: Vector2 = canvas.tex_origin + canvas.tex_span
		print("P7_P coverage x %d..%d z %d..%d" % [cov_lo.x, cov_hi.x, cov_lo.y, cov_hi.y])
		if cov_lo.x <= -1024 and cov_hi.x >= 1024 and cov_lo.y <= -1024 and cov_hi.y >= 1024:
			_ok("full map covers whole world plus border")
		else:
			_fail("coverage")
		print("P7_P shared_columns=%d" % map.shared_column_count())
		_accuracy_full(map)
		canvas.size = Vector2(800, 600)
		var z0: float = canvas.current_zoom()
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_UP
		ev.pressed = true
		ev.position = canvas.size * 0.5
		canvas._gui_input(ev)
		await process_frame
		var z1: float = canvas.current_zoom()
		print("P7_P wheel zoom %.4f -> %.4f" % [z0, z1])
		if z1 > z0 * 1.2: _ok("wheel zoom consumed by map") 
		else: _fail("wheel zoom")
		var k := InputEventKey.new()
		k.physical_keycode = KEY_MINUS
		k.keycode = KEY_MINUS
		k.pressed = true
		root.push_input(k)
		await process_frame
		print("P7_P key zoom %.4f -> %.4f" % [z1, canvas.current_zoom()])
		if canvas.current_zoom() < z1: _ok("minus key zooms out")
		else: _fail("key zoom")
		var vc0: Vector2 = canvas.view_center
		var ka := InputEventKey.new()
		ka.physical_keycode = KEY_RIGHT
		ka.keycode = KEY_RIGHT
		ka.pressed = true
		root.push_input(ka)
		await process_frame
		var drag_start: Vector2 = canvas.size * 0.5
		var dn := InputEventMouseButton.new()
		dn.button_index = MOUSE_BUTTON_LEFT
		dn.pressed = true
		dn.position = drag_start
		dn.global_position = drag_start
		canvas._gui_input(dn)
		var mv := InputEventMouseMotion.new()
		mv.relative = Vector2(-80, 40)
		mv.position = drag_start + mv.relative
		mv.global_position = mv.position
		canvas._gui_input(mv)
		var up := InputEventMouseButton.new()
		up.button_index = MOUSE_BUTTON_LEFT
		up.pressed = false
		up.position = mv.position
		up.global_position = mv.position
		canvas._gui_input(up)
		await process_frame
		print("P7_P pan view_center %s -> %s marker=%s" % [vc0, canvas.view_center, canvas.has_marker])
		if canvas.view_center.x > vc0.x + 290.0 and not canvas.has_marker: _ok("arrow and drag pan, drag sets no marker")
		else: _fail("pan")
		canvas.reset_view()
		var target := Vector2(pc.x + 40, pc.y - 25)
		var sp: Vector2 = canvas.world_to_screen(target + Vector2(0.5, 0.5))
		var c1 := InputEventMouseButton.new()
		c1.button_index = MOUSE_BUTTON_LEFT
		c1.pressed = true
		c1.position = sp
		c1.global_position = sp
		canvas._gui_input(c1)
		var c2: InputEventMouseButton = c1.duplicate()
		c2.pressed = false
		canvas._gui_input(c2)
		await process_frame
		print("P7_P click info=%s marker=%s target=%s" % [map._map_info.text, canvas.marker_cell, target])
		if canvas.has_marker and canvas.marker_cell.distance_to(target) <= 2.0 and "biome" in map._map_info.text: _ok("click gives coords biome and marker")
		else: _fail("click")
		print("P7_P border_click=%s" % map.describe_cell(Vector2i(1150, 0)))
		var pos0: Vector3 = player.get_voxel_position()
		Input.action_press("move_forward")
		for _w in 40:
			await process_frame
		Input.action_release("move_forward")
		var pos1: Vector3 = player.get_voxel_position()
		print("P7_P move_forward while open moved=%.3f" % pos0.distance_to(pos1))
		if pos0.distance_to(pos1) < 0.05: _ok("no movement leak")
		else: _fail("movement leak")
		print("P7_P paused=%s" % paused)
		map.toggle_fullscreen_map()
		await process_frame
		var q_before: int = map._map_job_queue.size()
		t0 = Time.get_ticks_usec()
		map.toggle_fullscreen_map()
		for _w in 3:
			await process_frame
		var m2: Dictionary = map.get_open_metrics()
		var full_q := 0
		for q in map._map_job_queue:
			if bool(q.get("fullscreen", false)):
				full_q += 1
		print("P7_P reopen cached=%s first_draw_ms=%.1f full_jobs_queued=%d" % [m2.cached, float(m2.first_draw_ms_x1000) / 1000.0, full_q])
		if bool(m2.cached) and full_q == 0: _ok("reopen uses cached map")
		else: _fail("reopen cache")
	else:
		var j = map._idle_minimap_job
		print("P7_P old full coverage half=%d" % (map._map_cfg().fullscreen_half_extent_cells))
	_finish()


func _accuracy(label: String, map, job: Dictionary) -> void:
	if job.is_empty() or job.get("image") == null:
		print("P7_P %s accuracy n/a" % label)
		return
	var img: Image = job.image
	var size: int = int(job.size)
	var stride: int = int(job.stride)
	var c: Vector2i = job.center
	var probe_job: Dictionary = job.duplicate()
	probe_job["column_cache"] = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var match_n := 0
	var n := 300
	for _i in n:
		var px := rng.randi_range(0, size - 1)
		var py := rng.randi_range(0, size - 1)
		var wx := c.x + (px - size / 2) * stride
		var wz := c.y + (py - size / 2) * stride
		var fresh: Color = load("res://systems/topographical_map_builder.gd")._sample_cell_fast(map._world, probe_job, wx, wz)
		var have: Color = img.get_pixel(px, py)
		if absf(fresh.r - have.r) + absf(fresh.g - have.g) + absf(fresh.b - have.b) < 0.06:
			match_n += 1
	var pc: Vector2i = map._player_center_cell()
	print("P7_P %s accuracy pixels_match=%d/%d center_offset_cells=%s stride=%d size=%d" % [label, match_n, n, (c - pc), stride, size])


func _accuracy_full(map) -> void:
	var j: Dictionary = load("res://systems/topographical_map_builder.gd").begin_job(map._world, map._crystal, Vector2i.ZERO, map._map_cfg(), true, true, 2, false, 1088, 288)
	j["image"] = _full_image(map)
	_accuracy("fullmap", map, j)


func _full_image(map) -> Image:
	var img: Image = map._full_tex.get_image()
	img.resize(288, 288, Image.INTERPOLATE_NEAREST)
	return img

func _capture_loading(compose) -> Dictionary:
	var ls = _game.find_child("LoadingScreen", true, false) if _game else null
	var phase := ""
	var bake_l := ""
	var pct := ""
	if ls:
		var ph = ls.get_node_or_null("Center/PhaseLabel")
		if ph == null:
			ph = ls.find_child("PhaseLabel", true, false)
		if ph:
			phase = str(ph.text)
		var bl = ls.find_child("BakeLabel", true, false)
		if bl:
			bake_l = str(bl.text)
		var pc = ls.find_child("Percent", true, false)
		if pc:
			pct = str(pc.text)
	return {
		"stage": int(compose.stage) if compose else -1,
		"phase_label": phase,
		"bake_label": bake_l,
		"percent": pct,
		"world_loading": _GameplayInput.world_loading,
		"progress_source": "start_region_status + fill_status",
	}


func _finish() -> void:
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "P7_P OK")
	else:
		_ProbeExit.finish_tree(self, 1, "P7_P FAILED")
