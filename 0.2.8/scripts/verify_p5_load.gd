extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const SLOT := 7


func _init() -> void:
	call_deferred("_run")


func _boot(packed: PackedScene) -> Dictionary:
	var game: Node = packed.instantiate()
	root.add_child(game)
	var d := {"game": game}
	for _i in 1800:
		var p = get_first_node_in_group("player")
		var cm = get_first_node_in_group("chunk_manager")
		var sv = get_first_node_in_group("save_game_service")
		var w = get_first_node_in_group("world")
		if p and cm and sv and w and bool(p.get("world_ready")):
			d.player = p
			d.cm = cm
			d.save = sv
			d.world = w
			return d
		await process_frame
	return d


func _ring(cm, pc: Vector2i) -> int:
	var n := 0
	if false:
		print("dbg pc=%s chunks=%d paused=%s key=%s sample=%s" % [pc, cm.chunks.size(), cm.stream_paused, cm._last_chunk_key, cm.chunks.keys().slice(0, 3)])
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if cm.is_chunk_loaded(pc + Vector2i(dx, dz)):
				n += 1
	return n


func _run() -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	var a: Dictionary = await _boot(packed)
	if not a.has("player"):
		push_error("FAIL boot")
		quit(1)
		return
	a.save.config.auto_save_enabled = false
	var p = a.player
	var bd: Dictionary = load("res://world/world_bake_service.gd").full_world_chunk_bounds()
	print("bounds %s" % bd)
	var sc: Vector2i = a.cm.get_player_chunk_coord()
	var tc := Vector2i(clampi(sc.x + 4, int(bd.min_cx) + 1, int(bd.max_cx) - 1), clampi(sc.y + 4, int(bd.min_cz) + 1, int(bd.max_cz) - 1))
	if absi(tc.x - sc.x) < 3:
		tc.x = clampi(sc.x - 4, int(bd.min_cx) + 1, int(bd.max_cx) - 1)
	if absi(tc.y - sc.y) < 3:
		tc.y = clampi(sc.y - 4, int(bd.min_cz) + 1, int(bd.max_cz) - 1)
	var far := Vector2(tc.x * 16 + 8.5, tc.y * 16 + 8.5)
	var h: float = a.world.get_surface_height(far.x, far.y)
	p.voxel_position = Vector3(far.x, h + 1.0, far.y)
	p._sync_global_from_voxel()
	for _i in 600:
		await process_frame
		if _ring(a.cm, a.cm.get_player_chunk_coord()) == 9:
			break
	var saved: Vector3 = p.voxel_position
	print("saved pos %s chunk %s ring %d" % [saved, a.cm.get_player_chunk_coord(), _ring(a.cm, a.cm.get_player_chunk_coord())])
	if a.save.save_slot(SLOT) != OK:
		push_error("FAIL save")
		quit(1)
		return
	a.cm.shutdown_workers()
	a.game.queue_free()
	for _i in 30:
		await process_frame
	var b: Dictionary = await _boot(packed)
	b.save.config.auto_save_enabled = false
	var ok: bool = await b.save.load_slot(SLOT)
	var t0 := Time.get_ticks_msec()
	var ring := 0
	var pc: Vector2i = b.cm.get_player_chunk_coord()
	for _i in 600:
		await process_frame
		pc = b.cm.get_player_chunk_coord()
		ring = _ring(b.cm, pc)
		if ring == 9:
			break
	var lp: Vector3 = b.player.voxel_position
	print("LOAD ok=%s pos=%s dist=%.2f chunk=%s ring=%d/9 world_ready=%s ms=%d" % [ok, lp, Vector2(lp.x - saved.x, lp.z - saved.z).length(), pc, ring, b.player.get("world_ready"), Time.get_ticks_msec() - t0])
	var pass_ok: bool = ok and ring == 9 and bool(b.player.get("world_ready"))
	print("P5 LOAD " + ("OK" if pass_ok else "FAIL"))
	b.cm.shutdown_workers()
	quit(0 if pass_ok else 1)
