extends SceneTree
## Bounded live boot + PerfProfiler sample for one CRYSTALSTORM_PERF_PRESET.

const MAIN_SCENE := "res://scenes/main.tscn"
const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")


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
	print("QUALITY_PROFILE_START preset=%s" % preset)
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		print("QUALITY_PROFILE_FAIL no scene")
		_ProbeExit.finish_tree(self, 1, "QUALITY PROFILE FAILED")
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
	if compose == null or int(compose.stage) < compose.Stage.INITIAL_STREAM_READY:
		print("QUALITY_PROFILE_FAIL not ready")
		_ProbeExit.finish_tree(self, 1, "QUALITY PROFILE FAILED")
		return
	for _w in 30:
		await process_frame
		if not _GameplayInput.world_loading:
			break
	var cm = get_first_node_in_group("chunk_manager")
	var idle_n := 0
	while idle_n < 180:
		await process_frame
		idle_n += 1
		if cm and cm.has_method("get_stream_status"):
			var st: Dictionary = cm.get_stream_status()
			if int(st.get("stream_queue", 1)) == 0 and int(st.get("mesh_pending", 1)) == 0 \
					and int(st.get("inflight", 1)) == 0:
				break
	for _s in 20:
		await process_frame
	var acc: Dictionary = {}
	var n := 0
	var worst := 0.0
	var sum := 0.0
	var last_f3 := ""
	for i in 90:
		await process_frame
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
	var out := {
		"preset": preset,
		"samples": n,
		"avg_frame_ms": (sum / float(maxi(n, 1))),
		"worst_frame_ms": worst,
		"hottest": hot,
		"f3": last_f3,
		"stream": {},
	}
	if cm and cm.has_method("get_stream_status"):
		out["stream"] = cm.get_stream_status()
	var path := scratch.path_join("quality_%s.json" % preset)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "\t"))
		f.close()
		print("WROTE %s" % path)
	print("QUALITY_PROFILE preset=%s avg_ms=%.2f worst=%.2f hot=%s" % [
		preset, float(out.avg_frame_ms), worst, str(hot.slice(0, 5) if hot.size() >= 5 else hot)
	])
	_ProbeExit.finish_tree(self, 0, "All quality profile OK")
