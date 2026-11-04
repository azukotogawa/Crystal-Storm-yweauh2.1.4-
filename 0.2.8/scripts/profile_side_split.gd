extends Node
## Side-wall pass split: call counts and inclusive time of its helpers (subclass overrides). Read-only probe.
const _WorldState = preload("res://world/world_state.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")
const _WorldBakeService = preload("res://world/world_bake_service.gd")

class CM extends ChunkManager:
	var cnt := {}
	var us := {}
	var keys := {}
	func _b(k: String, t: int) -> void:
		cnt[k] = int(cnt.get(k, 0)) + 1
		us[k] = int(us.get(k, 0)) + Time.get_ticks_usec() - t
	func _side_wall_spec(data: ChunkData, x: int, z: int, nx: int, nz: int, toward_high: Vector2i) -> Dictionary:
		var t := Time.get_ticks_usec(); var r := super(data, x, z, nx, nz, toward_high); _b("side_wall_spec", t); return r
	func _emit_side_strips(data: ChunkData, out_quads: Array, x: int, z: int, nx: int, nz: int, face_code: int, tile: int) -> void:
		var t := Time.get_ticks_usec(); super(data, out_quads, x, z, nx, nz, face_code, tile); _b("emit_side_strips", t)
	func _emit_wave_lip(data: ChunkData, out_quads: Array, x: int, z: int, nx: int, nz: int, face_code: int) -> void:
		var t := Time.get_ticks_usec(); super(data, out_quads, x, z, nx, nz, face_code); _b("emit_wave_lip", t)
	func _column_micro_top(data: ChunkData, col_x: int, col_z: int, mx: int, mz: int) -> float:
		keys[Vector4i(col_x, col_z, TerrainLook.wave_rep_micro(mx), TerrainLook.wave_rep_micro(mz))] = true
		var t := Time.get_ticks_usec(); var r := super(data, col_x, col_z, mx, mz); _b("column_micro_top", t); return r
	func _halo_landing_dir(data: ChunkData, nx: int, nz: int, n_h: float) -> Vector2i:
		var t := Time.get_ticks_usec(); var r := super(data, nx, nz, n_h); _b("halo_landing_dir", t); return r

func _ready() -> void:
	call_deferred("_run")

func P(s: String) -> void:
	print("GS " + s)

func _run() -> void:
	_WorldState.replace_active()
	_WorldBakeService.clear_active()
	var world = _InfiniteNoiseWorld.new(77123)
	var mgr := CM.new()
	mgr.prebuild_chunk_buffers = true
	mgr.terrain_surface_mesh = true
	get_tree().root.add_child(mgr)
	mgr.world = world
	await get_tree().process_frame
	var S: int = _ChunkData.SIZE
	var tot := {}
	var side_us := 0
	var nchunks := 0
	var off_us := 0
	var rim_us := 0
	var micro_calls := 0
	var uniq := 0
	for i in 28:
		var c := Vector2i(i - 16, 4)
		var data = _ChunkData.new(c, world)
		data.capture_worker_snapshot()
		data._compute_column_maps(true)
		data._bind_macro_surface_if_needed()
		data._mesh_job_micro_skip = {}
		var out: Array = []
		mgr._emit_ramps(data, out, {})
		mgr._emit_waved_tops(data, out, 0, 0, S, S)
		mgr.cnt.clear(); mgr.us.clear(); mgr.keys.clear()
		var t := Time.get_ticks_usec()
		for d in [Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1)]:
			mgr._emit_surface_side_walls_region(data, d, 1, out, 0, 0, S, S)
		var st := Time.get_ticks_usec() - t
		# isolated cost of the two leaf calls in _column_micro_top
		var t2 := Time.get_ticks_usec()
		for x in S:
			for z in S:
				TerrainLook.offset_steps(float(c.x * S + x) + 0.1875, float(c.y * S + z) + 0.8125)
		var o := Time.get_ticks_usec() - t2
		t2 = Time.get_ticks_usec()
		for x in S:
			for z in S:
				data.rim_plane_steps(c.x * S + x, c.y * S + z, 1, 6, 10.0)
		var r := Time.get_ticks_usec() - t2
		if i < 4:
			continue
		nchunks += 1
		side_us += st
		off_us += o
		rim_us += r
		micro_calls += int(mgr.cnt.get("column_micro_top", 0))
		uniq += mgr.keys.size()
		for k in mgr.cnt:
			if not tot.has(k):
				tot[k] = [0, 0]
			tot[k][0] += mgr.cnt[k]
			tot[k][1] += mgr.us[k]
	P("SIDE chunks=%d side4_total_ms_per_chunk=%.2f" % [nchunks, side_us / 1000.0 / nchunks])
	for k in tot:
		P("SIDE fn=%s calls_per_chunk=%.0f incl_ms_per_chunk=%.2f us_per_call=%.2f" % [k, tot[k][0] / float(nchunks), tot[k][1] / 1000.0 / nchunks, tot[k][1] / float(maxi(tot[k][0], 1))])
	P("SIDE column_micro_top calls_per_chunk=%.0f unique_keys_per_chunk=%.0f redundancy=%.2fx" % [micro_calls / float(nchunks), uniq / float(nchunks), micro_calls / float(maxi(uniq, 1))])
	P("SIDE iso offset_steps us_per_call=%.2f rim_plane_steps us_per_call=%.2f" % [off_us / float(nchunks * 256), rim_us / float(nchunks * 256)])
	P("DONE")
	get_tree().quit(0)