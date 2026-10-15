extends SceneTree

const _TextureSet = preload("res://helpers/texture_set.gd")
const _Shadow = preload("res://helpers/contact_shadow.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("Batch 1 capture skipped (headless)")
		quit(0)
		return
	_ensure_bake_env()
	var out := _out_path()
	var packed := load("res://scenes/main.tscn")
	if packed == null:
		push_error("Batch 1 capture: main scene missing")
		quit(1)
		return
	PlayerSettings.tutorial_completed = true
	var game: Node = (packed as PackedScene).instantiate()
	root.add_child(game)
	var player: Node = null
	var chunks := 0
	for _i in 7200:
		await process_frame
		PlayerSettings.tutorial_completed = true
		player = _first("player")
		var cm := _first("chunk_manager")
		chunks = int(cm.chunks.size()) if cm != null and "chunks" in cm else 0
		if player != null and bool(player.get("world_ready")) and chunks > 0:
			break
	if player == null or not bool(player.get("world_ready")) or chunks <= 0:
		push_error("Batch 1 capture: player not ready")
		quit(1)
		return
	var load_ui := _first("loading_screen")
	if load_ui is CanvasItem:
		(load_ui as CanvasItem).visible = false
	_hide_chrome()
	PlayerSettings.texture_set = "batch1"
	PlayerSettings.texture_blueprint = false
	_TextureSet.refresh_live(self)
	_spawn_showcase(game, player as Node3D)
	var cam := _first("camera")
	if cam != null and cam is Camera3D:
		_aim_at_player(cam as Camera3D, player as Node3D)
	for _settle in 8:
		await process_frame
		PlayerSettings.tutorial_completed = true
		PlayerSettings.texture_set = "batch1"
	_hide_chrome()
	var img: Image = null
	for _shot in 8:
		await RenderingServer.frame_post_draw
		var vt := root.get_viewport().get_texture()
		if vt:
			img = vt.get_image()
		if img != null and img.get_width() > 0:
			break
	if img == null or img.get_width() <= 0:
		push_error("Batch 1 capture: no viewport image")
		quit(1)
		return
	if not out.is_empty():
		var folder := out.get_base_dir()
		if not folder.is_empty():
			DirAccess.make_dir_recursive_absolute(folder)
		if img.save_png(out) != OK:
			push_error("Batch 1 capture: out save failed")
			quit(1)
			return
	print("Batch 1 capture saved %s" % out)
	quit(0)


func _spawn_showcase(game: Node, player: Node3D) -> void:
	var origin := player.global_position
	var spots: Array[Dictionary] = [
		{"name": "Sword", "path": "res://assets/art/items/wooden_sword.png", "at": Vector3(-2.2, 0.0, 1.2), "px": 0.05},
		{"name": "Herb", "path": "res://assets/art/items/herb.png", "at": Vector3(-0.8, 0.0, 1.4), "px": 0.05},
		{"name": "Rabbit", "path": "res://assets/art/entity/rabbit.png", "at": Vector3(0.8, 0.0, 1.1), "px": 0.04},
		{"name": "Tree", "path": "res://assets/art/vegetation/tree_s2.png", "at": Vector3(2.4, 0.0, 0.6), "px": 0.045},
		{"name": "CorruptBush", "path": "res://assets/art/vegetation/corrupted_%s.png" % "bush_s2", "at": Vector3(2.2, 0.0, 2.0), "px": 0.045},
		{"name": "Crystal", "path": "res://assets/art/crystal/amethyst.png", "at": Vector3(-2.0, 0.0, 2.4), "px": 0.03},
	]
	for spot in spots:
		_billboard(game, str(spot.name), str(spot.path), origin + spot.at, float(spot.px))
	_Shadow.attach(player, 0.05, 1.6)


func _billboard(game: Node, node_name: String, tex_path: String, feet: Vector3, pixel_size: float) -> void:
	var anchor := Node3D.new()
	anchor.name = node_name + "Anchor"
	game.add_child(anchor)
	anchor.global_position = feet
	var sprite := Sprite3D.new()
	sprite.name = node_name
	sprite.add_to_group("texture_set_sprite")
	sprite.set_meta("cs_texture_request", tex_path)
	sprite.texture = _TextureSet.resolve(tex_path)
	sprite.pixel_size = pixel_size
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.position = Vector3(0.0, 1.15, 0.0)
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	anchor.add_child(sprite)
	_Shadow.attach(anchor, 0.05, 1.1)


func _hide_chrome() -> void:
	PlayerSettings.tutorial_completed = true
	if ClassDB.class_exists("TutorialOverlay"):
		TutorialOverlay.dismiss()
	for node in get_nodes_in_group("loading_screen"):
		if node is CanvasItem:
			(node as CanvasItem).visible = false
	for node in get_nodes_in_group("debug_panel"):
		if node is CanvasItem:
			(node as CanvasItem).visible = false
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is TutorialOverlay:
			(node as CanvasLayer).visible = false


func _aim_at_player(cam: Camera3D, player: Node3D) -> void:
	if cam == null or player == null:
		return
	cam.set_process(false)
	cam.current = true
	var anchor := player.global_position + Vector3(0.6, 1.2, 1.2)
	var yaw := deg_to_rad(45.0)
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 8.0
	cam.global_position = anchor + back * 30.0 + Vector3(0.0, 18.0, 0.0)
	cam.look_at(anchor, Vector3.UP)


func _first(group: String) -> Node:
	var nodes := get_nodes_in_group(group)
	if nodes.is_empty():
		return null
	return nodes[0]


func _out_path() -> String:
	var out := OS.get_environment("CRYSTALSTORM_BATCH_OUT").strip_edges()
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var arg := str(args[i])
		if arg == "--out" and i + 1 < args.size():
			out = str(args[i + 1])
		elif arg.begins_with("--out="):
			out = arg.substr("--out=".length())
	return out


func _ensure_bake_env() -> void:
	if OS.get_environment("CRYSTALSTORM_BAKE_RADIUS").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	if OS.get_environment("CRYSTALSTORM_FULL_WORLD_BAKE").is_empty():
		OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	if OS.get_environment("CRYSTALSTORM_BAKE_ON_NEW").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
