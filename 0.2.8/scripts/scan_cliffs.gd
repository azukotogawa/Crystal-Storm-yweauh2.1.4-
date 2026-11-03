extends SceneTree
## Scan for chunks with tall side walls (cliffs) to pick identity-check coverage.
const _WorldState = preload("res://world/world_state.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkPipeline = preload("res://chunks/chunk_pipeline.gd")
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")
const _WorldBakeService = preload("res://world/world_bake_service.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for seed in [77123, 4242, 9001]:
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
		for gz in range(-7, 8):
			for gx in range(-7, 8):
				var c := Vector2i(gx * 8, gz * 8)
				var data = _ChunkData.new(c, world)
				data.capture_worker_snapshot()
				var job: Dictionary = _ChunkPipeline.run_worker_job(mgr, data, true, [], Rect2i(0, 0, 16, 16), [], {}, true, true)
				var quads: Array = job.get("merged_quads", [])
				var ns := 0; var my := 0.0; var sy := 0.0; var keys := {}
				for q in quads:
					var fc := int(q.get("face_code", 0))
					if fc >= 3 and fc <= 6 and not q.has("wave_riser"):
						ns += 1
						var d := float(q.get("dim_y", 0.0))
						my = maxf(my, d); sy += d
					for k in q.keys():
						keys[k] = true
				print("CL seed=%d c=%d,%d n=%d side=%d max_dy=%.2f sum_dy=%.1f keys=%s" % [seed, c.x, c.y, quads.size(), ns, my, sy, ",".join(PackedStringArray(keys.keys()))])
		mgr.queue_free()
		await process_frame
	print("CL DONE")
	quit(0)