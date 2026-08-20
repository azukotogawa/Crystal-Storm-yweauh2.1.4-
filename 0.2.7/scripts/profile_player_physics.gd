extends SceneTree
## Exclusive breakdown of Player::_physics_process (measure only).
##
## Usage:
##   CRYSTALSTORM_PLAYER_PHYSICS_MEASURE=1 CRYSTALSTORM_BAKE_RADIUS=2 \
##   godot --headless -s scripts/profile_player_physics.gd

const SAMPLE_FRAMES := 300


func _initialize() -> void:
	OS.set_environment("CRYSTALSTORM_PLAYER_PHYSICS_MEASURE", "1")
	if OS.get_environment("CRYSTALSTORM_BAKE_RADIUS").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	if OS.get_environment("CRYSTALSTORM_PERF_PRESET").is_empty():
		OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	call_deferred("_run")


func _run() -> void:
	print("=== PLAYER PHYSICS BREAKDOWN ===")
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		push_error("scene fail")
		quit(1)
		return
	await process_frame
	await process_frame

	var player = null
	var frames := 0
	while frames < 1500:
		await process_frame
		frames += 1
		var root := current_scene
		if root == null:
			continue
		player = root.get_tree().get_first_node_in_group("player")
		var composition = root.get_tree().get_first_node_in_group("composition_root")
		if composition and int(composition.stage) >= 7 and player and bool(player.get("world_ready")):
			break

	if player == null:
		push_error("no player")
		quit(1)
		return

	if player.has_method("set_physics_measure_enabled"):
		player.set_physics_measure_enabled(true)
		player.reset_physics_measure()

	# Continuous movement to exercise move/collision path.
	var dirs: Array[String] = ["ui_right", "ui_up", "ui_left", "ui_down"]
	var dir_i := 0
	for i in SAMPLE_FRAMES:
		# Hold one direction for 20 frames then rotate
		if i % 20 == 0:
			for d in dirs:
				Input.action_release(d)
			Input.action_press(dirs[dir_i % dirs.size()])
			dir_i += 1
		# Occasional jump
		if i % 45 == 10:
			Input.action_press("jump")
		elif i % 45 == 11:
			Input.action_release("jump")
		await process_frame

	for d in dirs:
		Input.action_release(d)
	Input.action_release("jump")

	var report: Dictionary = {}
	if player.has_method("get_physics_measure"):
		report = player.get_physics_measure()

	_print_report(report)
	_write_flamegraph(report)

	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-23417f42e77b/implementer"
	DirAccess.make_dir_recursive_absolute(scratch)
	var path := scratch.path_join("player_physics_profile.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()
		print("WROTE ", path)
	print("=== PLAYER PHYSICS BREAKDOWN END ===")
	quit(0)


func _print_report(r: Dictionary) -> void:
	print("\n========== Player::_physics_process EXCLUSIVE ==========")
	print("frames=%s  total=%.2fms  avg=%.3fms  max=%.3fms  worst_frame=%s" % [
		r.get("frames", 0),
		float(r.get("total_ms", 0)),
		float(r.get("avg_ms", 0)),
		float(r.get("max_ms", 0)),
		r.get("worst_frame", 0),
	])
	print("\nCall counts (player helpers):")
	var cc: Dictionary = r.get("call_counts", {})
	for k in cc.keys():
		print("  %-28s %s" % [k, cc[k]])

	print("\nRanked phases inside _physics_process (sum exclusive wall of phase blocks):")
	print("| rank | phase | calls | total_ms | avg_us | max_us | share |")
	var rank := 1
	for ph in r.get("phases", []):
		print("| %4d | %s | %d | %.3f | %.1f | %d | %.1f%% |" % [
			rank, ph.get("phase"), int(ph.get("calls", 0)),
			float(ph.get("total_ms", 0)), float(ph.get("avg_us", 0)),
			int(ph.get("max_us", 0)), float(ph.get("share_of_sum", 0)) * 100.0,
		])
		rank += 1

	print("\nWorst-frame phase timeline (us in that frame):")
	var wp: Dictionary = r.get("worst_phases", {})
	var rows: Array = []
	for k in wp.keys():
		rows.append({"k": k, "us": int(wp[k])})
	rows.sort_custom(func(a, b): return int(a.us) > int(b.us))
	for row in rows:
		print("  %-22s %6d us  (%.3f ms)" % [row.k, row.us, float(row.us) / 1000.0])

	print("\nVoxelFloorProbe nested (terrain / collision / world queries):")
	var pr: Dictionary = r.get("floor_probe", {})
	var leaves: Array = [
		["walkable_height", pr.get("walkable_height_calls", 0), pr.get("walkable_height_us", 0)],
		["sample_walkable_feet", pr.get("sample_feet_calls", 0), pr.get("sample_feet_us", 0)],
		["can_step_to", pr.get("can_step_calls", 0), pr.get("can_step_us", 0)],
		["is_blocked_at", pr.get("blocked_calls", 0), pr.get("blocked_us", 0)],
		["is_grounded_at", pr.get("grounded_calls", 0), pr.get("grounded_us", 0)],
	]
	print("| leaf | calls | total_ms | avg_us |")
	for L in leaves:
		var c: int = int(L[1])
		var u: int = int(L[2])
		print("| %s | %d | %.3f | %.1f |" % [L[0], c, float(u) / 1000.0, float(u) / float(maxi(c, 1))])
	print("World query counts: surface_height=%s tile_type=%s get_solid=%s ramp=%s cave=%s crystal_h=%s" % [
		pr.get("world_get_surface_height", 0),
		pr.get("world_get_tile_type", 0),
		pr.get("world_get_solid", 0),
		pr.get("ramp_entry", 0),
		pr.get("cave_floor", 0),
		pr.get("crystal_walkable_height", 0),
	])

	# Dominant identification
	var top_phase := ""
	var top_us := 0
	for ph in r.get("phases", []):
		if int(ph.get("total_us", 0)) > top_us:
			top_us = int(ph.get("total_us", 0))
			top_phase = str(ph.get("phase"))
	var probe_can := int(pr.get("can_step_us", 0))
	var probe_ground := int(pr.get("grounded_us", 0))
	var probe_sample := int(pr.get("sample_feet_us", 0))
	var probe_walk := int(pr.get("walkable_height_us", 0))
	print("\n*** Dominant player phase: %s (%.1f%% of phase sum) ***" % [
		top_phase, float(top_us) / float(maxi(int(r.get("total_us", 1)), 1)) * 100.0,
	])
	print("*** Dominant nested cost: walkable_height_at (terrain) total %.2fms; called via sample_feet/can_step/grounded ***" % [
		float(probe_walk) / 1000.0,
	])
	print("Recommendation: cache multi-offset walkable_height samples per physics frame (same feet column set), or reduce probe offsets / reuse last snap height when still grounded.")
	print("======================================================\n")


func _write_flamegraph(r: Dictionary) -> void:
	# Folded stacks for speedscope / flamegraph.pl
	var lines: PackedStringArray = PackedStringArray()
	var frames: int = maxi(int(r.get("frames", 1)), 1)
	# Represent total us as sample counts (1 sample = 1 us)
	for ph in r.get("phases", []):
		var name: String = str(ph.get("phase", "?"))
		var us: int = int(ph.get("total_us", 0))
		if us <= 0:
			continue
		lines.append("Player::_physics_process;%s %d" % [name, us])
	var pr: Dictionary = r.get("floor_probe", {})
	var nest := {
		"horizontal_move": ["can_step_to", "sample_walkable_feet", "walkable_height_at", "is_blocked_at"],
		"vertical_state": ["snap_to_ground", "is_grounded_at", "sample_walkable_feet", "walkable_height_at"],
		"slope_speed": ["walkable_height_at"],
		"jump_check": ["is_grounded_at", "walkable_height_at"],
	}
	# Nested exclusive-ish leaves under walkable
	var wh: int = int(pr.get("walkable_height_us", 0))
	if wh > 0:
		lines.append("Player::_physics_process;horizontal_move;can_step_to;sample_walkable_feet;walkable_height_at %d" % maxi(wh / 2, 1))
		lines.append("Player::_physics_process;vertical_state;is_grounded_at;sample_walkable_feet;walkable_height_at %d" % maxi(wh / 2, 1))
	var sh: int = int(pr.get("world_get_surface_height", 0))
	# use counts as samples for query intensity
	if sh > 0:
		lines.append("Player::_physics_process;terrain_queries;world.get_surface_height %d" % sh)
	var tt: int = int(pr.get("world_get_tile_type", 0))
	if tt > 0:
		lines.append("Player::_physics_process;terrain_queries;world.get_tile_type %d" % tt)
	var gs: int = int(pr.get("world_get_solid", 0))
	if gs > 0:
		lines.append("Player::_physics_process;collision;world.get_solid %d" % gs)
	var re: int = int(pr.get("ramp_entry", 0))
	if re > 0:
		lines.append("Player::_physics_process;terrain_queries;chunk_manager.get_ramp_entry %d" % re)

	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-23417f42e77b/implementer"
	var path := scratch.path_join("player_physics_flamegraph.folded")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
		f.close()
		print("WROTE flamegraph folded stacks: ", path)
