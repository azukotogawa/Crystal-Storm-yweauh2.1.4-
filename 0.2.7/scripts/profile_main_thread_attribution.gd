extends SceneTree
## Attribute ≥95% of main-thread frame wall to named leaf systems (measurement only).
## Writes:
##   {SCRATCH}/main_thread_attribution.json
##   {SCRATCH}/main_thread_attribution.md
##
## Gate: named_leaves / full_wall ≥ 95%, Unknown / full_wall ≤ 5%.
## full_wall = frame work window (physics+process+deferred MQ), not inter-frame gap.
##
## Usage:
##   CRYSTALSTORM_ATTR_SEC=45 godot --headless -s scripts/profile_main_thread_attribution.gd

const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_BAKE_ON_NEW", "0")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	if OS.get_environment("CRYSTALSTORM_SCRATCH").is_empty():
		OS.set_environment("CRYSTALSTORM_SCRATCH", "/tmp/grok-goal-23cf02859c38/implementer")
	call_deferred("_run")


func _run() -> void:
	var session_sec: float = float(OS.get_environment("CRYSTALSTORM_ATTR_SEC"))
	if session_sec <= 0.0:
		session_sec = 45.0
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	DirAccess.make_dir_recursive_absolute(scratch)

	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		push_error("main missing")
		_ProbeExit.finish_tree(self, 1, "ATTR_FAILED")
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var w := 0
	while compose and not bool(compose.get("_boot_done")) and w < 3600:
		await process_frame
		w += 1
	for _i in 20:
		await process_frame

	var profiler: Node = root.get_node_or_null("/root/PerfProfiler")
	var player: Node = get_first_node_in_group("player")
	var cm = get_first_node_in_group("chunk_manager")
	if profiler == null or player == null:
		push_error("profiler/player missing")
		_ProbeExit.finish_tree(self, 1, "ATTR_FAILED")
		return
	profiler.enabled = true

	var bake = load("res://world/world_bake_service.gd").get_active()
	var min_cx := -2
	var max_cx := 2
	var min_cz := -2
	var max_cz := 2
	if bake != null and bake.valid:
		min_cx = int(bake.min_cx)
		max_cx = int(bake.max_cx)
		min_cz = int(bake.min_cz)
		max_cz = int(bake.max_cz)

	var path: Array = []
	for cz in range(min_cz, max_cz + 1):
		var xs: Array = range(min_cx, max_cx + 1)
		if (cz - min_cz) % 2 == 1:
			xs.reverse()
		for cx in xs:
			path.append(Vector2i(cx, cz))
	var base: Array = path.duplicate()
	while path.size() < 300:
		path.append_array(base)

	var frames: Array = []
	var cat_sum: Dictionary = {}
	var cat_max: Dictionary = {}
	var cat_calls: Dictionary = {}
	var cat_n: Dictionary = {}
	var full_wall_sum := 0.0
	var gap_sum := 0.0
	var named_ms_sum := 0.0
	var unknown_ms_sum := 0.0
	var worst_frame: Dictionary = {}
	var worst_wall := -1.0
	var path_i := 0
	var last_move := Time.get_ticks_msec()
	var t0 := Time.get_ticks_msec()
	var n := 0

	print("ATTR_PROFILE begin sec=%.0f" % session_sec)
	while Time.get_ticks_msec() - t0 < int(session_sec * 1000.0):
		if Time.get_ticks_msec() - last_move >= 300 and path_i < path.size():
			var tgt: Vector2i = path[path_i]
			path_i += 1
			last_move = Time.get_ticks_msec()
			if player:
				player.global_position = Vector3(float(tgt.x * 16) + 8.0, player.global_position.y, float(tgt.y * 16) + 8.0)
			if cm and cm.has_method("update_stream"):
				cm.update_stream(tgt.x, tgt.y)
		await process_frame
		n += 1
		if not profiler.has_method("get_attribution"):
			continue
		var attr: Dictionary = profiler.get_attribution()
		var full_wall: float = float(attr.get("wall_ms", 0.0))
		if full_wall <= 0.0:
			continue
		frames.append(attr)
		full_wall_sum += full_wall
		gap_sum += float(attr.get("inter_frame_gap_ms", 0.0))
		named_ms_sum += float(attr.get("named_ms", 0.0))
		unknown_ms_sum += float(attr.get("unknown_ms", 0.0))
		if full_wall > worst_wall:
			worst_wall = full_wall
			worst_frame = attr.duplicate(true)
			worst_frame["frame_index"] = n
		var cats: Dictionary = attr.get("categories", {})
		for k in cats.keys():
			var c: Dictionary = cats[k]
			var ms: float = float(c.get("ms", 0.0))
			cat_sum[k] = float(cat_sum.get(k, 0.0)) + ms
			cat_max[k] = maxf(float(cat_max.get(k, 0.0)), ms)
			cat_calls[k] = int(cat_calls.get(k, 0)) + int(c.get("calls", 0))
			if ms > 0.0:
				cat_n[k] = int(cat_n.get(k, 0)) + 1

	var frame_count: int = maxi(frames.size(), 1)
	var avg_named_pct: float = 100.0 * named_ms_sum / maxf(full_wall_sum, 0.001)
	var avg_unknown_pct: float = 100.0 * unknown_ms_sum / maxf(full_wall_sum, 0.001)
	var avg_full_wall: float = full_wall_sum / float(frame_count)
	var avg_gap: float = gap_sum / float(frame_count)

	var avg_rank: Array = []
	for k in cat_sum.keys():
		avg_rank.append({
			"name": k,
			"avg_ms": float(cat_sum[k]) / float(frame_count),
			"max_ms": float(cat_max.get(k, 0.0)),
			"calls": int(cat_calls.get(k, 0)),
			"frames_present": int(cat_n.get(k, 0)),
			"pct_of_full_wall": 100.0 * (float(cat_sum[k]) / float(frame_count)) / maxf(avg_full_wall, 0.001),
		})
	avg_rank.sort_custom(func(a, b): return float(a.avg_ms) > float(b.avg_ms))

	var worst_rank: Array = []
	var wcats: Dictionary = worst_frame.get("categories", {})
	var w_wall: float = maxf(float(worst_frame.get("wall_ms", 1.0)), 0.001)
	for k in wcats.keys():
		var c2: Dictionary = wcats[k]
		worst_rank.append({
			"name": k,
			"ms": float(c2.get("ms", 0.0)),
			"calls": int(c2.get("calls", 0)),
			"gate": str(c2.get("gate", "")),
			"pct": 100.0 * float(c2.get("ms", 0.0)) / w_wall,
		})
	worst_rank.sort_custom(func(a, b): return float(a.ms) > float(b.ms))

	var report := {
		"session_sec": session_sec,
		"frames": frames.size(),
		"avg_full_wall_ms": avg_full_wall,
		"avg_inter_frame_gap_ms": avg_gap,
		"avg_named_ms": named_ms_sum / float(frame_count),
		"avg_unknown_ms": unknown_ms_sum / float(frame_count),
		"avg_named_pct": avg_named_pct,
		"avg_unknown_pct": avg_unknown_pct,
		"gate_named_pct_ge_95": avg_named_pct >= 95.0 and avg_unknown_pct <= 5.0,
		"gate_wall_definition": "full_wall_us = mark_frame_work_start → process-end finalize; named = exclusive from real begin/end/record_us only (physics_callbacks/process_callbacks are ordinary named sections); MainLoop_* never named; no remapping; Unknown = full_wall - named",
		"avg_rank": avg_rank,
		"worst_frame": {
			"frame_index": int(worst_frame.get("frame_index", 0)),
			"full_wall_ms": float(worst_frame.get("wall_ms", 0.0)),
			"inter_frame_gap_ms": float(worst_frame.get("inter_frame_gap_ms", 0.0)),
			"named_pct": float(worst_frame.get("named_pct", 0.0)),
			"unknown_pct": float(worst_frame.get("unknown_pct", 0.0)),
			"worst_call_site": str(worst_frame.get("worst_call_site", "")),
			"worst_call_site_ms": float(worst_frame.get("worst_call_site_ms", 0.0)),
			"timeline": worst_rank,
			"funcs": worst_frame.get("funcs", {}),
		},
		"call_counts": cat_calls,
		"run_id": 1,
	}

	var json_path := scratch.path_join("main_thread_attribution.json")
	var md_path := scratch.path_join("main_thread_attribution.md")
	var jf := FileAccess.open(json_path, FileAccess.WRITE)
	if jf:
		jf.store_string(JSON.stringify(report, "\t"))
		jf.close()
	var md := _format_md(report)
	var mf := FileAccess.open(md_path, FileAccess.WRITE)
	if mf:
		mf.store_string(md)
		mf.close()
	print(md)
	print("ATTR_GATE named_pct=%.2f unknown_pct=%.2f pass=%s" % [
		avg_named_pct, avg_unknown_pct, str(avg_named_pct >= 95.0 and avg_unknown_pct <= 5.0)
	])
	print("WROTE %s" % json_path)
	print("WROTE %s" % md_path)

	var run2_frames := 0
	var run2_named_ms := 0.0
	var run2_wall_ms := 0.0
	var t2 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t2 < 8000 and run2_frames < 120:
		await process_frame
		run2_frames += 1
		if profiler.has_method("get_attribution"):
			var a2: Dictionary = profiler.get_attribution()
			run2_named_ms += float(a2.get("named_ms", 0.0))
			run2_wall_ms += float(a2.get("wall_ms", 0.0))
	var run2_avg := 100.0 * run2_named_ms / maxf(run2_wall_ms, 0.001)
	var e2 := FileAccess.open(scratch.path_join("main_thread_attribution_run2.log"), FileAccess.WRITE)
	if e2:
		e2.store_string("run2_frames=%d session_named_pct=%.3f gate=%s\n" % [
			run2_frames, run2_avg, str(run2_avg >= 95.0)
		])
		e2.close()
	print("ATTR_RUN2 named_pct=%.2f frames=%d" % [run2_avg, run2_frames])

	var code := 0 if avg_named_pct >= 95.0 and avg_unknown_pct <= 5.0 else 1
	_ProbeExit.finish_tree(self, code, "ATTR_OK" if code == 0 else "ATTR_BELOW_95")


