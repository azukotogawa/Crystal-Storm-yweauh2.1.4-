extends SceneTree

const HOLD := 3.0
const _Hud = preload("res://scripts/honest_bot/honest_showcase_hud.gd")
const _Chapters = preload("res://scripts/honest_bot/honest_chapters.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var panel := ColorRect.new()
	panel.position = Vector2(12, 12)
	panel.size = Vector2(328, 164)
	panel.color = Color(0.22, 0.05, 0.32, 0.92)
	root.add_child(panel)
	var hp := Label.new()
	hp.position = Vector2(24, 78)
	hp.text = "Crystal HP  350 / 500"
	hp.add_theme_font_size_override("font_size", 18)
	hp.add_theme_color_override("font_color", Color(0.95, 0.9, 1))
	root.add_child(hp)
	var hud = _Hud.new()
	root.add_child(hud)
	var log = _Chapters.new()
	log.begin()
	hud.set_readout(log.format_clock(), "dig_tool")
	await process_frame
	log.advance(root.get_process_delta_time())
	await process_frame
	log.advance(root.get_process_delta_time())
	hud.set_readout(log.format_clock(), "dig_tool")
	var chapter := hud.get_child(1) as Label
	var rect := Rect2()
	if chapter != null:
		rect = chapter.get_global_rect()
	var panel_rect := panel.get_global_rect()
	if chapter == null or rect.position.x < panel_rect.end.x or rect.intersects(panel_rect):
		print("FAIL chapter label overlaps crystal panel")
		quit(1)
		return
	print("OK chapter label clear of crystal panel")
	while log.seconds() < HOLD:
		await process_frame
		log.advance(root.get_process_delta_time())
		hud.set_readout(log.format_clock(), "dig_tool")
		panel.color = Color(0.22, 0.05 + 0.2 * sin(log.seconds() * 3.0), 0.45, 0.92)
	print("MOVIE_GAME_SEC %.3f" % log.seconds())
	quit(0)
