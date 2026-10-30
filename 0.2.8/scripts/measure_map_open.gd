extends SceneTree

const _MapScript = preload("res://ui/topographical_map.gd")
const _Quality = preload("res://config/performance_quality_config.gd")
const _WorldBorder = preload("res://helpers/world_border.gd")
const _Feel = preload("res://config/game_feel_config.gd")
const PLAYABLE := 1024 * 2 * 1024 * 2


class CrystalField:
	extends Node

	const _PLAYABLE := 1024 * 2 * 1024 * 2
	const _CHUNK := 16
	var _depth: Dictionary = {}
	var _chunks: Dictionary = {}

	func cell_count() -> int:
		return _depth.size()

	func coverage_ratio() -> float:
		return float(_depth.size()) / float(_PLAYABLE)

	func clear_cells() -> void:
		_depth.clear()
		_chunks.clear()

	func fill_percent(pct: float) -> int:
		clear_cells()
		if pct <= 0.0:
			return 0
		var target := int(round(pct / 100.0 * float(_PLAYABLE)))
		var radius := int(ceil(sqrt(float(target) / PI))) + 3
		var added := 0
		for z in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				if added >= target:
					return added
				if Vector2(x, z).length() > float(radius):
					continue
				if not _WorldBorder.allows_crystal(float(x), float(z)):
					continue
				var t := clampf(1.0 - Vector2(x, z).length() / float(radius), 0.0, 1.0)
				_add(x, z, lerpf(0.3, 2.4, t))
				added += 1
		return added

	func _add(x: int, z: int, depth: float) -> void:
		var pos := Vector2i(x, z)
		_depth[pos] = depth
		var c := Vector2i(floori(float(x) / float(_CHUNK)), floori(float(z) / float(_CHUNK)))
		var bucket: Dictionary = _chunks.get(c, {})
		if bucket.is_empty() and not _chunks.has(c):
			_chunks[c] = bucket
		bucket[pos] = true

	func depth_chunks_in_rect(bounds: Rect2i) -> Array:
		var out: Array = []
		var x0: int = bounds.position.x
		var y0: int = bounds.position.y
		var x1: int = x0 + bounds.size.x
		var y1: int = y0 + bounds.size.y
		if x1 <= x0 or y1 <= y0:
			return out
		for cy in range(floori(float(y0) / float(_CHUNK)), floori(float(y1 - 1) / float(_CHUNK)) + 1):
			for cx in range(floori(float(x0) / float(_CHUNK)), floori(float(x1 - 1) / float(_CHUNK)) + 1):
				var c := Vector2i(cx, cy)
				if _chunks.has(c):
					out.append(c)
		return out

	func collect_depth_chunk(chunk: Vector2i, bounds: Rect2i, out: Dictionary) -> void:
		var bucket: Dictionary = _chunks.get(chunk, {})
		var x0: int = bounds.position.x
		var y0: int = bounds.position.y
		var x1: int = x0 + bounds.size.x
		var y1: int = y0 + bounds.size.y
		for pos_variant in bucket:
			var pos: Vector2i = pos_variant
			if pos.x < x0 or pos.y < y0 or pos.x >= x1 or pos.y >= y1:
				continue
			var depth: float = float(_depth[pos])
			if depth >= 0.04:
				out[pos] = depth

	func get_active_spawns() -> Array:
		return []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var quality = _Quality.apply_preset(_Quality.Preset.MEDIUM)
	var feel = _Feel.active()
	print("SETUP preset=medium pixels=%d time_us=%d stride=%d scale=%.1f preview_ms=%d playable=%d" % [
		int(quality.map_pixels_per_frame), int(quality.map_time_budget_us), int(quality.map_sample_stride),
		float(feel.map_open_budget_scale), int(float(feel.map_preview_sec) * 1000.0), PLAYABLE,
	])
	var world := InfiniteNoiseWorld.new(12349)
	var crystal := CrystalField.new()
	crystal.add_to_group("crystal_manager")
	root.add_child(world)
	root.add_child(crystal)
	var map = _MapScript.new()
	root.add_child(map)
	await process_frame
	map._world = world
	map._crystal = crystal
	map.apply_performance_config(quality)
	map._fullscreen_rect.size = Vector2(1200, 640)
	await _bench(world)
	for pct in [0.0, 1.0, 10.0]:
		await _measure_open(map, world, crystal, pct)
	print("MAP OPEN DONE")
	quit(0)