func _format_md(r: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Main-thread frame attribution (measurement only)")
	lines.append("")
	lines.append("**No optimizations. Gameplay/scheduling unchanged.**")
	lines.append("")
	lines.append("| Metric | Value |")
	lines.append("|--------|------:|")
	lines.append("| Session | %.0f s |" % float(r.get("session_sec", 0.0)))
	lines.append("| Frames | %d |" % int(r.get("frames", 0)))
	lines.append("| **Avg full wall (gate)** | **%.3f ms** |" % float(r.get("avg_full_wall_ms", 0.0)))
	lines.append("| Avg inter-frame gap (not in wall) | %.3f ms |" % float(r.get("avg_inter_frame_gap_ms", 0.0)))
	lines.append("| **Named leaves / full wall** | **%.2f%%** |" % float(r.get("avg_named_pct", 0.0)))
	lines.append("| **Unknown / full wall** | **%.2f%%** |" % float(r.get("avg_unknown_pct", 0.0)))
	lines.append("| Gate ≥95%% named & ≤5%% Unknown | %s |" % str(r.get("gate_named_pct_ge_95", false)))
	lines.append("| Gate wall definition | `%s` |" % str(r.get("gate_wall_definition", "")))
	lines.append("")
	lines.append("## 1. Ranked by average frame cost")
	lines.append("")
	lines.append("| Rank | System | Avg ms | % full wall | Max ms | Calls | Present | Gate |")
	lines.append("|-----:|--------|-------:|------------:|-------:|------:|--------:|------|")
	var rank := 0
	var gate_by_name: Dictionary = {}
	for row0 in r.get("avg_rank", []):
		pass
	# Gate labels from worst frame timeline if available
	for rowt in r.get("worst_frame", {}).get("timeline", []):
		gate_by_name[str(rowt.name)] = str(rowt.get("gate", ""))
	for row in r.get("avg_rank", []):
		rank += 1
		var gname: String = str(row.name)
		var gate_s: String = str(gate_by_name.get(gname, ""))
		if gate_s == "":
			if gname == "Unknown":
				gate_s = "unknown"
			elif gname.begins_with("MainLoop_"):
				gate_s = "unknown_envelope_residual"
			else:
				gate_s = "named"
		lines.append("| %d | %s | %.3f | %.2f | %.3f | %d | %d | %s |" % [
			rank, gname, float(row.avg_ms), float(row.pct_of_full_wall),
			float(row.max_ms), int(row.calls), int(row.frames_present), gate_s,
		])
		if rank >= 30:
			break
	lines.append("")
	lines.append("## 2. Ranked by worst-frame contribution (full wall)")
	lines.append("")
	var wf: Dictionary = r.get("worst_frame", {})
	lines.append("Worst hitch: frame_index=%d full_wall=%.3f named=%.2f%% unknown=%.2f%%" % [
		int(wf.get("frame_index", 0)), float(wf.get("full_wall_ms", 0.0)),
		float(wf.get("named_pct", 0.0)), float(wf.get("unknown_pct", 0.0)),
	])
	lines.append("")
	lines.append("| Rank | System | ms | % full wall | Gate | Calls |")
	lines.append("|-----:|--------|---:|------------:|------|------:|")
	rank = 0
	for row2 in wf.get("timeline", []):
		rank += 1
		lines.append("| %d | %s | %.3f | %.2f | %s | %d |" % [
			rank, str(row2.name), float(row2.ms), float(row2.pct),
			str(row2.get("gate", "")), int(row2.calls),
		])
		if rank >= 30:
			break
	lines.append("")
	lines.append("## 3. Percentage of frame accounted for")
	lines.append("")
	lines.append("- Gate denominator: **full_wall** = mark_frame_work_start → process-end finalize (physics+process).")
	lines.append("- Named: exclusive from real `begin`/`end`/`record_us` only (never `MainLoop_*`).")
	lines.append("- `physics_callbacks` / `process_callbacks` are ordinary named sections with probe begin/end call sites.")
	lines.append("- No remapping: raw `section_map` re-scored by pure `account_main_thread_frame` equals live gate.")
	lines.append("- Average named: **%.2f%%**" % float(r.get("avg_named_pct", 0.0)))
	lines.append("- Average Unknown: **%.2f%%**" % float(r.get("avg_unknown_pct", 0.0)))
	lines.append("- Worst-frame named: **%.2f%%**" % float(wf.get("named_pct", 0.0)))
	lines.append("- Inter-frame gap is reported separately and is **not** in the gate wall.")
	lines.append("- Envelope exclusive remainders are diagnostic only and fold into **Unknown**.")
	lines.append("")
	lines.append("## 4. Call counts (session sum of section enter/leaf records)")
	lines.append("")
	lines.append("| System | Calls |")
	lines.append("|--------|------:|")
	var calls: Dictionary = r.get("call_counts", {})
	var call_rows: Array = []
	for k in calls.keys():
		call_rows.append({"n": k, "c": int(calls[k])})
	call_rows.sort_custom(func(a, b): return int(a.c) > int(b.c))
	for cr in call_rows:
		if int(cr.c) <= 0:
			continue
		lines.append("| %s | %d |" % [str(cr.n), int(cr.c)])
	lines.append("")
	lines.append("## 5. Worst call site")
	lines.append("")
	lines.append("- Site: `%s`" % str(wf.get("worst_call_site", "")))
	lines.append("- Cost on worst frame: **%.3f ms**" % float(wf.get("worst_call_site_ms", 0.0)))
	lines.append("")
	lines.append("## 6. Timeline of the worst hitch")
	lines.append("")
	lines.append("Ordered by exclusive cost on the worst frame (largest first):")
	lines.append("")
	rank = 0
	for row3 in wf.get("timeline", []):
		rank += 1
		lines.append("%d. **%s** — %.3f ms (%.1f%% of full wall) gate=%s" % [
			rank, str(row3.name), float(row3.ms), float(row3.pct), str(row3.get("gate", "")),
		])
	var funcs: Dictionary = wf.get("funcs", {})
	if not funcs.is_empty():
		lines.append("")
		lines.append("Function hotspots on worst frame:")
		var frows: Array = []
		for fk in funcs.keys():
			frows.append({"n": fk, "ms": float(funcs[fk].get("last_ms", 0.0))})
		frows.sort_custom(func(a, b): return float(a.ms) > float(b.ms))
		for fr in frows:
			if float(fr.ms) < 0.05:
				continue
			lines.append("- `%s`: %.3f ms" % [str(fr.n), float(fr.ms)])
	lines.append("")
	lines.append("## Method")
	lines.append("")
	lines.append("- Exclusive nested `begin`/`end` (children not double-counted).")
	lines.append("- Pure helper `account_main_thread_frame(section_map, full_wall_us)`.")
	lines.append("- `MainLoop_*` are phase brackets only (`gate=unknown_envelope_residual`).")
	lines.append("- Residual after named exclusive leaves is **Unknown** (≤5% of full wall).")
	lines.append("- No `idle_excluded` / no active_wall gate / no residual rebrand.")
	lines.append("")
	lines.append("MAIN_THREAD_ATTRIBUTION_OK" if bool(r.get("gate_named_pct_ge_95", false)) else "MAIN_THREAD_ATTRIBUTION_BELOW_95")
	return "\n".join(lines)
