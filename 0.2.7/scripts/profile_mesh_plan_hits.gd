extends SceneTree
## Walk/stream the baked world and report every mesh plan hit/miss reason.
## Usage:
##   CRYSTALSTORM_MESH_PLAN_TRACE=1 godot --headless -s scripts/profile_mesh_plan_hits.gd
## Optional: CRYSTALSTORM_WALK_SEC=60 CRYSTALSTORM_SCRATCH=...

const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_STARTUP_PROFILE", "1")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_TRACE", "1")
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_BAKE_ON_NEW", "0")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	if OS.get_environment("CRYSTALSTORM_SCRATCH").is_empty():
		OS.set_environment("CRYSTALSTORM_SCRATCH", "/tmp/grok-goal-3c89103bbbb9/implementer")
	call_deferred("_run")


func _run() -> void:
	var walk_sec: float = float(OS.get_environment("CRYSTALSTORM_WALK_SEC"))
	if walk_sec <= 0.0:
		walk_sec = 60.0
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		push_error("main missing")
		_ProbeExit.finish_tree(self, 1, "MESH_PLAN_HIT_PROFILE FAILED")
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while compose and not bool(compose.get("_boot_done")) and frames < 3600:
		await process_frame
		frames += 1
	if compose and not bool(compose.get("_boot_done")):
		push_error("boot incomplete")
		_ProbeExit.finish_tree(self, 1, "MESH_PLAN_HIT_PROFILE FAILED")
		return

	var mp = load("res://world/mesh_plan_cache.gd")
	var cache = mp.get_active() if mp else null
	if cache == null:
		push_error("MeshPlanCache inactive")
		_ProbeExit.finish_tree(self, 1, "MESH_PLAN_HIT_PROFILE FAILED")
		return
	cache.begin_trace()
	print("MESH_PLAN_TRACE begin streamed=%s valid=%s" % [
		str(cache.streamed_from_bake), str(cache.valid)
	])

	var player = game.get_node_or_null("Player")
	if player == null:
		# Find player in tree
		var nodes := game.find_children("*", "CharacterBody3D", true, false)
		if nodes.is_empty():
			nodes = game.find_children("*", "Node3D", true, false)
		for n in nodes:
			if str(n.name).to_lower().contains("player") or n.is_in_group("player"):
				player = n
				break
	var cm = null
	var reg = compose.get("registry") if compose else null
	if reg and reg.has_method("resolve"):
		cm = reg.resolve(&"chunk_manager")
	if cm == null:
		cm = game.find_child("ChunkManager", true, false)

	var t0 := Time.get_ticks_msec()
	var step := 0
	# Simulated walk: move through chunk grid to force stream loads across bake bounds.
	var path: Array = []
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
	# Snake through package coords only (baked world walk). Outside-package
	# rebuilds are expected and measured separately when path leaves bounds.
	var include_outside := OS.get_environment("CRYSTALSTORM_WALK_OUTSIDE") == "1"
	for cz in range(min_cz, max_cz + 1):
		var xs: Array = range(min_cx, max_cx + 1)
		if (cz - min_cz) % 2 == 1:
			xs.reverse()
		for cx in xs:
			path.append(Vector2i(cx, cz))
	# Repeat path to fill 60s inside bake.
	var base_path: Array = path.duplicate()
	while path.size() < 200:
		path.append_array(base_path)
	if include_outside:
		path.append(Vector2i(max_cx + 1, 0))
		path.append(Vector2i(min_cx - 1, 0))

	var path_i := 0
	var last_move_ms := t0
	while Time.get_ticks_msec() - t0 < int(walk_sec * 1000.0):
		# Advance target every ~0.35s so stream keeps loading.
		if Time.get_ticks_msec() - last_move_ms >= 350 and path_i < path.size():
			var target: Vector2i = path[path_i]
			path_i += 1
			last_move_ms = Time.get_ticks_msec()
			var wx: float = float(target.x * 16) + 8.0
			var wz: float = float(target.y * 16) + 8.0
			if player and player.has_method("set_global_position"):
				var p: Vector3 = player.global_position
				player.global_position = Vector3(wx, p.y, wz)
			elif player:
				player.global_position = Vector3(wx, player.global_position.y, wz)
			if cm and cm.has_method("update_stream"):
				cm.update_stream(target.x, target.y)
			elif cm and cm.has_method("request_chunk"):
				for dz in range(-2, 3):
					for dx in range(-2, 3):
						cm.request_chunk(Vector2i(target.x + dx, target.y + dz), true)
		await process_frame
		step += 1

	var summary: Dictionary = cache.summary_report()
	var log: Array = cache.decision_log.duplicate(true)
	print("MESH_PLAN_SUMMARY %s" % JSON.stringify(summary))
	print("decision\tcoord\tpackage\tplan_exists\tplan_loaded\thit\treason\tdetail\trebuild_ms")
	for d in log:
		print("%s\t(%d,%d)\t%s\t%s\t%s\t%s\t%s\t%s\t-" % [
			str(d.get("mesh_source", "")),
			int(d.get("coord_x", 0)),
			int(d.get("coord_z", 0)),
			str(d.get("package_exists", false)),
			str(d.get("mesh_plan_exists_in_package", false)),
			str(d.get("mesh_plan_loaded", false)),
			str(d.get("cache_hit", false)),
			str(d.get("rebuild_reason", "")),
			str(d.get("detail", "")),
		])
	# Reason histogram
	print("REASON_HISTOGRAM")
	var reasons: Dictionary = summary.get("reasons", {})
	for k in reasons.keys():
		print("  %s = %d" % [str(k), int(reasons[k])])

	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	var out_path := scratch.path_join("mesh_plan_hit_report.json")
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"summary": summary,
			"decisions": log,
			"walk_sec": walk_sec,
			"path_len": path.size(),
			"frames": step,
			"bake_bounds": {
				"min_cx": min_cx, "max_cx": max_cx, "min_cz": min_cz, "max_cz": max_cz,
			},
		}, "\t"))
		f.close()
		print("WROTE %s" % out_path)
	cache.end_trace()
	_ProbeExit.finish_tree(self, 0, "MESH_PLAN_HIT_PROFILE_OK")
