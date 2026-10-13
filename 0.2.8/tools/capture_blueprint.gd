extends SceneTree
## Windowed blueprint screenshot.
## Headless prints a skip line and exits 0.
## godot --path . -s res://tools/capture_blueprint.gd -- --out <path>
## Optional env: CRYSTALSTORM_BLUEPRINT_OUT

const _Shadow = preload("res://helpers/contact_shadow.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("Blueprint capture skipped (headless)")
		quit(0)
		return
	_ensure_bake_env()
	var out := _out_path()
	var packed := load("res://scenes/main.tscn")
	if packed == null:
		push_error("Blueprint capture: main scene missing")
		quit(1)
		return
	# Keep the first-run tutorial from covering the shot. Do not save settings.
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
		push_error("Blueprint capture: player not ready")
		quit(1)
		return
	# The start-region gate can still cover the view after world_ready.
	var load_ui := _first("loading_screen")
	if load_ui is CanvasItem:
		(load_ui as CanvasItem).visible = false
	var cam := _first("camera")
	if cam != null:
		if "zoom_level" in cam:
			cam.zoom_level = 12.0
		if cam is Camera3D:
			(cam as Camera3D).size = 12.0
	print("Blueprint world visible chunks=%d" % chunks)
	_hide_chrome()
	_spawn_showcase(game, player as Node3D)
	var bp := root.get_node_or_null("TextureBlueprint")
	if bp != null and bp.has_method("set_enabled"):
		bp.set_enabled(true)
	for _j in 8:
		await process_frame
	_rebind_chunks()
	_hide_chrome()
	_aim_at_player(cam as Camera3D, player as Node3D)
	for _settle in 2:
		await process_frame
	_report_terrain(game, "Blueprint terrain")
	var img: Image = null
	for _shot in 8:
		await RenderingServer.frame_post_draw
		var vt := root.get_viewport().get_texture()
		if vt:
			img = vt.get_image()
		if img != null and img.get_width() > 0:
			break
	if img == null or img.get_width() <= 0:
		push_error("Blueprint capture: no viewport image")
		quit(1)
		return
	var user_path := ProjectSettings.globalize_path("user://blueprint_view.png")
	if img.save_png(user_path) != OK:
		push_error("Blueprint capture: user save failed")
		quit(1)
		return
	if not out.is_empty():
		var folder := out.get_base_dir()
		if not folder.is_empty():
			DirAccess.make_dir_recursive_absolute(folder)
		if img.save_png(out) != OK:
			push_error("Blueprint capture: out save failed")
			quit(1)
			return
	_report_pixels(img)
	print("Blueprint capture saved")
	quit(0)


func _hide_chrome() -> void:
	# In-memory only. Do not write player_settings.json.
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


## Orthographic iso aimed at the player so the body, nearby props, and terrain share the frame.
func _aim_at_player(cam: Camera3D, player: Node3D) -> void:
	if cam == null or player == null:
		return
	cam.set_process(false)
	cam.current = true
	var anchor := player.global_position + Vector3(0.0, 1.2, 0.0)
	var yaw := deg_to_rad(45.0)
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 10.0
	cam.global_position = anchor + back * 30.0 + Vector3(0.0, 22.0, 0.0)
	cam.look_at(anchor, Vector3.UP)
	var screen := cam.unproject_position(player.global_position)
	print("Blueprint player screen %s" % screen)


func _rebind_chunks() -> void:
	var script = load("res://chunks/chunk_view.gd")
	if script != null:
		script.rebind_live_materials(self)


func _report_pixels(img: Image) -> void:
	var orange := 0
	var counted := 0
	var step := 6
	var y_end := maxi(img.get_height() - 90, 1)
	for y in range(36, y_end, step):
		for x in range(16, img.get_width() - 16, step):
			counted += 1
			var c := img.get_pixel(x, y)
			if c.r > 0.35 and c.r > c.g * 1.25 and c.g > c.b:
				orange += 1
	var mid := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
	print("Blueprint pixels orange=%d/%d center=%s" % [orange, counted, mid])


func _report_terrain(game: Node, tag: String) -> void:
	var bp := root.get_node_or_null("TextureBlueprint")
	print("%s enabled=%s" % [tag, str(bp.get("enabled")) if bp else "missing"])
	var meshes := 0
	var swapped := 0
	var stack: Array = [game]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if not (node is MeshInstance3D) or str(node.name) != "terrain_surface_mesh":
			continue
		meshes += 1
		var mat := (node as MeshInstance3D).material_override
		if not (mat is ShaderMaterial):
			if meshes <= 2:
				print("%s mesh material %s" % [tag, mat])
			continue
		var tex = (mat as ShaderMaterial).get_shader_parameter("texture_atlas")
		var is_bp := tex is Texture2D and (tex as Texture2D).has_meta("cs_blueprint")
		if is_bp:
			swapped += 1
		if meshes <= 2:
			print("%s tex=%s blueprint=%s" % [tag, tex, is_bp])
	print("%s meshes=%d swapped=%d" % [tag, meshes, swapped])


func _spawn_showcase(game: Node, player: Node3D) -> void:
	var origin := player.global_position
	_billboard(game, "MobSprite", "res://assets/art/entity/rabbit.png", origin + Vector3(2.0, 0.0, 0.6), 1.2)
	_billboard(game, "ItemSprite", "res://assets/art/items/wooden_sword.png", origin + Vector3(-1.6, 0.0, 1.0), 0.9)
	_billboard(game, "ItemSpriteB", "res://assets/art/items/stone.png", origin + Vector3(0.4, 0.0, -1.6), 0.9)
	_Shadow.attach(player, 0.05, 1.6)


func _billboard(game: Node, node_name: String, tex_path: String, feet: Vector3, diameter: float) -> void:
	var anchor := Node3D.new()
	anchor.name = node_name + "Anchor"
	game.add_child(anchor)
	anchor.global_position = feet
	var sprite := Sprite3D.new()
	sprite.name = node_name
	sprite.texture = load(tex_path)
	sprite.pixel_size = 0.045
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.position = Vector3(0.0, 1.0, 0.0)
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	anchor.add_child(sprite)
	_Shadow.attach(anchor, 0.05, diameter)


func _first(group: String) -> Node:
	var nodes := get_nodes_in_group(group)
	if nodes.is_empty():
		return null
	return nodes[0]


func _out_path() -> String:
	var out := OS.get_environment("CRYSTALSTORM_BLUEPRINT_OUT").strip_edges()
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
