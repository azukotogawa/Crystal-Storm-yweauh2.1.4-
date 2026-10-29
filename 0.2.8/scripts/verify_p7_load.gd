extends SceneTree

var _gaps: Array = []
var _t0 := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_t0 = Time.get_ticks_usec()
	var last := _t0
	var packed: PackedScene
	if OS.get_environment("P7_THREADED") == "1":
		ResourceLoader.load_threaded_request("res://scenes/main.tscn", "PackedScene", true)
		while ResourceLoader.load_threaded_get_status("res://scenes/main.tscn") == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await process_frame
			var nw := Time.get_ticks_usec()
			_gaps.append([float(nw - last) / 1e6, float(last - _t0) / 1e6, "prefetch", 0])
			last = nw
		packed = ResourceLoader.load_threaded_get("res://scenes/main.tscn") as PackedScene
	else:
		packed = load("res://scenes/main.tscn") as PackedScene
	var t_load := Time.get_ticks_usec()
	var game: Node = packed.instantiate()
	var t_inst := Time.get_ticks_usec()
	root.add_child(game)
	var t_add := Time.get_ticks_usec()
	print("P7_LOADSPLIT load=%.3f inst=%.3f ready_sync=%.3f" % [float(t_load - _t0) / 1e6, float(t_inst - t_load) / 1e6, float(t_add - t_inst) / 1e6])
	var ready_at := -1.0
	var frames := 0
	var after_ready := 0
	var player = null
	while frames < 6000:
		await process_frame
		frames += 1
		var now := Time.get_ticks_usec()
		var gap := float(now - last) / 1000000.0
		var phase := "ready" if ready_at >= 0.0 else "loading"
		_gaps.append([gap, float(last - _t0) / 1000000.0, phase, frames])
		last = now
		if player == null:
			player = get_first_node_in_group("player")
		if ready_at < 0.0 and player and bool(player.get("world_ready")):
			ready_at = float(now - _t0) / 1000000.0
		if ready_at >= 0.0:
			after_ready += 1
			if after_ready >= 600:
				break
	_gaps.sort_custom(func(a, b): return a[0] > b[0])
	var top := []
	for i in mini(6, _gaps.size()):
		top.append("%.3fs@%.2fs/%s/f%d" % [_gaps[i][0], _gaps[i][1], _gaps[i][2], _gaps[i][3]])
	var max_ready := 0.0
	for g in _gaps:
		if g[2] == "ready":
			max_ready = maxf(max_ready, g[0])
	var world = get_first_node_in_group("world")
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for z in range(-96, 96, 3):
		for x in range(-96, 96, 3):
			ctx.update(PackedFloat32Array([world.get_surface_height_uncached(float(x), float(z)), float(world.get_tile_type_uncached(float(x), float(z)))]).to_byte_array())
	var h := ctx.finish().hex_encode().substr(0, 16)
	var bake = load("res://world/world_bake_service.gd").get_active()
	if bake:
		print("P7_LOADBAKE veg_ms=%s veg_entries=%s prime=%s" % [str(bake.last_vegetation_bake_ms), str(bake.last_vegetation_entries), str(bake._prime_count)])
	print("P7_LOAD tag=%s seed=%d ready_at=%.2fs frames=%d max_gap=%.3fs max_gap_after_ready=%.3fs top=%s world_hash=%s" % [
		OS.get_environment("P7_TAG"), int(world.world_seed), ready_at, frames, _gaps[0][0], max_ready, str(top), h])
	quit(0)