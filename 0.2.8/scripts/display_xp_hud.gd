extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const _Progression = preload("res://systems/progression_service.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("xp hud window needs a window")
		quit(1)
		return
	var folder := OS.get_environment("CRYSTALSTORM_XP_HUD_DIR").strip_edges()
	if folder.is_empty():
		folder = "D:/ARCHIVE/CrystalStorm/verify-evidence/pivot-0.4/xp-hud"
	DirAccess.make_dir_recursive_absolute(folder)
	DisplayServer.window_set_title("Crystal Storm XP")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		push_error("main missing")
		quit(1)
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	if not await _wait_stream(game):
		quit(1)
		return
	_dismiss_blockers(game)
	var overlay := get_first_node_in_group("game_overlay")
	if overlay and overlay.has_method("notify_loading_finished"):
		overlay.notify_loading_finished()
	for _i in 20:
		await process_frame
	var svc = _Progression.get_active()
	if svc == null:
		svc = get_first_node_in_group("progression_service")
	if svc == null or overlay == null or not svc.has_method("add_xp"):
		push_error("xp hud window missing progression or overlay")
		quit(1)
		return
	svc.add_xp(70)
	var toast := overlay.get_node_or_null("ToastLabel") as Label
	var level_label := overlay.get_node_or_null("XpBar/Row/XpLevel") as Label
	var value_label := overlay.get_node_or_null("XpBar/Row/XpValue") as Label
	if toast == null or toast.text != "Level up — 2" or level_label == null or level_label.text != "Lv 2":
		push_error("xp bar shot missed the level-up toast (%s)" % (toast.text if toast else "missing"))
		quit(1)
		return
	if value_label == null or value_label.text != "20 / %d" % _Progression.xp_to_advance(2):
		push_error("xp bar value is %s" % (value_label.text if value_label else "missing"))
		quit(1)
		return
	if not await _save_shot(folder, "xp-bar-level-up"):
		quit(1)
		return
	var gm := get_first_node_in_group("game_manager")
	if gm and gm.has_method("_on_player_died"):
		gm._on_player_died()
	for _i in 6:
		await process_frame
	if not await _save_shot(folder, "xp-run-summary"):
		quit(1)
		return
	var body := overlay.find_child("SummaryBody", true, false) as Label
	if body == null or not body.text.contains("Level: 2") or not body.text.contains("XP: 20 /"):
		push_error("run summary shot missed level and xp")
		quit(1)
		return
	print("XP HUD WINDOW OK")
	quit(0)


func _wait_stream(game: Node) -> bool:
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while frames < 3600:
		if compose != null and int(compose.stage) >= int(compose.Stage.INITIAL_STREAM_READY):
			return true
		await process_frame
		frames += 1
	push_error("xp hud window stream timeout")
	return false


func _dismiss_blockers(game: Node) -> void:
	var tutorial := load("res://ui/tutorial_overlay.gd")
	if tutorial != null and tutorial.has_method("dismiss"):
		tutorial.dismiss()
	var loading := game.get_node_or_null("LoadingLayer")
	if loading != null:
		loading.visible = false
	for _i in 8:
		await process_frame


func _save_shot(folder: String, tag: String) -> bool:
	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("xp hud shot empty %s" % tag)
		return false
	var path := "%s/%s.png" % [folder, tag]
	var err := img.save_png(path)
	if err != OK:
		push_error("xp hud shot save %s %s" % [tag, str(err)])
		return false
	print("SHOT %s" % path)
	return true
