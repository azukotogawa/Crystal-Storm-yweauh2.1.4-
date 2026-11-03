extends SceneTree
## Read-only timing probe (test/cs-gen-profile-20261103). Calls existing gen/bake functions with timers; no behaviour changes.
const _WorldState = preload("res://world/world_state.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkPipeline = preload("res://chunks/chunk_pipeline.gd")
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")
const _WorldBakeService = preload("res://world/world_bake_service.gd")
const _Job = preload("res://world/world_bake_worker_job.gd")
const _Buf = preload("res://chunks/chunk_mesh_buffer_builder.gd")
const _Prop = preload("res://world/prop_scatter.gd")
const _Poi = preload("res://world/poi_scatter.gd")
const _Veg = preload("res://world/vegetation_manager.gd")
const _Near = preload("res://world/near_props.gd")
var SEED := 77123
var N := 30
var out_lines: PackedStringArray = PackedStringArray()
var world
var mgr
var bake
var par_res: Array = []

func _init() -> void:
	call_deferred("_run")

func P(s: String) -> void:
	print("GP " + s)
	out_lines.append(s)
	var f := FileAccess.open("user://gprof_out.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out_lines))
		f.close()

func us() -> int:
	return Time.get_ticks_usec()

func _coords(row: int) -> Array:
	var a: Array = []
	for i in N:
		a.append(Vector2i(i - 15, row))
	return a

func _avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for v in a:
		t += float(v)
	return t / float(a.size())

func _med(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2])

func _rep(name: String, a: Array) -> void:
	P("%s n=%d avg_ms=%.2f med_ms=%.2f" % [name, a.size(), _avg(a) / 1000.0, _med(a) / 1000.0])

func _run() -> void:
	var se := OS.get_environment("CS_SEED")
	if not se.is_empty():
		SEED = se.to_int()
	P("start seed=%d threads=%d godot=%s" % [SEED, OS.get_processor_count(), Engine.get_version_info().string])
	_WorldState.replace_active()
	_WorldBakeService.clear_active()
	world = _InfiniteNoiseWorld.new(SEED)
	mgr = _ChunkManager.new()
	mgr.prebuild_chunk_buffers = true
	mgr.terrain_surface_mesh = true
	root.add_child(mgr)
	if "world" in mgr:
		mgr.world = world
	bake = _WorldBakeService.new()
	bake.package_dir = "user://gprof_pkg"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://gprof_pkg/chunks"))
	await process_frame

	# Micro-benchmarks: interpreter vs native noise call cost.
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_PERLIN
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz.fractal_octaves = 4
	var t0 := us()
	var acc := 0.0
	for i in 100000:
		acc += nz.get_noise_2d(float(i) * 0.37, float(i) * 0.11)
	var noise_us := us() - t0
	t0 = us()
	for i in 100000:
		acc += float(i) * 0.37 + sin(float(i))
	var loop_us := us() - t0
	t0 = us()
	var d := {}
	for i in 100000:
		d[Vector2i(i & 255, i >> 8)] = {"a": i, "b": 1.0}
	var dict_us := us() - t0
	P("micro noise4oct_ns=%.0f gd_loop_ns=%.0f dict_alloc_insert_ns=%.0f acc=%.1f" % [noise_us * 10.0, loop_us * 10.0, dict_us * 10.0, acc])

	# Phase 1: real streaming pipeline (bake off), single thread.
	var s_col: Array = []; var s_mesh: Array = []; var s_buf: Array = []; var s_tot: Array = []; var s_q: Array = []
	for c in _coords(0):
		var data = _ChunkData.new(c, world)
		data.capture_worker_snapshot()
		var ta := us()
		var job: Dictionary = _ChunkPipeline.run_worker_job(mgr, data, true, [], Rect2i(0, 0, _ChunkData.SIZE, _ChunkData.SIZE), [], {}, true, true)
		s_tot.append(us() - ta)
		s_col.append(int(job.get("column_us", 0)))
		s_mesh.append(int(job.get("build_mesh_us", 0)))
		s_buf.append(int(job.get("buffer_us", 0)))
		s_q.append((job.get("merged_quads", []) as Array).size())
	P("STREAM single-thread (ChunkPipeline.run_worker_job, bake off)")
	_rep("stream.column(height+tile sample)", s_col)
	_rep("stream.mesh_build", s_mesh)
	_rep("stream.buffer_pack", s_buf)
	_rep("stream.worker_total", s_tot)
	P("stream.quads avg=%.0f" % _avg(s_q))

	# Phase 2: per-function sampling cost, 256 columns per chunk.
	var f_h: Array = []; var f_raw: Array = []; var f_riv: Array = []; var f_bio: Array = []; var f_tile: Array = []; var f_prop: Array = []
	for c in _coords(3):
		var bx: int = c.x * 16; var bz: int = c.y * 16
		t0 = us()
		for lz in 16:
			for lx in 16:
				world._compute_raw_elevation(float(bx + lx), float(bz + lz))
		f_raw.append(us() - t0)
		t0 = us()
		for lz in 16:
			for lx in 16:
				world.get_river_mask(float(bx + lx), float(bz + lz))
		f_riv.append(us() - t0)
		t0 = us()
		for lz in 16:
			for lx in 16:
				world._get_biome_compute(float(bx + lx), 0.0, float(bz + lz))
		f_bio.append(us() - t0)
		t0 = us()
		for lz in 16:
			for lx in 16:
				world.get_surface_height_worker(float(bx + lx), float(bz + lz), 0.0)
		f_h.append(us() - t0)
		t0 = us()
		for lz in 16:
			for lx in 16:
				world.get_tile_type_worker(float(bx + lx), float(bz + lz), -1, -1)
		f_tile.append(us() - t0)
		t0 = us()
		_Prop.for_chunk(SEED, c.x, c.y, 8, world)
		f_prop.append(us() - t0)
	P("FUNCS per chunk (256 columns)")
	_rep("fn.raw_elevation_noise_only", f_raw)
	_rep("fn.river_mask", f_riv)
	_rep("fn.biome_compute", f_bio)
	_rep("fn.surface_height_worker(full)", f_h)
	_rep("fn.tile_type_worker(full)", f_tile)
	_rep("fn.prop_scatter.for_chunk", f_prop)

	# Phase 3: bake worker job (sample / mesh build+plan dup / write), single thread.
	var b_s: Array = []; var b_m: Array = []; var b_w: Array = []; var b_t: Array = []; var b_bytes: Array = []
	for c in _coords(6):
		var one: Dictionary = _Job.execute(c, world, mgr, [], bake)
		b_s.append(int(one.get("sample_us", 0))); b_m.append(int(one.get("mesh_us", 0)))
		b_w.append(int(one.get("write_us", 0))); b_t.append(int(one.get("total_us", 0))); b_bytes.append(int(one.get("bytes", 0)))
	P("BAKE single-thread (WorldBakeWorkerJob.execute)")
	_rep("bake.sample", b_s)
	_rep("bake.mesh_build+plan_dup", b_m)
	_rep("bake.write(encode+file)", b_w)
	_rep("bake.total", b_t)
	P("bake.bytes avg=%.0f" % _avg(b_bytes))

	# Phase 4: mesh sub-stages + buffer + near_props on baked-base data.
	var m_g: Array = []; var m_full: Array = []; var m_buf: Array = []; var m_np: Array = []; var m_ramp: Array = []
	var near = _Near.new()
	near.manager = mgr
	for c in _coords(9):
		var surface := PackedFloat32Array(); var tiles := PackedInt32Array()
		surface.resize(256); tiles.resize(256)
		var i := 0
		for lz in 16:
			for lx in 16:
				surface[i] = float(world.get_surface_height_worker(float(c.x * 16 + lx), float(c.y * 16 + lz), 0.0))
				tiles[i] = int(world.get_tile_type_worker(float(c.x * 16 + lx), float(c.y * 16 + lz), -1, -1))
				i += 1
		var data = _ChunkData.new(c, world)
		data.capture_base_only_snapshot()
		bake._apply_pack_to_data(data, surface, tiles)
		if data.has_method("_bind_macro_surface_if_needed"):
			data._bind_macro_surface_if_needed()
		var q: Array = []
		var cc := {}
		t0 = us(); mgr._emit_ramps(data, q, cc); m_ramp.append(us() - t0)
		q = []
		t0 = us()
		mgr._greedy_mesh_plane_region(data, Vector3i(0, 1, 0), 0, q, 0, 0, 16, 16)
		m_g.append(us() - t0)
		t0 = us(); var built: Dictionary = mgr._build_mesh(data); m_full.append(us() - t0)
		var quads: Array = built.get("quads", [])
		t0 = us(); _Buf.build_mesh_payload(data, quads, true, {}, false, [], quads); m_buf.append(us() - t0)
		t0 = us(); var nn = near._build(data); m_np.append(us() - t0)
		if nn is Node:
			nn.free()
	P("MESH sub-stages")
	_rep("mesh.emit_ramps", m_ramp)
	_rep("mesh.greedy_top_face_only", m_g)
	_rep("mesh.build_mesh_full", m_full)
	_rep("mesh.buffer_pack(vertex/index)", m_buf)
	_rep("near_props._build", m_np)
	near.free()

	# Phase 5: whole-world passes run once per bake.
	t0 = us()
	var pois = _Poi.scatter(SEED)
	P("POI scatter whole region ms=%.1f n=%d" % [(us() - t0) / 1000.0, pois.size()])
	t0 = us()
	var vm: Dictionary = _Veg.bake_scatter_map(world, 12000, {}, {})
	P("VEG bake_scatter_map 12000 attempts ms=%.1f entries=%d" % [(us() - t0) / 1000.0, vm.size()])

	# Phase 6: parallel scaling with WorkerThreadPool.
	for mode in ["bake", "stream"]:
		var cs: Array = _coords(12 if mode == "bake" else 15)
		par_res.resize(cs.size())
		par_res.fill(0)
		var tw := us()
		var gid: int = WorkerThreadPool.add_group_task(Callable(self, "_par_" + mode).bind(cs), cs.size(), -1, true)
		WorkerThreadPool.wait_for_group_task_completion(gid)
		var wall := us() - tw
		var sum := 0
		for v in par_res:
			sum += int(v)
		P("PAR %s chunks=%d wall_ms=%.0f per_chunk_avg_ms=%.0f throughput_ms_per_chunk=%.1f effective_parallelism=%.2f" % [mode, cs.size(), wall / 1000.0, sum / 1000.0 / cs.size(), wall / 1000.0 / cs.size(), float(sum) / float(maxi(wall, 1))])
	P("DONE")
	quit(0)

func _par_bake(idx: int, cs: Array) -> void:
	var one: Dictionary = _Job.execute(cs[idx], world, mgr, [], bake)
	par_res[idx] = int(one.get("total_us", 0))

func _par_stream(idx: int, cs: Array) -> void:
	var data = _ChunkData.new(cs[idx], world)
	data.capture_worker_snapshot()
	var ta := Time.get_ticks_usec()
	_ChunkPipeline.run_worker_job(mgr, data, true, [], Rect2i(0, 0, 16, 16), [], {}, true, true)
	par_res[idx] = Time.get_ticks_usec() - ta