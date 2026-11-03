extends SceneTree


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_WORLD_BAKE", "1")
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 12349
	var svc_script = load("res://world/world_bake_service.gd")
	var bake = svc_script.new()
	svc_script.set_active(bake)
	var host = load("res://chunks/chunk_manager.gd").new()
	host.world = world
	var t0 := Time.get_ticks_msec()
	var boot: Dictionary = bake.bootstrap_for_world(world, false, host)
	print("AREA boot mode=%s ok=%s ms=%d valid=%s dir=%s" % [str(boot.get("mode")), str(boot.get("ok")), Time.get_ticks_msec() - t0, str(bake.valid), bake.package_dir])
	if not bool(bake.valid):
		bake.world_seed = 12349
		bake.full_world = true
		bake.streamed = true
		bake.package_dir = bake.bake_dir_for(12349, -1, true)
		print("AREA dir forced ", bake.package_dir)
	var r := int(OS.get_environment("AREA_R")) if OS.get_environment("AREA_R") != "" else 8
	var spots := [Vector2i(504, -744), Vector2i(540, -700), Vector2i(470, -790)]
	var want: Dictionary = {}
	for s in spots:
		var c: Vector2i = svc_script.world_to_chunk_coord(s.x, s.y)
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				want[c + Vector2i(dx, dz)] = true
	var t1 := Time.get_ticks_msec()
	var ok := 0
	var qn := 0
	for k in want.keys():
		var one: Dictionary = bake._bake_one_chunk(k, world, host, [])
		if bool(one.get("ok", false)):
			ok += 1
			qn += int(one.get("plan_qn", 0))
	var ms := Time.get_ticks_msec() - t1
	if bake.has_method("_write_plan_seed_meta"):
		bake._write_plan_seed_meta()
	if bake.has_method("save_bake"):
		bake.save_bake()
	print("AREA baked chunks=%d of %d plan_qn=%d bake_ms=%d r=%d" % [ok, want.size(), qn, ms, r])
	host.free()
	svc_script.clear_active()
	for _i in 3:
		await process_frame
	quit(0)
