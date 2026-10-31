extends SceneTree

var _out := ""
var _log := PackedStringArray()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_out = OS.get_environment("CRYSTALSTORM_SCRATCH")
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while frames < 5400:
		if compose != null and int(compose.stage) >= compose.Stage.INITIAL_STREAM_READY:
			break
		await process_frame
		frames += 1
	_note("BOOT frames=%d" % frames)
	for _i in 60:
		await process_frame
	var cm = get_first_node_in_group("chunk_manager")
	var world = get_first_node_in_group("world")
	var player = get_first_node_in_group("player")
	_hide_canvas(root)
	if player:
		player.visible = false
	var cam := Camera3D.new()
	cam.far = 3000.0
	root.add_child(cam)
	cam.current = true
	var spots := _load_spots()
	if spots.is_empty() and player:
		spots["spawn"] = Vector2(player.global_position.x, player.global_position.z)
	for spot_name in spots.keys():
		var w: Vector2 = spots[spot_name]
		var ready := await _teleport_and_wait(cm, world, player, w)
		var y := _surface(world, w)
		var t := Vector3(w.x, y, w.y)
		_note("SPOT %s %.1f %.1f %.1f ready=%s chunks=%d" % [spot_name, t.x, t.y, t.z, str(ready), cm.chunks.size() if cm else -1])
		for v in _views():
			_aim(cam, t, v)
			for _j in 20:
				await process_frame
			await _grab("%s_%s" % [spot_name, v["name"]])
	var fa := FileAccess.open(_out.path_join("shot_log.txt"), FileAccess.WRITE)
	fa.store_string("\n".join(_log))
	fa.close()
	print("SHOT MODE OK")
	quit(0)


func _views() -> Array:
	return [
		{"name": "iso", "ortho": true, "size": 90.0, "off": Vector3(1, 0.82, 1).normalized() * 160.0},
		{"name": "eye", "ortho": false, "fov": 65.0, "off": Vector3(0.01, 4.0, 34), "look": Vector3(0, 2.0, -40)},
		{"name": "top", "ortho": true, "size": 140.0, "off": Vector3(0, 200, 0.01)},
	]


func _aim(cam: Camera3D, t: Vector3, v: Dictionary) -> void:
	if v["ortho"]:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = v["size"]
		cam.near = 0.5
	else:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = v["fov"]
		cam.near = 0.05
	cam.global_position = t + v["off"]
	var look: Vector3 = t + (v["look"] if v.has("look") else Vector3.ZERO)
	var up := Vector3.FORWARD if v["name"] == "top" else Vector3.UP
	cam.look_at(look, up)


func _surface(world, w: Vector2) -> float:
	if world and world.has_method("get_surface_height"):
		return float(world.get_surface_height(w.x, w.y))
	return 0.0


func _teleport_and_wait(cm, world, player, w: Vector2) -> bool:
	var ws = load("res://config/world_settings.gd").get_active()
	var col := w / 2.0
	if ws and ws.has_method("world_to_column"):
		col = Vector2(ws.world_to_column(w.x), ws.world_to_column(w.y))
	if player:
		player.set_physics_process(false)
	var stable := 0
	var f := 0
	var ok := false
	while f < 7200:
		if player:
			var h := _surface(world, w) / 2.0 + 2.0
			if ws and ws.has_method("world_to_column"):
				h = ws.world_to_column(_surface(world, w)) + 2.0
			if "voxel_position" in player:
				player.voxel_position = Vector3(col.x, h, col.y)
			if player.has_method("_sync_global_from_voxel"):
				player._sync_global_from_voxel()
			else:
				player.global_position = Vector3(w.x, _surface(world, w) + 2.0, w.y)
		await process_frame
		f += 1
		if f < 30 or cm == null:
			continue
		if _area_ready(cm, col):
			stable += 1
			if stable >= 45:
				ok = true
				break
		else:
			stable = 0
	_note("WAIT frames=%d ok=%s" % [f, str(ok)])
	return ok


func _area_ready(cm, col: Vector2) -> bool:
	var size := 16
	var cd = load("res://chunks/chunk_data.gd")
	if cd and "SIZE" in cd:
		size = int(cd.SIZE)
	var cx := floori(col.x / float(size))
	var cz := floori(col.y / float(size))
	var r := int(cm.RENDER_DISTANCE) if "RENDER_DISTANCE" in cm else 6
	var missing := 0
	for z in range(cz - r, cz + r + 1):
		for x in range(cx - r, cx + r + 1):
			var k := Vector2i(x, z)
			if cm.has_method("_WorldBakeService_is_outside") and cm._WorldBakeService_is_outside(k):
				continue
			if not cm.chunks.has(k):
				missing += 1
	var busy := 0
	for q in ["_stream_load_pending", "_chunk_tasks", "_mesh_completion_queue", "pending"]:
		if q in cm:
			busy += int(cm.get(q).size())
	return missing == 0 and busy == 0


func _hide_canvas(n: Node) -> void:
	for ch in n.get_children():
		if ch is CanvasLayer:
			ch.visible = false
		_hide_canvas(ch)


func _load_spots() -> Dictionary:
	var out := {}
	var p := OS.get_environment("CRYSTALSTORM_SHOT_SPOTS")
	if p == "" or not FileAccess.file_exists(p):
		return out
	for line in FileAccess.get_file_as_string(p).split("\n"):
		var f := line.strip_edges().split(" ", false)
		if f.size() == 3:
			out[f[0]] = Vector2(float(f[1]), float(f[2]))
	return out


func _note(s: String) -> void:
	print(s)
	_log.append(s)


func _grab(n: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var p := _out.path_join(n + ".png")
	if img and img.save_png(p) == OK:
		_note("SHOT %s" % p)
