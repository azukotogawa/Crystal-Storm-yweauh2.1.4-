extends SceneTree
## Verifies exclusive main-thread attribution without residual rebrand.
## Gate: named exclusive (real begin/end sections) / full_wall ≥ 95%, Unknown ≤ 5%.
## Pure account_main_thread_frame is the only gate scorer (live path must not remap).

const _ProbeExit = preload("res://scripts/probe_exit.gd")
const MAIN_SCENE := "res://scenes/main.tscn"

const FORBIDDEN_NAMED := [
	"Engine_process_unscoped",
	"Engine_physics_unscoped",
	"Engine_idle_or_message_queue",
	"Main_thread_waiting",
	"Main_thread_waiting_untracked",
	"MainLoop_process",
	"MainLoop_physics",
	"MainLoop_deferred",
	"MainLoop_idle",
	"Unknown",
	"physics_server_step",
]

## Production roots that may contain begin("name") / record_us("name") for named categories.
const PROD_GLOBS := [
	"res://systems/",
	"res://chunks/",
	"res://crystal/",
	"res://world/",
	"res://entities/",
	"res://player/",
	"res://ui/",
	"res://game/",
	"res://weapons/",
	"res://relics/",
	"res://main.gd",
]


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_BAKE_ON_NEW", "0")
	if OS.get_environment("CRYSTALSTORM_SCRATCH").is_empty():
		OS.set_environment("CRYSTALSTORM_SCRATCH", "/tmp/grok-goal-23cf02859c38/implementer")
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _test_pure_account_contract()
	failed += _test_no_remap_and_real_begin_end()
	failed += await _test_gameplay_walk_gate()
	if failed > 0:
		_ProbeExit.finish_tree(self, 1, "VERIFY_ATTR_FAIL n=%d" % failed)
	else:
		_ProbeExit.finish_tree(self, 0, "VERIFY_ATTR_OK")


func _test_pure_account_contract() -> int:
	var failed := 0
	var profiler: Node = root.get_node_or_null("/root/PerfProfiler")
	if profiler == null or not profiler.has_method("account_main_thread_frame"):
		push_error("FAIL: account_main_thread_frame missing")
		return 1
	# Leaves named; MainLoop_* envelope exclusive → Unknown.
	var sections := {
		"chunk_upload": {"exclusive_us": 4000, "calls": 1},
		"living_world": {"exclusive_us": 2000, "calls": 1},
		"MainLoop_physics": {"exclusive_us": 3000, "calls": 1},
		"MainLoop_process": {"exclusive_us": 1000, "calls": 1},
	}
	var acct: Dictionary = profiler.account_main_thread_frame(sections, 10000)
	var named_ms: float = float(acct.get("named_ms", 0.0))
	var unknown_ms: float = float(acct.get("unknown_ms", 0.0))
	print(
		"pure_account named_ms=%.3f unknown_ms=%.3f named_pct=%.2f"
		% [named_ms, unknown_ms, float(acct.get("named_pct", 0.0))]
	)
	if absf(named_ms - 6.0) > 0.05:
		push_error("FAIL: pure named expected 6.0 got %.3f" % named_ms)
		failed += 1
	else:
		print("OK pure named leaves only")
	if absf(unknown_ms - 4.0) > 0.05:
		push_error("FAIL: pure unknown expected 4.0 (envelope residual) got %.3f" % unknown_ms)
		failed += 1
	else:
		print("OK pure envelope residual is Unknown")
	# physics_callbacks exclusive is named (ordinary section, not envelope).
	var with_phase := {
		"physics_callbacks": {"exclusive_us": 5000, "calls": 1},
		"entity_physics": {"exclusive_us": 3000, "calls": 10},
		"MainLoop_physics": {"exclusive_us": 2000, "calls": 1},
	}
	var acct2: Dictionary = profiler.account_main_thread_frame(with_phase, 10000)
	# named = 5+3 = 8ms; MainLoop 2ms → Unknown; named_pct 80
	if absf(float(acct2.get("named_ms", 0.0)) - 8.0) > 0.05:
		push_error(
			"FAIL: pure physics_callbacks+entity expected named 8.0 got %.3f"
			% float(acct2.get("named_ms", 0.0))
		)
		failed += 1
	else:
		print("OK pure physics_callbacks is named (not envelope)")
	if str(acct2.get("categories", {}).get("MainLoop_physics", {}).get("gate", "")) == "named":
		push_error("FAIL: MainLoop_physics must not be named in pure account")
		failed += 1
	if float(acct.get("named_pct", 0.0)) >= 95.0:
		push_error("FAIL: residual synthetic must not pass 95%")
		failed += 1
	else:
		print("OK pure contract fails when residual large")
	return failed


