extends SceneTree
## Headless gameplay profile — samples PerfProfiler each frame, ranks top frame-time consumers.


const MAIN_SCENE := "res://scenes/main.tscn"
const _SmokeProbeHelpers = preload("res://scripts/smoke_probe_helpers.gd")
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _EntityBrainRegistry = preload("res://entities/entity_brain_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")


const CONSUMER_KEYS: Array[String] = [
	"untracked",
	"worker_total",
	"crystal_manager",
	"crystal_sim",
	"crystal_mesh",
	"chunk_manager",
	"chunk_mesh",
	"chunk_column",
	"chunk_upload",
	"chunk_buffer",
	"chunk_apply",
	"chunk_view_setup",
	"chunk_scenetree_insert",
	"stream_schedule",
	"stream_update",
	"player_physics",
	"camera_update",
	"entity_physics",
	"entity_navigation",
	"entity_combat",
	"target_highlight",
	"weapon_controller",
	"game_manager",
	"ui_overlay",
	"combat_vfx",
	"terrain_editor",
	"enemy_spawner",
	"living_world",
	"town_defense",
	"voxel_fluid",
	"vegetation_growth",
	"map_build",
	"debug_panel",
]


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	call_deferred("_run")


func _run() -> void:
	var session_sec := _session_seconds()
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH").strip_edges()
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-59b157a7ebbb/implementer"

	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		push_error("profile: main scene missing")
		quit(1)
		return

	var game: Node = main_packed.instantiate()
	root.add_child(game)

	var player: Node = null
	var chunk_manager: ChunkManager = null
	var terrain: TerrainEditor = null
	var world: InfiniteNoiseWorld = null
	var crystal: CrystalManager = null
	var weapon: Node = null
	var entity_mgr = null
	var profiler: Node = root.get_node_or_null("/root/PerfProfiler")

	for _attempt in 900:
		player = get_first_node_in_group("player")
		chunk_manager = get_first_node_in_group("chunk_manager")
		terrain = get_first_node_in_group("terrain_editor")
		world = get_first_node_in_group("world")
		crystal = get_first_node_in_group("crystal_manager")
		entity_mgr = get_first_node_in_group("entity_manager")
		weapon = player.get_node_or_null("WeaponController") if player else null
		if (
			player != null and chunk_manager != null and terrain != null
			and world != null and crystal != null and crystal._initialized
			and profiler != null and bool(player.get("world_ready"))
		):
			break
		await process_frame

	if player == null or profiler == null:
		push_error("profile: bootstrap timeout")
		quit(1)
		return

	_EntityBrainRegistry.ensure_builtins()
	var inv = player.get("inventory")
	if inv:
		inv.set_slot(1, "stone_pick", 1)
		inv.set_slot(0, "wooden_sword", 1)

	var frame_samples: Array[float] = []
	var untracked_samples: Array[float] = []
	var consumer_samples: Dictionary = {}
	var func_max: Dictionary = {}  # name -> max_ms
	var func_sum: Dictionary = {}
	var func_n: Dictionary = {}
	for key in CONSUMER_KEYS:
		consumer_samples[key] = []

	var session_end_ms := Time.get_ticks_msec() + int(session_sec * 1000.0)
	var session_frames := 0
	var move_dirs: Array[String] = ["ui_right", "ui_up", "ui_left", "ui_down"]
	var dir_idx := 0
	var spawned_entity: Node = null

	print("PROFILE session=%.0fs preset=MEDIUM" % session_sec)

	while Time.get_ticks_msec() < session_end_ms:
		await process_frame
		session_frames += 1
		var phase := session_frames % 180
		var move_action := move_dirs[dir_idx % move_dirs.size()]
		if phase < 90:
			Input.action_press(move_action)
		else:
			Input.action_release(move_action)
			if phase == 90:
				dir_idx += 1

		if phase == 30 and weapon and weapon.has_method("_try_dig"):
			if weapon.has_method("set_active_hotbar_index"):
				weapon.set_active_hotbar_index(1)
			weapon.set("_cooldown_timer", 0.0)
			weapon.call("_try_dig")
		elif phase == 60:
			Input.action_press("jump")
		elif phase == 62:
			Input.action_release("jump")
		elif phase == 120 and weapon:
			if spawned_entity == null or not is_instance_valid(spawned_entity):
				if entity_mgr:
					var col: Vector3 = player.get_voxel_position()
					var spawn_cell := Vector2i(floori(col.x) + 1, floori(col.z))
					var brain = _EntityBrainRegistry.get_def(&"rabbit")
					if brain:
						entity_mgr.call(
							"_spawn_world_entity",
							spawn_cell.x, spawn_cell.y, brain, spawn_cell, Color(0.7, 0.6, 0.5)
						)
			if weapon.has_method("set_active_hotbar_index"):
				weapon.set_active_hotbar_index(0)
			weapon.set("_cooldown_timer", 0.0)
			weapon.call("_try_attack")

		if player.has_method("_sync_global_from_voxel"):
			player.call("_sync_global_from_voxel")

		# Avoid walking entire scene tree every frame (that itself was untracked cost).
		if session_frames % 30 == 0 and profiler.has_method("sample_scene_stats"):
			profiler.sample_scene_stats(self)
		var snap: Dictionary = profiler.get_snapshot() if profiler.has_method("get_snapshot") else {}
		frame_samples.append(float(snap.get("frame_ms", 0.0)))
		var u := float(snap.get("untracked_ms", 0.0))
		untracked_samples.append(u)
		_append_consumer_sample(consumer_samples, "untracked", u)
		_append_consumer_sample(consumer_samples, "worker_total", float(snap.get("worker_ms", 0.0)))
		var secs: Dictionary = snap.get("sections", {})
		for key in CONSUMER_KEYS:
			if key in ["untracked", "worker_total"]:
				continue
			var ms := 0.0
			if secs.has(key):
				ms = float(secs[key].get("last_ms", 0.0))
			_append_consumer_sample(consumer_samples, key, ms)
		var funcs: Dictionary = snap.get("funcs", {})
		for fk in funcs.keys():
			var fms := float(funcs[fk].get("last_ms", 0.0))
			# Session max from last-frame samples only (not process-lifetime max_ms).
			func_sum[fk] = float(func_sum.get(fk, 0.0)) + fms
			func_n[fk] = int(func_n.get(fk, 0)) + 1
			func_max[fk] = maxf(float(func_max.get(fk, 0.0)), fms)

	for action in move_dirs + ["jump", "attack"]:
		Input.action_release(action)

	if chunk_manager and chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle()

	if chunk_manager and chunk_manager.has_method("release_all_chunks_for_teardown"):
		chunk_manager.release_all_chunks_for_teardown()

	var report := _build_report(
		session_sec, session_frames, frame_samples, consumer_samples,
		untracked_samples, func_sum, func_n, func_max
	)
	var report_path := "%s/gameplay_profile_report.md" % scratch
	_write_text(report_path, report)
	print(report)
	print("PROFILE_REPORT_PATH=%s" % report_path)
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT") == "1":
		OS.kill(OS.get_process_id())
		return
	quit(0)


