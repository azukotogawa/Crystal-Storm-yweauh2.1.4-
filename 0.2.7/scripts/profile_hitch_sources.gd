extends SceneTree
## Baseline / after profile for CrystalManager + GameVisualRegistry hitches.
## Measures: bundle regenerations, full visual refreshes, crystal process cost
## during boot + synthetic chunk storm + teleport-like stream pressure.
## Usage: godot --headless -s scripts/profile_hitch_sources.gd

const FRAMES_POST_READY := 180
const CHUNK_STORM_FRAMES := 90


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	print("=== HITCH SOURCE PROFILE start ===")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", OS.get_environment("CRYSTALSTORM_BAKE_RADIUS") if not OS.get_environment("CRYSTALSTORM_BAKE_RADIUS").is_empty() else "2")
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		push_error("change_scene failed %d" % err)
		quit(1)
		return
	await process_frame
	await process_frame

	var root := current_scene
	var frames := 0
	var reg = null
	var crystal = null
	var cm = null
	var composition = null
	while frames < 1200:
		await process_frame
		frames += 1
		if root == null:
			root = current_scene
		if root == null:
			continue
		reg = root.get_tree().get_first_node_in_group("game_visual_registry")
		crystal = root.get_tree().get_first_node_in_group("crystal_manager")
		cm = root.get_tree().get_first_node_in_group("chunk_manager")
		composition = root.get_tree().get_first_node_in_group("composition_root")
		var running := false
		if composition and "stage" in composition:
			running = int(composition.stage) >= 7  # RUNNING
		if running and crystal and bool(crystal.get("_initialized")):
			# Let a few frames settle after RUNNING.
			for _i in 5:
				await process_frame
				frames += 1
			break

	var boot_ms := Time.get_ticks_msec() - t0
	print("[HitchProfile] boot_to_stream_ms=%d frames=%d" % [boot_ms, frames])

	# Install counters if not present (reflection-friendly via scripts)
	var counters := {
		"bundle_gens": 0,
		"refresh_all": 0,
		"refresh_scene": 0,
		"world_refresh_all_layers": 0,
		"crystal_process_us": 0,
		"crystal_process_calls": 0,
		"crystal_process_max_us": 0,
		"crystal_tick_us": 0,
		"crystal_tick_max_us": 0,
		"flow_us": 0,
		"flow_max_us": 0,
	}

	# Read built-in counters if instrumentation present
	if reg and reg.has_method("get_hitch_counters"):
		var c: Dictionary = reg.get_hitch_counters()
		for k in c.keys():
			counters[k] = c[k]
	if crystal and crystal.has_method("get_hitch_counters"):
		var c2: Dictionary = crystal.get_hitch_counters()
		for k in c2.keys():
			counters[k] = c2[k]

	var snap_boot := _snap_counters(reg, crystal)
	print("[HitchProfile] counters_at_stream_ready: %s" % JSON.stringify(snap_boot))

	# Sample crystal for N frames at steady stream-ready
	var sample := await _sample_crystal(crystal, FRAMES_POST_READY)
	print("[HitchProfile] post_ready crystal sample: %s" % JSON.stringify(sample))

	# Chunk-load storm: force refresh path by re-emitting / waiting stream
	var player = root.get_tree().get_first_node_in_group("player") if root else null
	if player and cm and player.has_method("get_voxel_position"):
		var before_tp := _snap_counters(reg, crystal)
		var pos: Vector3 = player.get_voxel_position()
		# Teleport-like jump ~8 chunks away to force stream
		if "voxel_position" in player:
			player.voxel_position = Vector3(pos.x + 128.0, pos.y + 40.0, pos.z + 128.0)
		elif player.has_method("set_voxel_position"):
			player.set_voxel_position(Vector3(pos.x + 128.0, pos.y + 40.0, pos.z + 128.0))
		else:
			player.global_position = Vector3(
				(pos.x + 128.0) * 1.0,
				(pos.y + 40.0) * 1.0,
				(pos.z + 128.0) * 1.0
			)
		var storm := await _sample_crystal(crystal, CHUNK_STORM_FRAMES)
		var after_tp := _snap_counters(reg, crystal)
		print("[HitchProfile] teleport_stream crystal sample: %s" % JSON.stringify(storm))
		print("[HitchProfile] counter_delta_teleport: %s" % JSON.stringify(_delta(before_tp, after_tp)))

	var snap_end := _snap_counters(reg, crystal)
	var out := {
		"boot_to_stream_ms": boot_ms,
		"counters_boot": snap_boot,
		"post_ready_sample": sample,
		"counters_end": snap_end,
		"total_ms": Time.get_ticks_msec() - t0,
	}
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-23417f42e77b/implementer"
	DirAccess.make_dir_recursive_absolute(scratch)
	var path := scratch.path_join("hitch_profile.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "\t"))
		f.close()
		print("[HitchProfile] wrote %s" % path)
	print("=== HITCH SOURCE PROFILE end ===")
	quit(0)


func _snap_counters(reg, crystal) -> Dictionary:
	var d := {}
	if reg and reg.has_method("get_hitch_counters"):
		d.merge(reg.get_hitch_counters(), true)
	if crystal and crystal.has_method("get_hitch_counters"):
		d.merge(crystal.get_hitch_counters(), true)
	# Fallback: cache size / initialized flags
	if reg:
		if "cache_size" not in d and "_cache" in reg:
			d["cache_size"] = int(reg._cache.size()) if reg._cache is Dictionary else -1
		if "_bundle_ready" in reg:
			d["bundle_ready"] = bool(reg._bundle_ready)
		if "_bundle_gen_count" in reg:
			d["bundle_gen_count"] = int(reg._bundle_gen_count)
		if "_refresh_all_count" in reg:
			d["refresh_all_count"] = int(reg._refresh_all_count)
		if "_refresh_scene_count" in reg:
			d["refresh_scene_count"] = int(reg._refresh_scene_count)
	if crystal:
		if "_process_max_us" in crystal:
			d["crystal_process_max_us"] = int(crystal._process_max_us)
		if "covered_cells" in crystal:
			d["crystal_cells"] = int(crystal.covered_cells)
		if "expansion_enabled" in crystal:
			d["expansion_enabled"] = bool(crystal.expansion_enabled)
	return d


func _delta(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {}
	for k in b.keys():
		if typeof(b[k]) in [TYPE_INT, TYPE_FLOAT] and a.has(k):
			out[k] = b[k] - a[k]
		else:
			out[k] = b[k]
	return out


func _sample_crystal(crystal, n: int) -> Dictionary:
	var sum_us := 0
	var max_us := 0
	var sum_tick := 0
	var max_tick := 0
	var calls := 0
	var steps := 0
	for i in n:
		await process_frame
		if crystal == null:
			continue
		# Prefer profiler gauges if present
		var profiler = root.get_node_or_null("/root/PerfProfiler") if root else null
		if profiler and profiler.has_method("get_last_section_us"):
			var u := int(profiler.get_last_section_us("crystal_manager"))
			if u > 0:
				sum_us += u
				max_us = maxi(max_us, u)
				calls += 1
		if crystal.has_method("get_last_process_us"):
			var pu := int(crystal.get_last_process_us())
			sum_us += pu
			max_us = maxi(max_us, pu)
			calls += 1
			if crystal.has_method("get_last_tick_us"):
				var tu := int(crystal.get_last_tick_us())
				sum_tick += tu
				max_tick = maxi(max_tick, tu)
			if crystal.has_method("get_last_sim_steps"):
				steps += int(crystal.get_last_sim_steps())
	return {
		"frames": n,
		"process_calls": calls,
		"process_avg_ms": (float(sum_us) / float(maxi(calls, 1))) / 1000.0,
		"process_max_ms": float(max_us) / 1000.0,
		"tick_avg_ms": (float(sum_tick) / float(maxi(calls, 1))) / 1000.0,
		"tick_max_ms": float(max_tick) / 1000.0,
		"sim_steps_total": steps,
	}
