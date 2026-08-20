extends SceneTree
## Measure startup / bake size / mem after baked-vegetation change.
## Forces a fresh v4 bake then profiles startup.

const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _StartupProfiler = preload("res://systems/startup_profiler.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_STARTUP_PROFILE", "1")
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "1")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-3c89103bbbb9/implementer"
	DirAccess.make_dir_recursive_absolute(scratch)

	# --- Force rebake with vegetation ---
	var world_script = load("res://world/InfiniteNoiseWorld.gd")
	var world = world_script.new()
	if "world_seed" in world:
		world.world_seed = 12349
	var bake = load("res://world/world_bake_service.gd").new()
	var cm_script = load("res://chunks/chunk_manager.gd")
	# Host for mesh plans: use a temporary ChunkManager if possible
	var host = cm_script.new()
	host.world = world
	var t_bake0 := Time.get_ticks_msec()
	var baked: Dictionary = bake.bake_world(world, 2, host)
	var bake_ms := Time.get_ticks_msec() - t_bake0
	if not bool(baked.get("ok", false)):
		# Retry without mesh host
		baked = bake.bake_world(world, 2, null)
		bake_ms = Time.get_ticks_msec() - t_bake0
	bake.save_bake()
	var bytes: int = int(baked.get("bytes", bake.last_bake_bytes))
	var veg_n: int = int(baked.get("vegetation_entries", bake.last_vegetation_entries))
	var veg_ms: int = int(baked.get("vegetation_bake_ms", bake.last_vegetation_bake_ms))
	print(
		"BAKE_RESULT ok=%s bake_ms=%d veg_ms=%d veg_entries=%d bytes=%d"
		% [str(baked.get("ok")), bake_ms, veg_ms, veg_n, bytes]
	)

	# Size of package dir
	var dir: String = bake.package_dir
	var total_bytes := _dir_bytes(dir)
	print("BAKE_DIR %s total_bytes=%d" % [dir, total_bytes])

	host.free()
	# Clear active so boot reloads cleanly
	load("res://world/world_bake_service.gd").clear_active()
	for _i in 3:
		await process_frame

	# --- Startup profile ---
	_StartupProfiler.begin_session()
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var f := 0
	while compose and not bool(compose.get("_boot_done")) and f < 3600:
		await process_frame
		f += 1
	for _i in 45:
		await process_frame

	var mem_static := float(Performance.get_monitor(Performance.MEMORY_STATIC))
	var samples: Dictionary = _StartupProfiler._samples
	var wall_us: int = _StartupProfiler.total_us()
	var fs_us := _last(samples, "feature_seeding")
	var veg_us := _last(samples, "fs/vegetation_placement")
	var stream_us := _last(samples, "initial_chunk_stream")

	var cm = get_first_node_in_group("chunk_manager")
	var chunks_n: int = cm.chunks.size() if cm and "chunks" in cm else -1
	var bake_active = load("res://world/world_bake_service.gd").get_active()
	var veg_baked := false
	var resident := 0
	if bake_active:
		veg_baked = bool(bake_active.get("vegetation_baked"))
		resident = int(bake_active.resident_count()) if bake_active.has_method("resident_count") else 0

	var report := {
		"bake_ms": bake_ms,
		"bake_bytes": bytes,
		"bake_dir_bytes": total_bytes,
		"vegetation_entries": veg_n,
		"vegetation_bake_ms": veg_ms,
		"startup_wall_ms": float(wall_us) / 1000.0,
		"feature_seeding_ms": float(fs_us) / 1000.0,
		"vegetation_placement_ms": float(veg_us) / 1000.0,
		"initial_chunk_stream_ms": float(stream_us) / 1000.0,
		"mem_static_mb": mem_static / (1024.0 * 1024.0),
		"chunks_loaded": chunks_n,
		"bake_resident": resident,
		"vegetation_baked_flag": veg_baked,
		"package_dir": dir,
	}
	var out := scratch.path_join("baked_vegetation_measure.json")
	var wf := FileAccess.open(out, FileAccess.WRITE)
	if wf:
		wf.store_string(JSON.stringify(report, "\t"))
		wf.close()
		print("WROTE %s" % out)
	print("MEASURE %s" % JSON.stringify(report))
	_StartupProfiler.print_report()
	_ProbeExit.finish_tree(self, 0, "BAKED_VEG_MEASURE_OK")


func _last(samples: Dictionary, key: String) -> int:
	if not samples.has(key):
		return 0
	var a: PackedInt64Array = samples[key]
	if a.is_empty():
		return 0
	return int(a[a.size() - 1])


func _dir_bytes(user_dir: String) -> int:
	var abs_path := ProjectSettings.globalize_path(user_dir)
	if not DirAccess.dir_exists_absolute(abs_path):
		return 0
	var total := 0
	var stack: Array = [abs_path]
	while not stack.is_empty():
		var dpath: String = stack.pop_back()
		var da := DirAccess.open(dpath)
		if da == null:
			continue
		da.list_dir_begin()
		var name := da.get_next()
		while name != "":
			if name == "." or name == "..":
				name = da.get_next()
				continue
			var full := dpath.path_join(name)
			if da.current_is_dir():
				stack.append(full)
			else:
				var fa := FileAccess.open(full, FileAccess.READ)
				if fa:
					total += int(fa.get_length())
					fa.close()
			name = da.get_next()
	return total