func _test_no_remap_and_real_begin_end() -> int:
	var failed := 0
	var profiler: Node = root.get_node_or_null("/root/PerfProfiler")
	if profiler == null:
		push_error("FAIL: PerfProfiler missing")
		return 1
	profiler.enabled = true
	var pp := FileAccess.get_file_as_string("res://systems/perf_profiler.gd")
	var probe := FileAccess.get_file_as_string("res://systems/main_thread_frame_probe.gd")
	for banned in [
		"ENVELOPE_DISPATCH_LEAF",
		"promoted_to",
		"idle_excluded",
	]:
		if banned in pp:
			push_error("FAIL: banned remapping token in perf_profiler: %s" % banned)
			failed += 1
		else:
			print("OK no %s in profiler" % banned)
	# physics_server_step may appear only as a forbidden-named guard, not as a live section writer.
	if 'section_map["physics_server_step"]' in pp or "begin(\"physics_server_step\")" in pp:
		push_error("FAIL: physics_server_step used as live section")
		failed += 1
	else:
		print("OK physics_server_step not a live section")
	if "begin(SECTION_PHYSICS)" not in probe and 'begin("physics_callbacks")' not in probe:
		# Probe uses const SECTION_PHYSICS := "physics_callbacks"
		if 'SECTION_PHYSICS := "physics_callbacks"' not in probe:
			push_error("FAIL: probe must begin physics_callbacks via real begin")
			failed += 1
		else:
			print("OK probe physics_callbacks const + begin")
	else:
		print("OK probe physics_callbacks begin site")
	if 'SECTION_PROCESS := "process_callbacks"' not in probe:
		push_error("FAIL: probe must begin process_callbacks via real begin")
		failed += 1
	else:
		print("OK probe process_callbacks const + begin")
	if "MainLoop_physics" in probe and 'begin("MainLoop_physics")' in probe:
		push_error("FAIL: probe still begins MainLoop_physics (use physics_callbacks)")
		failed += 1
	# Exclusive nest without remapping
	if profiler.has_method("mark_frame_work_start"):
		profiler.mark_frame_work_start()
	profiler.begin("physics_callbacks")
	OS.delay_usec(2000)
	profiler.begin("entity_physics")
	OS.delay_usec(3000)
	profiler.end("entity_physics")
	OS.delay_usec(1500)
	profiler.end("physics_callbacks")
	if profiler.has_method("finalize_frame"):
		profiler.finalize_frame()
	var attr: Dictionary = profiler.get_attribution()
	var cats: Dictionary = attr.get("categories", {})
	var parent_ex: float = float(cats.get("physics_callbacks", {}).get("ms", 0.0))
	var child_ex: float = float(cats.get("entity_physics", {}).get("ms", 0.0))
	print("exclusive physics_callbacks=%.3f entity_physics=%.3f" % [parent_ex, child_ex])
	# Parent exclusive = inter-child gaps only (must not include child exclusive).
	if child_ex < 2.0:
		push_error("FAIL: entity_physics exclusive missing")
		failed += 1
	if parent_ex < 1.0:
		push_error("FAIL: physics_callbacks exclusive missing gaps (got %.3f)" % parent_ex)
		failed += 1
	elif parent_ex > child_ex * 4.0 + 20.0:
		# Pathological double-count if parent inclusive leaked into exclusive.
		push_error("FAIL: physics_callbacks exclusive looks double-counted (got %.3f)" % parent_ex)
		failed += 1
	else:
		print("OK hierarchical exclusive on real physics_callbacks begin/end")
	if str(cats.get("physics_callbacks", {}).get("gate", "")) != "named":
		push_error("FAIL: physics_callbacks must be gate=named")
		failed += 1
	# section_map published for re-account
	if not attr.has("section_map"):
		push_error("FAIL: attribution must publish raw section_map")
		failed += 1
	else:
		var re: Dictionary = profiler.account_main_thread_frame(
			attr.get("section_map", {}), int(attr.get("wall_us", 1))
		)
		if absf(float(re.get("named_pct", 0.0)) - float(attr.get("named_pct", -1.0))) > 0.5:
			push_error("FAIL: re-account of section_map diverges from live attribution")
			failed += 1
		else:
			print("OK pure re-account matches live (no remapping)")
	return failed


