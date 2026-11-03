extends SceneTree
## Mesh output fingerprint (test/cs-packed-mesh-20261103).
## Prints one "GH" line per chunk: seed, coord, sha256 of merged quads and of every
## packed/array payload field (vertex/index/normal/colour/uv buffers). Run on the old and
## new code and diff the lines; scripts/reference/mesh_hashes_20261103.txt holds the baseline
## the Stage 3 native mesher must reproduce.
const _WorldState = preload("res://world/world_state.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkPipeline = preload("res://chunks/chunk_pipeline.gd")
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")
const _WorldBakeService = preload("res://world/world_bake_service.gd")
const SEEDS := [77123, 4242, 9001]
const ROWS := [0, 7, -11]
const PER_ROW := 12
## Cliff-heavy chunks found by scripts/scan_cliffs.gd (most side faces / largest drops).
## Printed as GC lines; baseline in scripts/reference/mesh_hashes_cliffs_20261103.txt.
const CLIFFS := {
	77123: [Vector2i(16, 0), Vector2i(48, 40), Vector2i(48, 0), Vector2i(-56, 24), Vector2i(16, 56)],
	4242: [Vector2i(48, -32), Vector2i(24, -40), Vector2i(-8, 32), Vector2i(48, 24)],
	9001: [Vector2i(24, -24), Vector2i(40, 56)],
}

func _init() -> void:
	call_deferred("_run")

func _h(v) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes(v))
	return ctx.finish().hex_encode().substr(0, 16)

func _run() -> void:
	print("GH start godot=%s debug=%s" % [Engine.get_version_info().string, OS.is_debug_build()])
	var total := 0
	var feat := {"ramp": 0, "water": 0, "riser": 0, "cliff": 0}
	var t_all := 0
	for seed in SEEDS:
		_WorldState.replace_active()
		_WorldBakeService.clear_active()
		var world = _InfiniteNoiseWorld.new(seed)
		var mgr = _ChunkManager.new()
		mgr.prebuild_chunk_buffers = true
		mgr.terrain_surface_mesh = true
		root.add_child(mgr)
		if "world" in mgr:
			mgr.world = world
		await process_frame
		if seed == SEEDS[0]:
			print("GH native_mesher=%s" % str(mgr.native_mesher_active() if mgr.has_method("native_mesher_active") else false))
		var coords: Array = []
		for row in ROWS:
			for i in PER_ROW:
				coords.append([Vector2i(i * 3 - 18, row * 2), "GH"])
		for cc in CLIFFS.get(seed, []):
			coords.append([cc, "GC"])
		for item in coords:
			if true:
				var c: Vector2i = item[0]
				var data = _ChunkData.new(c, world)
				data.capture_worker_snapshot()
				var ta := Time.get_ticks_usec()
				var job: Dictionary = _ChunkPipeline.run_worker_job(mgr, data, true, [], Rect2i(0, 0, 16, 16), [], {}, true, true)
				t_all += Time.get_ticks_usec() - ta
				var quads: Array = job.get("merged_quads", [])
				var payload: Dictionary = job.get("payload", {})
				var parts := PackedStringArray()
				parts.append("quads=" + _h(quads))
				var keys: Array = payload.keys()
				keys.sort()
				for k in keys:
					var v = payload[k]
					var ks := str(k)
					if ks.ends_with("_us") or ks.ends_with("_ms") or ks.contains("telemetry"):
						continue
					if v is Array or v is Dictionary or typeof(v) >= TYPE_PACKED_BYTE_ARRAY:
						parts.append("%s=%s" % [ks, _h(v)])
				var nr := 0; var nw := 0; var nri := 0; var nc := 0
				for q in quads:
					var fc := int(q.get("face_code", 0))
					if fc >= 7 and fc <= 9:
						nr += 1
					var t := int(q.get("type", 0))
					if t == VoxelTypes.WATER or t == VoxelTypes.RIVER or (t >= 0 and t <= VoxelTypes.OCEAN3):
						nw += 1
					if q.has("wave_riser"):
						nri += 1
					if fc >= 3 and fc <= 6 and float(q.get("dim_y", 0.0)) > 1.5:
						nc += 1
				feat.ramp += nr; feat.water += nw; feat.riser += nri; feat.cliff += nc
				print("%s seed=%d c=%d,%d src=%s n=%d ramp=%d water=%d riser=%d cliff=%d %s" % [item[1], seed, c.x, c.y, str(job.get("mesh_source", "")), quads.size(), nr, nw, nri, nc, " ".join(parts)])
				total += 1
		mgr.queue_free()
		await process_frame
	print("GH summary chunks=%d seeds=%d ramp=%d water=%d riser=%d cliff=%d avg_worker_ms=%.1f" % [total, SEEDS.size(), feat.ramp, feat.water, feat.riser, feat.cliff, t_all / 1000.0 / maxi(total, 1)])
	print("GH native_surface calls_fallbacks=%s" % str(ChunkSurfaceMeshBuilder.native_surface_stats()))
	print("GH DONE")
	quit(0)