func _bench(world: InfiniteNoiseWorld) -> void:
	var n := 400
	var coords: Array[Vector2i] = []
	for i in n:
		coords.append(Vector2i((i * 8) % 1600 - 800, (i * 5) % 1600 - 800))
	world._invalidate_height_caches()
	var t0 := Time.get_ticks_usec()
	for c in coords:
		world.get_surface_height(float(c.x), float(c.y))
	var height_us := Time.get_ticks_usec() - t0
	world._invalidate_height_caches()
	t0 = Time.get_ticks_usec()
	for c in coords:
		world.get_tile_type(float(c.x), float(c.y))
	var tile_us := Time.get_ticks_usec() - t0
	world._invalidate_height_caches()
	t0 = Time.get_ticks_usec()
	for c in coords:
		world.get_tile_type(float(c.x), float(c.y))
		world.get_surface_height(float(c.x), float(c.y))
	var pair_us := Time.get_ticks_usec() - t0
	world._invalidate_height_caches()
	for i in 12290:
		world.get_surface_height(float(-40000 - i), -3.0)
	t0 = Time.get_ticks_usec()
	for c in coords:
		world.get_tile_type(float(c.x), float(c.y))
		world.get_surface_height(float(c.x), float(c.y))
	var after_cap_us := Time.get_ticks_usec() - t0
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	t0 = Time.get_ticks_usec()
	for i in n:
		image.set_pixel(i % 64, int(i / 64) % 64, Color(0.2, 0.4, 0.3, 1.0))
	var pixel_us := Time.get_ticks_usec() - t0
	print("BENCH n=%d height_us=%d tile_us=%d pair_us=%d pair_after_cap_us=%d set_pixel_us=%d per_pair_us=%.1f per_pair_after_cap_us=%.1f" % [
		n, height_us, tile_us, pair_us, after_cap_us, pixel_us,
		float(pair_us) / float(n), float(after_cap_us) / float(n),
	])
	world._invalidate_height_caches()


func _measure_open(map, world: InfiniteNoiseWorld, crystal: CrystalField, pct: float) -> void:
	if map.is_fullscreen_open():
		map.toggle_fullscreen_map()
	map._full_tex = null
	map._full_fine_done = false
	map._full_rev = -1
	map._shared_columns = {}
	map._shared_rev = -1
	map._idle_minimap_job = {}
	map._active_map_job = {}
	map._map_job_queue.clear()
	map._crystal_overlay_job = {}
	world._invalidate_height_caches()
	var s0 := Time.get_ticks_usec()
	var seeded := crystal.fill_percent(pct)
	print("SEED pct=%.0f cells=%d coverage=%.6f seed_ms=%d" % [
		pct, seeded, crystal.coverage_ratio(), (Time.get_ticks_usec() - s0) / 1000,
	])
	var canvas = map._fullscreen_rect
	var draws_before: int = canvas.draw_count
	map.toggle_fullscreen_map()
	var open_usec: int = Time.get_ticks_usec()
	var frames: PackedInt32Array = PackedInt32Array()
	var phases: Dictionary = {}
	var phase_frames: Dictionary = {}
	var first_image := -1
	var full_ms := -1
	var max_frame := 0
	var max_phase := ""
	var guard := 0
	while guard < 6000:
		guard += 1
		var job: Dictionary = map._active_map_job
		var phase := _phase_name(map, job)
		var f0 := Time.get_ticks_usec()
		await process_frame
		var dt := int(Time.get_ticks_usec() - f0)
		frames.append(dt)
		phases[phase] = int(phases.get(phase, 0)) + dt
		phase_frames[phase] = int(phase_frames.get(phase, 0)) + 1
		if dt > max_frame:
			max_frame = dt
			max_phase = phase
		if first_image < 0:
			var metrics: Dictionary = map.get_open_metrics()
			var stamp := int(metrics.get("first_draw_ms_x1000", -1))
			if stamp >= 0:
				first_image = int(stamp / 1000)
			elif canvas.textured_draws > 0 or (canvas.texture != null and canvas.draw_count > draws_before):
				first_image = int((Time.get_ticks_usec() - open_usec) / 1000)
		var metrics_now: Dictionary = map.get_open_metrics()
		var refined := int(metrics_now.get("refined_ms_x1000", -1))
		if refined >= 0 and map._full_fine_done and map._active_map_job.is_empty():
			full_ms = int(refined / 1000)
			break
	if full_ms < 0:
		print("OPEN pct=%.0f INCOMPLETE frames=%d first_image_ms=%d" % [pct, frames.size(), first_image])
		_print_phases(pct, phases, phase_frames)
		return
	var build_n := frames.size()
	var idle: PackedInt32Array = PackedInt32Array()
	for _i in 45:
		var f0 := Time.get_ticks_usec()
		await process_frame
		idle.append(int(Time.get_ticks_usec() - f0))
	var pan := await _input_latency(map, "pan")
	var zoom := await _input_latency(map, "zoom")
	var drag := await _drag_latency(map)
	var wheel := await _wheel_latency(map)
	var job0: Dictionary = {}
	print("OPEN pct=%.0f cells=%d first_image_ms=%d full_ms=%d build_frames=%d build_p50_ms=%.2f build_p95_ms=%.2f build_max_ms=%.2f max_phase=%s idle_p50_ms=%.2f idle_p95_ms=%.2f idle_max_ms=%.2f pan_frames=%d pan_ms=%d zoom_frames=%d zoom_ms=%d drag_frames=%d drag_ms=%d wheel_frames=%d wheel_ms=%d canvas=%s draws=%d" % [
		pct, seeded, first_image, full_ms, build_n,
		_pct(frames, 0.50) / 1000.0, _pct(frames, 0.95) / 1000.0, float(max_frame) / 1000.0, max_phase,
		_pct(idle, 0.50) / 1000.0, _pct(idle, 0.95) / 1000.0, _max(idle) / 1000.0,
		int(pan.frames), int(pan.ms), int(zoom.frames), int(zoom.ms),
		int(drag.frames), int(drag.ms), int(wheel.frames), int(wheel.ms),
		str(canvas.size), canvas.draw_count,
	])
	_print_phases(pct, phases, phase_frames)
	if map._full_tex != null:
		print("OPEN pct=%.0f tex=%dx%d" % [pct, map._full_tex.get_width(), map._full_tex.get_height()])


