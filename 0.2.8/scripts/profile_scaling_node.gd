extends Node
## Stage-1 scaling probe (autoload form for export-template runs via override.cfg) (test/cs-packed-mesh-20261103). Read-only: times existing stream worker job per stage with W pool tasks.
const _WorldState = preload("res://world/world_state.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkPipeline = preload("res://chunks/chunk_pipeline.gd")
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")
const _WorldBakeService = preload("res://world/world_bake_service.gd")
var SEED := 77123
var N := 24
var world
var mgr
var res: Array = []

func _ready() -> void:
	call_deferred("_run")

func P(s: String) -> void:
	print("GS " + s)

func _run() -> void:
	var se := OS.get_environment("CS_SEED")
	if not se.is_empty():
		SEED = se.to_int()
	var ws := OS.get_environment("CS_WORKERS")
	var counts: Array = [1, 2, 3, 4, 8]
	if not ws.is_empty():
		counts = []
		for p in ws.split(","):
			counts.append(p.to_int())
	P("start seed=%d threads=%d godot=%s debug_build=%s editor=%s" % [SEED, OS.get_processor_count(), Engine.get_version_info().string, OS.is_debug_build(), OS.has_feature("editor")])
	_WorldState.replace_active()
	_WorldBakeService.clear_active()
	world = _InfiniteNoiseWorld.new(SEED)
	mgr = _ChunkManager.new()
	mgr.prebuild_chunk_buffers = true
	mgr.terrain_surface_mesh = true
	get_tree().root.add_child(mgr)
	if "world" in mgr:
		mgr.world = world
	await get_tree().process_frame
	var cs: Array = []
	for i in N:
		cs.append(Vector2i(i - 12, 4))
	# warm-up (not reported)
	res.resize(cs.size())
	for i in 4:
		_job(i, cs)
	for w in counts:
		res.fill(null)
		var t0 := Time.get_ticks_usec()
		var gid: int = WorkerThreadPool.add_group_task(Callable(self, "_job").bind(cs), cs.size(), int(w), true)
		WorkerThreadPool.wait_for_group_task_completion(gid)
		var wall := Time.get_ticks_usec() - t0
		var sc := 0.0; var sm := 0.0; var sb := 0.0; var st := 0.0
		for r in res:
			sc += r[0]; sm += r[1]; sb += r[2]; st += r[3]
		var n := float(cs.size())
		P("W=%d chunks=%d per_chunk_ms column=%.1f mesh=%.1f buffer=%.1f total=%.1f | wall_ms=%.0f throughput_ms_per_chunk=%.1f speedup_vs_serial_sum=%.2f" % [w, cs.size(), sc / n / 1000.0, sm / n / 1000.0, sb / n / 1000.0, st / n / 1000.0, wall / 1000.0, wall / 1000.0 / n, st / float(maxi(wall, 1))])
	P("DONE")
	get_tree().quit(0)

func _job(idx: int, cs: Array) -> void:
	var data = _ChunkData.new(cs[idx], world)
	data.capture_worker_snapshot()
	var ta := Time.get_ticks_usec()
	var job: Dictionary = _ChunkPipeline.run_worker_job(mgr, data, true, [], Rect2i(0, 0, 16, 16), [], {}, true, true)
	var tot := Time.get_ticks_usec() - ta
	res[idx] = [float(job.get("column_us", 0)), float(job.get("build_mesh_us", 0)), float(job.get("buffer_us", 0)), float(tot)]
