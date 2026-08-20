extends SceneTree
## Exclusive breakdown: ChunkManager._drain_stream_pipeline +
## WorldBakeService.ensure_package_data_resident / _read_chunk_package leaves.
## Measure only — no optimizations.
##
## Usage:
##   CRYSTALSTORM_DRAIN_STREAM_MEASURE=1 CRYSTALSTORM_BAKE_RESIDENT_MEASURE=1 \
##   CRYSTALSTORM_BAKE_RADIUS=2 CRYSTALSTORM_SCRATCH=... \
##   godot --headless -s scripts/profile_drain_resident.gd

const MAIN_SCENE := "res://scenes/main.tscn"
const WARM_FRAMES := 30
const COLD_TELEPORT_FRAMES := 120
const WALK_FRAMES := 180


func _initialize() -> void:
	OS.set_environment("CRYSTALSTORM_DRAIN_STREAM_MEASURE", "1")
	OS.set_environment("CRYSTALSTORM_BAKE_RESIDENT_MEASURE", "1")
	if OS.get_environment("CRYSTALSTORM_BAKE_RADIUS").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	if OS.get_environment("CRYSTALSTORM_PERF_PRESET").is_empty():
		OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	if OS.get_environment("CRYSTALSTORM_FULL_WORLD_BAKE").is_empty():
		OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	print("=== DRAIN + RESIDENT EXCLUSIVE MEASURE ===")
	var err := change_scene_to_file(MAIN_SCENE)
	if err != OK:
		push_error("scene fail")
		quit(1)
		return
	await process_frame
	await process_frame

	var player: Node = null
	var cm: Node = null
	var frames := 0
	while frames < 2000:
		await process_frame
		frames += 1
		var root := current_scene
		if root == null:
			continue
		player = root.get_tree().get_first_node_in_group("player")
		cm = root.get_tree().get_first_node_in_group("chunk_manager")
		var composition = root.get_tree().get_first_node_in_group("composition_root")
		if composition and int(composition.stage) >= 7 and player and cm:
			if bool(player.get("world_ready")):
				break

	if player == null or cm == null:
		push_error("boot fail player/cm")
		quit(1)
		return

	for _i in WARM_FRAMES:
		await process_frame

	# Enable + reset measures after warm stream so cold window is clean.
	if cm.has_method("set_drain_measure_enabled"):
		cm.set_drain_measure_enabled(true)
	var bake = load("res://world/world_bake_service.gd").get_active()
	if bake != null and bake.has_method("set_resident_measure_enabled"):
		bake.set_resident_measure_enabled(true)
	ChunkData.set_snapshot_measure_enabled(true)

	var dropped := 0
	if bake != null and bake.has_method("drop_resident_packages_for_measure"):
		dropped = int(bake.drop_resident_packages_for_measure())
	print("dropped_resident_packages=", dropped)

	# Direct cold microbench: one enqueue-shaped halo (center ensure + 8 data-only).
	var direct: Dictionary = {}
	if bake != null and bake.valid and bake.has_method("ensure_package_data_resident"):
		var center := Vector2i(0, 0)
		if bake.has_method("drop_resident_packages_for_measure"):
			bake.drop_resident_packages_for_measure()
		if bake.has_method("reset_resident_measure"):
			bake.reset_resident_measure()
		var t_direct := Time.get_ticks_usec()
		var t_c := Time.get_ticks_usec()
		if bake.has_method("ensure_chunk_resident"):
			bake.ensure_chunk_resident(center)
		var center_us := Time.get_ticks_usec() - t_c
		var t_h := Time.get_ticks_usec()
		var halo_n := 0
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dz == 0:
					continue
				var n := Vector2i(center.x + dx, center.y + dz)
				if bake.coord_in_package(n):
					bake.ensure_package_data_resident(n)
					halo_n += 1
		var halo_us := Time.get_ticks_usec() - t_h
		var direct_tot := Time.get_ticks_usec() - t_direct
		direct = {
			"center_ensure_chunk_resident_us": center_us,
			"halo_ensure_package_data_resident_us": halo_us,
			"halo_calls": halo_n,
			"total_us": direct_tot,
			"total_ms": float(direct_tot) / 1000.0,
			"resident_after": bake.get_resident_measure() if bake.has_method("get_resident_measure") else {},
		}
		print("DIRECT_COLD_HALO_MS=", float(direct_tot) / 1000.0,
			" center_ms=", float(center_us) / 1000.0,
			" halo_ms=", float(halo_us) / 1000.0, " halo_n=", halo_n)
		# Reset counters so stream window is clean after direct microbench.
		if bake.has_method("reset_resident_measure"):
			bake.reset_resident_measure()
		if cm.has_method("reset_drain_measure"):
			cm.reset_drain_measure()
		ChunkData.set_snapshot_measure_enabled(true)

	# Force stream activity: teleport within bake bounds (in-package only).
	var min_cx := -2
	var max_cx := 2
	var min_cz := -2
	var max_cz := 2
	if bake != null and bake.valid:
		min_cx = int(bake.min_cx)
		max_cx = int(bake.max_cx)
		min_cz = int(bake.min_cz)
		max_cz = int(bake.max_cz)
	# Stay 1 chunk inside package so stream ring still hits packages.
	var targets: Array = [
		Vector2i(maxi(min_cx + 1, min_cx), maxi(min_cz + 1, min_cz)),
		Vector2i(mini(max_cx - 1, max_cx), maxi(min_cz + 1, min_cz)),
		Vector2i(mini(max_cx - 1, max_cx), mini(max_cz - 1, max_cz)),
		Vector2i(maxi(min_cx + 1, min_cx), mini(max_cz - 1, max_cz)),
		Vector2i(0, 0),
	]
	var SIZE := 16
	for ti in targets.size():
		var tc: Vector2i = targets[ti]
		var wx := float(tc.x * SIZE + SIZE / 2)
		var wz := float(tc.y * SIZE + SIZE / 2)
		if player.has_method("teleport_to") or "global_position" in player:
			var gp: Vector3 = player.global_position
			gp.x = wx
			gp.z = wz
			player.global_position = gp
		print("teleport_to_chunk=", tc, " world=(", wx, ",", wz, ")")
		# Drop resident again each hop so halo ensure misses stay cold.
		if bake != null and bake.has_method("drop_resident_packages_for_measure"):
			bake.drop_resident_packages_for_measure()
		for _f in COLD_TELEPORT_FRAMES:
			await process_frame

	# Walk path for additional enqueues.
	var dirs: Array[String] = ["ui_right", "ui_up", "ui_left", "ui_down"]
	var di := 0
	for i in WALK_FRAMES:
		if i % 30 == 0:
			for d in dirs:
				Input.action_release(d)
			Input.action_press(dirs[di % dirs.size()])
			di += 1
		await process_frame
	for d in dirs:
		Input.action_release(d)

	var report: Dictionary = {}
	if cm.has_method("get_drain_measure"):
		report = cm.get_drain_measure()
	report["dropped_resident_at_start"] = dropped
	report["boot_frames"] = frames
	report["direct_cold_halo"] = direct
	if bake != null and bake.has_method("package_load_stats"):
		report["package_load_stats"] = bake.package_load_stats()

	_print_report(report)

	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-23417f42e77b/implementer"
	DirAccess.make_dir_recursive_absolute(scratch)
	var path := scratch.path_join("drain_resident_profile.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()
		print("WROTE ", path)
	print("=== DRAIN + RESIDENT EXCLUSIVE MEASURE END ===")
	quit(0)


func _print_report(r: Dictionary) -> void:
	print("\n========== ChunkManager._drain_stream_pipeline EXCLUSIVE ==========")
	print("drain_calls=%s  total=%.2fms  avg=%.3fms  max=%.3fms" % [
		r.get("drain_calls", 0),
		float(r.get("drain_total_ms", 0)),
		float(r.get("drain_avg_us", 0)) / 1000.0,
		float(r.get("drain_max_ms", 0)),
	])
	print("enqueue_calls=%s  enqueue_max=%.3fms" % [
		r.get("enqueue_calls", 0),
		float(r.get("enqueue_max_ms", 0)),
	])
	print("\nRanked drain phases (exclusive wall sum):")
	print("| rank | phase | n | total_ms | max_ms | avg_us | share |")
	var rank := 1
	for ph in r.get("phases", []):
		print("| %4d | %s | %d | %.3f | %.3f | %.1f | %.1f%% |" % [
			rank, ph.get("phase"), int(ph.get("n", 0)),
			float(ph.get("total_ms", 0)), float(ph.get("max_ms", 0)),
			float(ph.get("avg_us", 0)), float(ph.get("share_of_drain_sum", 0)) * 100.0,
		])
		rank += 1

	print("\nWorst drain frame:")
	print(JSON.stringify(r.get("worst_drain", {}), "\t"))
	print("\nWorst enqueue:")
	print(JSON.stringify(r.get("worst_enqueue", {}), "\t"))

	var bake_m: Dictionary = r.get("bake_resident", {})
	print("\n========== WorldBakeService.ensure_package_data_resident EXCLUSIVE ==========")
	print("calls=%s hits=%s misses=%s total=%.2fms max=%.3fms read_max=%.3fms" % [
		bake_m.get("calls", 0), bake_m.get("cache_hits", 0), bake_m.get("cache_misses", 0),
		float(bake_m.get("total_ms", 0)), float(bake_m.get("max_ms", 0)),
		float(bake_m.get("read_package_max_ms", 0)),
	])
	print("\nAll bake phases (incl aggregates):")
	print("| rank | phase | n | total_ms | max_ms | avg_us |")
	rank = 1
	for ph in bake_m.get("phases", []):
		print("| %4d | %s | %d | %.3f | %.3f | %.1f |" % [
			rank, ph.get("phase"), int(ph.get("n", 0)),
			float(ph.get("total_ms", 0)), float(ph.get("max_ms", 0)),
			float(ph.get("avg_us", 0)),
		])
		rank += 1

	print("\nExclusive LEAF ranking (by max_us — hitch attribution):")
	print("| rank | leaf | n | total_ms | max_ms | avg_us |")
	rank = 1
	for ph in bake_m.get("exclusive_leaves", []):
		print("| %4d | %s | %d | %.3f | %.3f | %.1f |" % [
			rank, ph.get("phase"), int(ph.get("n", 0)),
			float(ph.get("total_ms", 0)), float(ph.get("max_ms", 0)),
			float(ph.get("avg_us", 0)),
		])
		rank += 1

	print("\n*** DOMINANT EXCLUSIVE LEAF (by max hitch sample) ***")
	print("  leaf=%s  max=%.3fms  total=%.3fms" % [
		bake_m.get("dominant_exclusive_leaf", "?"),
		float(bake_m.get("dominant_exclusive_leaf_max_ms", 0)),
		float(bake_m.get("dominant_exclusive_leaf_total_us", 0)) / 1000.0,
	])
	print("\nWorst ensure_package_data_resident call:")
	print(JSON.stringify(bake_m.get("worst_call", {}), "\t"))
	if bake_m.has("worst_call") and bake_m["worst_call"] is Dictionary:
		var wc: Dictionary = bake_m["worst_call"]
		if wc.has("read_detail"):
			print("worst read_detail:")
			print(JSON.stringify(wc.get("read_detail", {}), "\t"))

	var snap: Dictionary = r.get("capture_worker_snapshot", {})
	print("\n========== capture_worker_snapshot EXCLUSIVE LEAVES ==========")
	print("calls=%s max=%.3fms" % [snap.get("calls", 0), float(snap.get("max_ms", 0))])
	print("| rank | phase | n | total_ms | max_ms | avg_us |")
	rank = 1
	for ph in snap.get("phases", []):
		print("| %4d | %s | %d | %.3f | %.3f | %.1f |" % [
			rank, ph.get("phase"), int(ph.get("n", 0)),
			float(ph.get("total_ms", 0)), float(ph.get("max_ms", 0)),
			float(ph.get("avg_us", 0)),
		])
		rank += 1
	print("worst snapshot:")
	print(JSON.stringify(snap.get("worst", {}), "\t"))

	var direct: Dictionary = r.get("direct_cold_halo", {})
	if not direct.is_empty():
		print("\n========== DIRECT COLD HALO (1× center + 8× package_data) ==========")
		print("total_ms=%.3f center_ms=%.3f halo_ms=%.3f halo_n=%s" % [
			float(direct.get("total_ms", 0)),
			float(direct.get("center_ensure_chunk_resident_us", 0)) / 1000.0,
			float(direct.get("halo_ensure_package_data_resident_us", 0)) / 1000.0,
			direct.get("halo_calls", 0),
		])
		var dr: Dictionary = direct.get("resident_after", {})
		print("direct leaf ranking:")
		rank = 1
		for ph in dr.get("exclusive_leaves", []):
			print("| %4d | %s | %d | %.3f | %.3f |" % [
				rank, ph.get("phase"), int(ph.get("n", 0)),
				float(ph.get("total_ms", 0)), float(ph.get("max_ms", 0)),
			])
			rank += 1
		print("direct dominant leaf=", dr.get("dominant_exclusive_leaf", "?"),
			" max_ms=", float(dr.get("dominant_exclusive_leaf_max_ms", 0)))
		print("direct all phases:")
		for ph in dr.get("phases", []):
			print("  %s n=%s total_ms=%.3f max_ms=%.3f" % [
				ph.get("phase"), ph.get("n"), float(ph.get("total_ms", 0)), float(ph.get("max_ms", 0)),
			])

	var pls: Dictionary = r.get("package_load_stats", {})
	if not pls.is_empty():
		print("\n========== PACKAGE LOAD STATS ==========")
		print(JSON.stringify(pls, "\t"))

	# Final synthesis for exclusive leaf of the drain hitch.
	print("\n========== SYNTHESIS ==========")
	var drain_max := float(r.get("drain_max_ms", 0))
	var enq: Dictionary = r.get("worst_enqueue", {})
	var snap_w: Dictionary = snap.get("worst", {})
	print("drain_max_ms=%.3f" % drain_max)
	print("worst_enqueue parts: %s" % JSON.stringify(enq))
	print("worst_snapshot parts: %s" % JSON.stringify(snap_w))
	var cand: Array = []
	if float(enq.get("capture_worker_snapshot_us", 0)) > 0:
		cand.append({"name": "capture_worker_snapshot", "us": int(enq.get("capture_worker_snapshot_us", 0))})
	if float(enq.get("ensure_package_data_resident_halo_us", 0)) > 0:
		cand.append({"name": "ensure_package_data_resident_halo", "us": int(enq.get("ensure_package_data_resident_halo_us", 0))})
	if float(enq.get("ensure_chunk_resident_us", 0)) > 0:
		cand.append({"name": "ensure_chunk_resident", "us": int(enq.get("ensure_chunk_resident_us", 0))})
	if float(snap_w.get("capture_halo_surface_us", 0)) > 0:
		cand.append({"name": "capture_halo_surface", "us": int(snap_w.get("capture_halo_surface_us", 0))})
	if float(snap_w.get("overlay_copy_us", 0)) > 0:
		cand.append({"name": "overlay_copy", "us": int(snap_w.get("overlay_copy_us", 0))})
	for ph in bake_m.get("exclusive_leaves", []):
		cand.append({"name": "bake." + str(ph.get("phase")), "us": int(ph.get("max_us", 0))})
	cand.sort_custom(func(a, b): return int(a.us) > int(b.us))
	if cand.size() > 0:
		print("DOMINANT_EXCLUSIVE_LEAF=%s us=%d ms=%.3f" % [
			cand[0].name, int(cand[0].us), float(cand[0].us) / 1000.0,
		])
		print("Top exclusive candidates:")
		for i in mini(cand.size(), 12):
			print("  %d. %s  %.3f ms" % [i + 1, cand[i].name, float(cand[i].us) / 1000.0])
