extends SceneTree
## Phase-1 mesh/apply timing on real ChunkPipeline + ChunkView path.
## Usage: godot --headless -s scripts/profile_mesh_phases.gd
## Writes mesh_phase_profile.json under CRYSTALSTORM_SCRATCH.

const _WorldState = preload("res://world/world_state.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkPipeline = preload("res://chunks/chunk_pipeline.gd")
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")
const _MeshPhaseProfiler = preload("res://systems/mesh_phase_profiler.gd")
const _WorldBakeService = preload("res://world/world_bake_service.gd")

const SEED := 424242
const RADIUS := 2


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("CRYSTALSTORM_MESH_PHASE_PROFILE", "1")
	OS.set_environment("CRYSTALSTORM_WORLD_BAKE", "1")
	_WorldState.replace_active()
	_MeshPhaseProfiler.begin_session()

	var world = _InfiniteNoiseWorld.new(SEED)
	var bake: _WorldBakeService = _WorldBakeService.ensure_active()
	# Prefer baked columns so residual cost is mesh/apply (post World Bake baseline).
	if not bake.load_bake(SEED, RADIUS):
		bake.bake_world(world, RADIUS)
		bake.save_bake()
		bake.load_bake(SEED, RADIUS)
	_WorldBakeService.set_active(bake)

	var mgr = _ChunkManager.new()
	mgr.prebuild_chunk_buffers = true
	mgr.terrain_surface_mesh = true
	root.add_child(mgr)

	# Optional mesh plan cache (when present / env allows) for after-opt profiles.
	var _MeshPlanCache = load("res://world/mesh_plan_cache.gd")
	if _MeshPlanCache:
		var mpc = _MeshPlanCache.ensure_active()
		if not mpc.load_plans(SEED, RADIUS):
			# Leave miss so baseline profiles measure pure generate mesh_plan.
			pass
		else:
			_MeshPlanCache.set_active(mpc)
			print("MeshPlanCache loaded plans=%d" % mpc.plan_count())

	var coords: Array = []
	for cz in range(-RADIUS, RADIUS + 1):
		for cx in range(-RADIUS, RADIUS + 1):
			coords.append(Vector2i(cx, cz))

	var hitch_worst_us := 0
	var load_us_samples: PackedInt64Array = PackedInt64Array()

	for coord in coords:
		var data = _ChunkData.new(coord, world)
		data.capture_worker_snapshot()
		var t_load := Time.get_ticks_usec()
		var job: Dictionary = _ChunkPipeline.run_worker_job(
			mgr,
			data,
			true,
			[],
			Rect2i(0, 0, _ChunkData.SIZE, _ChunkData.SIZE),
			[],
			{},
			true,
			true
		)
		if not bool(job.get("ok", false)):
			push_error("worker job failed for %s" % str(coord))
			continue
		# Apply path: real ChunkView.setup + drain uploads (main-thread phases).
		var view := ChunkView.new()
		var holder := Node3D.new()
		holder.name = "LayerContainer"
		view.add_child(holder)
		root.add_child(view)
		# Rebind layer_container after add
		view.layer_container = holder
		var payload: Dictionary = job.get("payload", {})
		if not payload.has("count"):
			payload["count"] = payload.get("quads", []).size()
		var t_apply := Time.get_ticks_usec()
		view.setup(data, payload)
		# Drain pending uploads fully (no budget cap for profile completeness).
		var drained := 0
		for _i in 64:
			drained += ChunkView.drain_pending_surface_uploads(32, 50_000_000)
			drained += ChunkView.drain_pending_buffer_uploads(32, 50_000_000)
			if ChunkView.pending_surface_upload_count() == 0 \
					and ChunkView.pending_buffer_upload_count() == 0:
				break
		var apply_us: int = Time.get_ticks_usec() - t_apply
		var total_load: int = Time.get_ticks_usec() - t_load
		load_us_samples.append(total_load)
		if apply_us > hitch_worst_us:
			hitch_worst_us = apply_us
		view.queue_free()

	var report: Dictionary = _MeshPhaseProfiler.report()
	report["seed"] = SEED
	report["radius"] = RADIUS
	report["chunks"] = coords.size()
	report["worst_apply_hitch_us"] = hitch_worst_us
	report["avg_chunk_load_us"] = _avg(load_us_samples)
	report["p95_chunk_load_us"] = _p95(load_us_samples)
	report["worst_chunk_load_us"] = _worst(load_us_samples)
	report["decision_note"] = _decision(report)

	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-63743003c13d/implementer"
	var path := scratch.path_join("mesh_phase_profile.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()
		print("WROTE %s" % path)
	else:
		push_error("could not write %s" % path)

	var decision_path := scratch.path_join("MESH_BOTTLENECK_DECISION.md")
	var df := FileAccess.open(decision_path, FileAccess.WRITE)
	if df:
		df.store_string(str(report.get("decision_note", "")))
		df.close()

	print("MESH_PHASE_PROFILE dominant=%s avg_us=%.1f" % [
		str(report.get("dominant_phase", "")),
		float(report.get("dominant_avg_us", 0.0)),
	])
	for s in report.get("phases", []):
		if int(s.get("n", 0)) <= 0:
			continue
		print(
			"  phase=%s n=%d avg=%.1f p95=%d worst=%d"
			% [
				str(s.phase), int(s.n), float(s.avg_us), int(s.p95_us), int(s.worst_us)
			]
		)
	print("  chunk_load avg=%.1f p95=%d worst=%d hitch_apply_worst=%d" % [
		float(report.get("avg_chunk_load_us", 0.0)),
		int(report.get("p95_chunk_load_us", 0)),
		int(report.get("worst_chunk_load_us", 0)),
		hitch_worst_us,
	])
	print("MESH_PHASE_PROFILE_OK")
	_MeshPhaseProfiler.end_session()
	_WorldBakeService.clear_active()
	quit(0)


func _avg(arr: PackedInt64Array) -> float:
	if arr.is_empty():
		return 0.0
	var t := 0
	for v in arr:
		t += int(v)
	return float(t) / float(arr.size())


func _worst(arr: PackedInt64Array) -> int:
	var w := 0
	for v in arr:
		if int(v) > w:
			w = int(v)
	return w


func _p95(arr: PackedInt64Array) -> int:
	if arr.is_empty():
		return 0
	var tmp: Array = []
	for v in arr:
		tmp.append(int(v))
	tmp.sort()
	return int(tmp[mini(tmp.size() - 1, int(floor(float(tmp.size() - 1) * 0.95)))])


func _decision(report: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Mesh Bottleneck Decision")
	lines.append("")
	lines.append("Samples: %d chunks (seed=%d radius=%d, column bake preferred)." % [
		int(report.get("chunks", 0)), SEED, RADIUS
	])
	lines.append("")
	lines.append("| Phase | n | avg µs | p95 µs | worst µs |")
	lines.append("|-------|---|--------|--------|----------|")
	for s in report.get("phases", []):
		if int(s.get("n", 0)) <= 0:
			continue
		lines.append(
			"| %s | %d | %.1f | %d | %d |"
			% [str(s.phase), int(s.n), float(s.avg_us), int(s.p95_us), int(s.worst_us)]
		)
	lines.append("")
	var dom: String = str(report.get("dominant_phase", ""))
	lines.append("**Dominant phase:** `%s` (avg %.1f µs)" % [dom, float(report.get("dominant_avg_us", 0.0))])
	lines.append("")
	if dom == "mesh_plan":
		lines.append("**Chosen optimization:** Mesh Plan Cache (serializable quads/plan only; not GPU resources).")
		lines.append("Rationale: greedy/plan construction is the largest measured mesh-related cost.")
	elif dom in ["gpu_upload", "mesh_object_create", "scenetree_insert", "material_assign", "multimesh_populate"]:
		lines.append("**Chosen optimization:** Apply-path optimization for `%s` (NOT Mesh Plan Cache)." % dom)
		lines.append("Rationale: decision gate forbids mesh-plan cache when upload/object/SceneTree dominate.")
	elif dom in ["buffer_pack", "vertex_index_build"]:
		lines.append("**Chosen optimization:** Cache serializable mesh plan + buffer payload CPU data (not GPU).")
		lines.append("Rationale: buffer/vertex packing dominates after plan; caching plan+CPU buffers skips both plan and pack.")
	else:
		lines.append("**Chosen optimization:** Investigate `%s`; default to Mesh Plan Cache only if plan is near-dominant." % dom)
	lines.append("")
	return "\n".join(lines)
