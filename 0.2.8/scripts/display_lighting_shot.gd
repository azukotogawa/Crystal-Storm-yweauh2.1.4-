extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("lighting shot needs a window")
		quit(1)
		return
	var folder := OS.get_environment("CRYSTALSTORM_LIGHTING_DIR").strip_edges()
	if folder.is_empty():
		folder = "D:/ARCHIVE/CrystalStorm/verify-evidence/lighting"
	DirAccess.make_dir_recursive_absolute(folder)
	var tag := OS.get_environment("CRYSTALSTORM_LIGHTING_TAG").strip_edges()
	if tag.is_empty():
		tag = "shot"
	DisplayServer.window_set_title("Crystal Storm lighting %s" % tag)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		push_error("main missing")
		quit(1)
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while frames < 3600:
		if compose != null and int(compose.stage) >= int(compose.Stage.INITIAL_STREAM_READY):
			break
		await process_frame
		frames += 1
	if frames >= 3600:
		push_error("lighting shot timed out")
		quit(1)
		return
	for _i in 20:
		await process_frame
	var tutorial := load("res://ui/tutorial_overlay.gd")
	if tutorial != null and tutorial.has_method("dismiss"):
		tutorial.dismiss()
	var canvas := game.get_node_or_null("CanvasLayer")
	if canvas != null:
		canvas.visible = false
	var loading := game.get_node_or_null("LoadingLayer")
	if loading != null:
		loading.visible = false
	for node in root.get_children():
		if node is CanvasLayer and node != game:
			(node as CanvasLayer).visible = false
	for _j in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [folder, tag]
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("lighting shot empty")
		quit(1)
		return
	var err := img.save_png(path)
	if err != OK:
		push_error("lighting shot save %s" % str(err))
		quit(1)
		return
	print("LIGHTING_SHOT=%s" % path)
	print("LIGHTING SHOT OK")
	quit(0)