func _session_seconds() -> float:
	var raw := OS.get_environment("PROFILE_SESSION_SEC").strip_edges()
	if raw.is_empty():
		return 45.0
	return clampf(float(raw), 10.0, 180.0)


func _append_consumer_sample(samples: Dictionary, key: String, ms: float) -> void:
	if not samples.has(key):
		samples[key] = []
	(samples[key] as Array).append(ms)


func _build_report(
	session_sec: float,
	frames: int,
	frame_samples: Array,
	consumer_samples: Dictionary,
	untracked_samples: Array = [],
	func_sum: Dictionary = {},
	func_n: Dictionary = {},
	func_max: Dictionary = {}
) -> String:
	var stamp := Time.get_datetime_string_from_system()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Gameplay frame-time profile (Phase 2 attribution)")
	lines.append("")
	lines.append("**Method:** Headless scripted session on production `main.tscn` (move, dig, jump, melee).")
	lines.append("**Preset:** MEDIUM | **Duration:** %.0fs | **Frames sampled:** %d | **Captured:** %s" % [
		session_sec, frames, stamp,
	])
	lines.append("")
	lines.append("Instrumentation via `PerfProfiler` (main vs worker stages; function hotspots).")
	lines.append("Measurement only — no gameplay optimization in this run.")
	lines.append("")
	lines.append("## Overall frame time (main thread)")
	lines.append("")
	lines.append("| Metric | ms |")
	lines.append("|--------|-----|")
	lines.append("| Average | %.3f |" % _mean(frame_samples))
	lines.append("| 95th percentile | %.3f |" % _percentile(frame_samples, 0.95))
	lines.append("| Worst frame | %.3f |" % _max(frame_samples))
	lines.append("| Implied avg FPS | %.1f |" % _fps_from_mean_ms(_mean(frame_samples)))
	if not untracked_samples.is_empty():
		lines.append("| **Unknown main (avg)** | **%.3f** |" % _mean(untracked_samples))
		lines.append("| Unknown main (p95) | %.3f |" % _percentile(untracked_samples, 0.95))
		lines.append("| Unknown main (worst) | %.3f |" % _max(untracked_samples))
	lines.append("")

	var ranked: Array = []
	for key in CONSUMER_KEYS:
		var arr: Array = consumer_samples.get(key, [])
		if arr.is_empty():
			continue
		ranked.append({
			"name": key,
			"avg": _mean(arr),
			"p95": _percentile(arr, 0.95),
			"worst": _max(arr),
		})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.avg) > float(b.avg)
	)

	lines.append("## Top 10 hottest subsystems (avg ms)")
	lines.append("")
	lines.append("| Rank | Consumer | Avg (ms) | P95 (ms) | Worst (ms) |")
	lines.append("|------|----------|----------|----------|------------|")
	var top_n := mini(10, ranked.size())
	for i in top_n:
		var row: Dictionary = ranked[i]
		lines.append(
			"| %d | %s | %.3f | %.3f | %.3f |"
			% [i + 1, str(row.name), float(row.avg), float(row.p95), float(row.worst)]
		)
	lines.append("")

	# Hot functions by average last-frame contribution
	var func_ranked: Array = []
	for fk in func_sum.keys():
		var n: int = maxi(int(func_n.get(fk, 1)), 1)
		func_ranked.append({
			"name": str(fk),
			"avg": float(func_sum[fk]) / float(n),
			"max": float(func_max.get(fk, 0.0)),
		})
	func_ranked.sort_custom(func(a, b): return float(a.avg) > float(b.avg))
	lines.append("## Top 10 hottest functions (avg last-frame ms)")
	lines.append("")
	lines.append("| Rank | Function | Avg (ms) | Max (ms) |")
	lines.append("|------|----------|----------|----------|")
	var ftop := mini(10, func_ranked.size())
	for i in ftop:
		var fr: Dictionary = func_ranked[i]
		lines.append("| %d | `%s` | %.3f | %.3f |" % [
			i + 1, str(fr.name), float(fr.avg), float(fr.max)
		])
	lines.append("")

	func_ranked.sort_custom(func(a, b): return float(a.max) > float(b.max))
	lines.append("## Top hitch functions (by max ms)")
	lines.append("")
	lines.append("| Rank | Function | Max (ms) | Avg (ms) |")
	lines.append("|------|----------|----------|----------|")
	for i in mini(10, func_ranked.size()):
		var fr2: Dictionary = func_ranked[i]
		lines.append("| %d | `%s` | %.3f | %.3f |" % [
			i + 1, str(fr2.name), float(fr2.max), float(fr2.avg)
		])
	lines.append("")

	lines.append("## All tracked consumers (reference)")
	lines.append("")
	lines.append("| Consumer | Avg (ms) | P95 (ms) | Worst (ms) |")
	lines.append("|----------|----------|----------|------------|")
	for row in ranked:
		lines.append(
			"| %s | %.3f | %.3f | %.3f |"
			% [str(row.name), float(row.avg), float(row.p95), float(row.worst)]
		)
	lines.append("")
	lines.append("## Notes")
	lines.append("")
	lines.append("- **untracked** — main-thread ms not covered by named *main* sections (worker stages excluded).")
	lines.append("- **worker_total / chunk_mesh / chunk_column / chunk_buffer** — worker-attributed; not subtracted from untracked.")
	lines.append("- Function rows are per-frame last samples averaged over the session.")
	return "\n".join(lines)


static func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sum := 0.0
	for v in values:
		sum += float(v)
	return sum / float(values.size())


static func _max(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var m := 0.0
	for v in values:
		m = maxf(m, float(v))
	return m


static func _percentile(values: Array, p: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array = values.duplicate()
	sorted.sort()
	var idx := clampi(int(ceilf(p * float(sorted.size())) - 1.0), 0, sorted.size() - 1)
	return float(sorted[idx])


static func _fps_from_mean_ms(mean_ms: float) -> float:
	if mean_ms <= 0.001:
		return 0.0
	return 1000.0 / mean_ms


static func _write_text(path: String, body: String) -> void:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(body)
		f.close()