func _phase_name(map, job: Dictionary) -> String:
	if job.is_empty():
		if not map._map_job_queue.is_empty():
			return "queue"
		return "idle"
	var size := int(job.get("size", 0))
	if job.get("crystal_collect_pending", false) or job.has("crystal_collect_chunks"):
		return "collect_%d" % size
	return "paint_%d" % size


func _print_phases(pct: float, phases: Dictionary, phase_frames: Dictionary) -> void:
	var keys: Array = phases.keys()
	keys.sort()
	for k in keys:
		var us := int(phases[k])
		var n := int(phase_frames.get(k, 0))
		print("PHASE pct=%.0f name=%s frames=%d total_ms=%.1f avg_ms=%.2f" % [
			pct, str(k), n, float(us) / 1000.0, float(us) / float(maxi(n, 1)) / 1000.0,
		])


func _input_latency(map, kind: String) -> Dictionary:
	var canvas = map._fullscreen_rect
	var draws: int = canvas.draw_count
	var center: Vector2 = canvas.view_center
	var zoom: float = canvas.zoom
	var code := KEY_LEFT if kind == "pan" else KEY_EQUAL
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	var t0 := Time.get_ticks_usec()
	root.push_input(ev)
	Input.parse_input_event(ev)
	var frames := 0
	while frames < 6:
		frames += 1
		await process_frame
		var moved := canvas.view_center.distance_to(center) > 0.01 or absf(canvas.zoom - zoom) > 0.0001
		if moved and canvas.draw_count > draws:
			var up := ev.duplicate()
			up.pressed = false
			root.push_input(up)
			return {"frames": frames, "ms": (Time.get_ticks_usec() - t0) / 1000}
	if kind == "pan":
		canvas.pan_pixels(Vector2(64, 0))
	else:
		canvas.zoom_by(1.25, canvas.size * 0.5)
	var t1 := Time.get_ticks_usec()
	await process_frame
	return {"frames": frames + 1, "ms": (Time.get_ticks_usec() - t1) / 1000 + (t1 - t0) / 1000, "fallback": true}


func _drag_latency(map) -> Dictionary:
	var canvas = map._fullscreen_rect
	var draws: int = canvas.draw_count
	var center: Vector2 = canvas.view_center
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = canvas.size * 0.5
	canvas._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = press.position + Vector2(48, -12)
	motion.relative = Vector2(48, -12)
	var t0 := Time.get_ticks_usec()
	canvas._gui_input(motion)
	var frames := 0
	while frames < 6:
		frames += 1
		await process_frame
		if canvas.view_center.distance_to(center) > 0.01 and canvas.draw_count > draws:
			var release := press.duplicate()
			release.pressed = false
			canvas._gui_input(release)
			return {"frames": frames, "ms": (Time.get_ticks_usec() - t0) / 1000}
	return {"frames": frames, "ms": -1}


func _wheel_latency(map) -> Dictionary:
	var canvas = map._fullscreen_rect
	var draws: int = canvas.draw_count
	var zoom: float = canvas.current_zoom()
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = canvas.size * 0.5
	var t0 := Time.get_ticks_usec()
	canvas._gui_input(wheel)
	var frames := 0
	while frames < 6:
		frames += 1
		await process_frame
		if absf(canvas.current_zoom() - zoom) > 0.0001 and canvas.draw_count > draws:
			return {"frames": frames, "ms": (Time.get_ticks_usec() - t0) / 1000}
	return {"frames": frames, "ms": -1}


func _pct(samples: PackedInt32Array, q: float) -> float:
	if samples.is_empty():
		return 0.0
	var copy: Array = []
	for v in samples:
		copy.append(int(v))
	copy.sort()
	var idx := clampi(int(floor(q * float(copy.size() - 1))), 0, copy.size() - 1)
	return float(copy[idx])


func _max(samples: PackedInt32Array) -> float:
	var m := 0
	for v in samples:
		m = maxi(m, int(v))
	return float(m)