func _collect_begin_record_names() -> Dictionary:
	## name -> true if found as begin("name") or record_us("name") in production sources.
	var found: Dictionary = {}
	var paths: Array = []
	for root_path in PROD_GLOBS:
		if root_path.ends_with(".gd"):
			paths.append(root_path)
			continue
		_collect_gd_files(root_path, paths)
	for path in paths:
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			continue
		# begin("section") / record_us("section"
		var i := 0
		while true:
			var b := text.find('begin("', i)
			var r := text.find('record_us("', i)
			var pos := -1
			var prefix_len := 0
			if b >= 0 and (r < 0 or b < r):
				pos = b
				prefix_len = 7  # begin("
			elif r >= 0:
				pos = r
				prefix_len = 11  # record_us("
			else:
				break
			var start := pos + prefix_len
			var end := text.find('"', start)
			if end < 0:
				break
			var name: String = text.substr(start, end - start)
			if not name.is_empty() and not name.begins_with("%"):
				found[name] = true
			i = end + 1
		# Also const SECTION_* := "name" in probe
		if "physics_callbacks" in text:
			found["physics_callbacks"] = true
		if "process_callbacks" in text:
			found["process_callbacks"] = true
	return found


func _collect_gd_files(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		if fn.begins_with("."):
			fn = d.get_next()
			continue
		var full: String = dir_path.path_join(fn)
		if d.current_is_dir():
			_collect_gd_files(full, out)
		elif fn.ends_with(".gd"):
			out.append(full)
		fn = d.get_next()
	d.list_dir_end()


func _test_gameplay_walk_gate() -> int:
	var failed := 0
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		push_error("FAIL: main missing")
		return 1
	var game: Node = packed.instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var w := 0
	while compose and not bool(compose.get("_boot_done")) and w < 3600:
		await process_frame
		w += 1
	for _i in 15:
		await process_frame
	var profiler: Node = root.get_node_or_null("/root/PerfProfiler")
	var player: Node = get_first_node_in_group("player")
	var cm = get_first_node_in_group("chunk_manager")
	if profiler == null or player == null:
		push_error("FAIL: boot incomplete")
		game.queue_free()
		return 1
	profiler.enabled = true
	var begin_names: Dictionary = _collect_begin_record_names()
	var coords: Array = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(2, -1), Vector2i(0, 2),
		Vector2i(-2, 0), Vector2i(1, 1),
	]
	var named_ms_sum := 0.0
	var unknown_ms_sum := 0.0
	var full_wall_sum := 0.0
	var n := 0
	var samples: Array = []
	for c in coords:
		if player:
			player.global_position = Vector3(float(c.x * 16) + 8.0, player.global_position.y, float(c.y * 16) + 8.0)
		if cm and cm.has_method("update_stream"):
			cm.update_stream(c.x, c.y)
		for _j in 10:
			await process_frame
			var attr: Dictionary = profiler.get_attribution()
			var full: float = float(attr.get("wall_ms", 0.0))
			if full <= 0.01:
				continue
			var cats: Dictionary = attr.get("categories", {})
			for bad in FORBIDDEN_NAMED:
				if cats.has(bad) and str(cats[bad].get("gate", "")) == "named":
					push_error("FAIL: forbidden residual rebrand named: %s" % bad)
					failed += 1
			# Re-score with pure account on raw section_map
			var sm: Dictionary = attr.get("section_map", {})
			if sm.is_empty():
				push_error("FAIL: walk attribution missing section_map")
				failed += 1
			else:
				var pure: Dictionary = profiler.account_main_thread_frame(
					sm, int(attr.get("wall_us", 1))
				)
				if absf(float(pure.get("named_pct", 0.0)) - float(attr.get("named_pct", -99.0))) > 1.0:
					push_error(
						"FAIL: live named_pct diverges from pure re-account (remap?)"
					)
					failed += 1
				named_ms_sum += float(pure.get("named_ms", 0.0))
				unknown_ms_sum += float(pure.get("unknown_ms", 0.0))
				full_wall_sum += float(pure.get("wall_ms", full))
			n += 1
			samples.append(attr)
	game.queue_free()
	await process_frame
	if n < 5:
		push_error("FAIL: too few samples")
		return failed + 1
	# Call-site audit once on the last sample's named set.
	if samples.size() > 0:
		var last_cats: Dictionary = samples[samples.size() - 1].get("categories", {})
		for k in last_cats.keys():
			if str(last_cats[k].get("gate", "")) != "named":
				continue
			if not begin_names.has(str(k)):
				push_error(
					"FAIL: named category '%s' has no production begin/record_us call site"
					% str(k)
				)
				failed += 1
			else:
				print("OK named call site: %s" % str(k))
	var session_named_pct: float = 100.0 * named_ms_sum / maxf(full_wall_sum, 0.001)
	var session_unknown_pct: float = 100.0 * unknown_ms_sum / maxf(full_wall_sum, 0.001)
	var avg_full: float = full_wall_sum / float(n)
	print(
		"WALK_GATE samples=%d session_named_pct=%.2f session_unknown_pct=%.2f avg_full_ms=%.2f"
		% [n, session_named_pct, session_unknown_pct, avg_full]
	)
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	var f := FileAccess.open(scratch.path_join("verify_attr_walk_gate.log"), FileAccess.WRITE)
	if f:
		f.store_string(
			"samples=%d session_named_pct=%.4f session_unknown_pct=%.4f avg_full_ms=%.4f pass=%s\n"
			% [
				n, session_named_pct, session_unknown_pct, avg_full,
				str(session_named_pct >= 95.0 and session_unknown_pct <= 5.0),
			]
		)
		if samples.size() > 0:
			var last: Dictionary = samples[samples.size() - 1]
			f.store_string(
				"last full=%.3f named=%.2f unknown=%.2f gap=%.3f\n"
				% [
					float(last.get("wall_ms", 0.0)),
					float(last.get("named_pct", 0.0)),
					float(last.get("unknown_pct", 0.0)),
					float(last.get("inter_frame_gap_ms", 0.0)),
				]
			)
			var lc: Dictionary = last.get("categories", {})
			for k in lc.keys():
				f.store_string(
					"  %s ms=%.3f gate=%s\n"
					% [str(k), float(lc[k].get("ms", 0.0)), str(lc[k].get("gate", ""))]
				)
		f.close()
	if session_named_pct < 95.0:
		push_error("FAIL: session named_pct %.2f < 95 (of full wall, pure re-account)" % session_named_pct)
		failed += 1
	else:
		print("OK walk session named_pct>=95 of full wall")
	if session_unknown_pct > 5.0:
		push_error("FAIL: session unknown_pct %.2f > 5 (of full wall, pure re-account)" % session_unknown_pct)
		failed += 1
	else:
		print("OK walk session unknown_pct<=5 of full wall")
	return failed
