extends Node
## Per-stage split of one chunk's worker path (single thread, release). Read-only probe.
const _WorldState = preload("res://world/world_state.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkPipeline = preload("res://chunks/chunk_pipeline.gd")
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")
const _WorldBakeService = preload("res://world/world_bake_service.gd")
var SEED := 77123
var world
var mgr
var acc := {}
var order: Array = []

func _ready() -> void:
	call_deferred("_run")

func P(s: String) -> void:
	print("GS " + s)

func rec(k: String, us: int) -> void:
	if not acc.has(k):
		acc[k] = []
		order.append(k)
	acc[k].append(us)

func _run() -> void:
	var se := OS.get_environment("CS_SEED")
	if not se.is_empty():
		SEED = se.to_int()
	P("start seed=%d debug_build=%s native_env=%s prep_env=%s" % [SEED, OS.is_debug_build(), OS.get_environment("CS_NATIVE_MESH"), OS.get_environment("CS_NATIVE_PREP")])
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
	for i in 24:
		cs.append(Vector2i(i - 12, 4))
	for i in 4:
		_split(cs[i])
		_whole(cs[i])
	acc.clear(); order.clear()
	for c in cs:
		_whole(c)
		_split(c)
	for k in order:
		var a: Array = acc[k]
		a.sort()
		var n := a.size()
		var s := 0
		for v in a: s += v
		P("ST %s med_us=%d mean_us=%d p25=%d p75=%d n=%d" % [k, a[n / 2], s / n, a[n / 4], a[(3 * n) / 4], n])
	P("DONE")
	get_tree().quit(0)

func _whole(c: Vector2i) -> void:
	var data = _ChunkData.new(c, world)
	var t := Time.get_ticks_usec()
	data.capture_worker_snapshot()
	rec("whole.snapshot", Time.get_ticks_usec() - t)
	t = Time.get_ticks_usec()
	var job: Dictionary = _ChunkPipeline.run_worker_job(mgr, data, true, [], Rect2i(0, 0, 16, 16), [], {}, true, true)
	rec("whole.worker_job", Time.get_ticks_usec() - t)
	rec("whole.column", int(job.get("column_us", 0)))
	rec("whole.mesh", int(job.get("build_mesh_us", 0)))
	rec("whole.buffer", int(job.get("buffer_us", 0)))
	var pl: Dictionary = job.get("payload", {})
	rec("whole.quads", int(pl.get("count", 0)))

func _split(c: Vector2i) -> void:
	var S: int = _ChunkData.SIZE
	var data = _ChunkData.new(c, world)
	var t := Time.get_ticks_usec()
	data.capture_worker_snapshot()
	rec("a0.snapshot", Time.get_ticks_usec() - t)
	t = Time.get_ticks_usec()
	data._compute_column_maps(true)
	rec("a1.column_maps", Time.get_ticks_usec() - t)
	t = Time.get_ticks_usec()
	data.derive_micro_from_terrain_edits()
	rec("a2.derive_micro", Time.get_ticks_usec() - t)
	t = Time.get_ticks_usec()
	if data.has_method("_bind_macro_surface_if_needed"):
		data._bind_macro_surface_if_needed()
	rec("a3.bind_macro_surface", Time.get_ticks_usec() - t)
	# isolated re-runs of the two per-column world calls (duplicate work, for attribution)
	var w = data.world
	t = Time.get_ticks_usec()
	for x in S:
		for z in S:
			w.get_surface_height_worker(float(c.x * S + x), float(c.y * S + z), float(data._worker_height_delta[x][z]))
	rec("x1.iso_surface_height_x256", Time.get_ticks_usec() - t)
	t = Time.get_ticks_usec()
	for x in S:
		for z in S:
			w.get_tile_type_worker(float(c.x * S + x), float(c.y * S + z), int(data._worker_build_tile[x][z]), data.mesh_feature_tile(x, z))
	rec("x2.iso_tile_type_x256", Time.get_ticks_usec() - t)
	# mesh stage, same order as _build_macro_mesh_region(full_chunk)
	var out: Array = []
	t = Time.get_ticks_usec()
	if not data._maps_resident:
		data.ensure_column_maps()
	data._mesh_job_micro_skip = {}
	rec("b0.ensure_maps", Time.get_ticks_usec() - t)
	var cc := {}
	t = Time.get_ticks_usec(); mgr._emit_ramps(data, out, cc); rec("b1.emit_ramps", Time.get_ticks_usec() - t)
	t = Time.get_ticks_usec(); mgr._emit_dug_strata_region(data, out, 0, 0, S, S); rec("b2.dug_strata", Time.get_ticks_usec() - t)
	t = Time.get_ticks_usec(); mgr._emit_build_strata_region(data, out, 0, 0, S, S); rec("b3.build_strata", Time.get_ticks_usec() - t)
	var names := ["b4.greedy_top", "b5.greedy_negx", "b6.greedy_posx", "b7.greedy_negz", "b8.greedy_posz"]
	var dirs := [Vector3i(0, 1, 0), Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1)]
	var fcs := [mgr.FACE_TOP, mgr.FACE_NEG_X, mgr.FACE_POS_X, mgr.FACE_NEG_Z, mgr.FACE_POS_Z]
	for i in 5:
		t = Time.get_ticks_usec()
		mgr._greedy_mesh_plane_region(data, dirs[i], fcs[i], out, 0, 0, S, S)
		rec(names[i], Time.get_ticks_usec() - t)
	t = Time.get_ticks_usec(); mgr._emit_water_lids_region(data, out, 0, 0, S, S); rec("b9.water_lids", Time.get_ticks_usec() - t)
	t = Time.get_ticks_usec()
	if mgr.MESH_CAVES:
		mgr._emit_cave_faces(data, out)
	rec("bA.caves", Time.get_ticks_usec() - t)
	t = Time.get_ticks_usec(); mgr.sync_ramp_map_to_mesh(data, out); rec("bB.sync_ramp_map", Time.get_ticks_usec() - t)
	# isolated waved-tops native (part of greedy_top), duplicate work
	if mgr._native_mesher != null:
		var tmp: Array = []
		t = Time.get_ticks_usec(); mgr._emit_waved_tops_native(data, tmp, 0, 0, S, S); rec("y1.iso_waved_tops_native_total", Time.get_ticks_usec() - t)
	# buffer stage
	t = Time.get_ticks_usec()
	var buf: Dictionary = _ChunkPipeline.run_buffer_stage(data, out, out, [], true, true, true, {})
	rec("c0.buffer_stage", Time.get_ticks_usec() - t)
	rec("c1.payload_duplicate", int(buf.get("duplicate_us", 0)))
	# isolated native surface split
	var tq: Array = []
	for q in ChunkSurfaceMeshBuilder.wave_far_quads(data, out):
		var fc := int(q.get("face_code", 0))
		if fc != 7 and fc != 8 and fc != 9:
			tq.append(q)
	t = Time.get_ticks_usec()
	var arrs: Dictionary = ChunkSurfaceMeshBuilder.build_surface_arrays_native(data, tq)
	rec("z1.iso_surface_arrays_native", Time.get_ticks_usec() - t)
	# main thread: ArrayMesh creation
	if not arrs.is_empty():
		t = Time.get_ticks_usec()
		var m: ArrayMesh = ChunkSurfaceMeshBuilder.build_array_mesh(arrs)
		rec("d1.main_array_mesh", Time.get_ticks_usec() - t)
		t = Time.get_ticks_usec()
		var mi := MeshInstance3D.new()
		mi.mesh = m
		add_child(mi)
		rec("d2.main_add_to_scene", Time.get_ticks_usec() - t)
		mi.queue_free()
	rec("q.quads", out.size())