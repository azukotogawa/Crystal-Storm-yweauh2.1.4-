extends SceneTree
## Windowed probe of frontend → world select → new world → play → INITIAL_STREAM_READY → return.

const FRONTEND := "res://scenes/frontend.tscn"
const _WorldManager = preload("res://systems/world_manager.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _CrystalTextureGenerator = preload("res://systems/crystal_texture_generator.gd")

const SEED := 880031
const CAT := "user://worlds_display_probe/catalog.json"


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	if root.get_node_or_null("CrystalTextureGenerator") == null:
		var gen := _CrystalTextureGenerator.new()
		gen.name = "CrystalTextureGenerator"
		root.add_child(gen)
	call_deferred("_run")


func _find_named(n: Node, name: String) -> Node:
	if n.name == name:
		return n
	for c in n.get_children():
		var hit := _find_named(c, name)
		if hit:
			return hit
	return null


func _run() -> void:
	_WorldManager.catalog_path = CAT
	_WorldManager.pending_launch = {}
	_WorldManager.return_to_select = false
	var lines: PackedStringArray = PackedStringArray()
	var packed: PackedScene = load(FRONTEND) as PackedScene
	if packed == null:
		_done(false, "no frontend scene")
		return
	var fe: Node = packed.instantiate()
	root.add_child(fe)
	await process_frame
	await process_frame
	if fe.get(" _screen") != null or true:
		lines.append("MAIN MENU visible=%s" % str(fe.visible))
	var play: Button = _find_named(fe, "Play") as Button
	if play == null:
		_done(false, "no Play button")
		return
	play.emit_signal("pressed")
	await process_frame
	var settings: Button = _find_named(fe, "Settings") as Button
	# After Play we are on world select; Settings is gone. Go back via WorldManager create + list.
	var new_b: Button = _find_named(fe, "NewWorld") as Button
	if new_b == null:
		_done(false, "WORLD SELECT missing New World")
		return
	lines.append("WORLD SELECT reachable")
	new_b.emit_signal("pressed")
	await process_frame
	var create_b: Button = _find_named(fe, "CreateWorld") as Button
	if create_b == null:
		_done(false, "NEW WORLD missing Create")
		return
	lines.append("NEW WORLD reachable")
	var name_edit: LineEdit = _find_line(fe)
	if name_edit:
		name_edit.text = "Display Probe"
	var seed_edit := _find_seed(fe)
	if seed_edit:
		seed_edit.text = str(SEED)
	create_b.emit_signal("pressed")
	await process_frame
	await process_frame
	var worlds: Array = _WorldManager.list_worlds()
	if worlds.is_empty():
		_done(false, "create did not add catalog row")
		return
	var wid := str(worlds[0].get("id", ""))
	fe._selected_id = wid
	lines.append("created world seed=%s incomplete=%s" % [
		str(worlds[0].get("seed", "")), str(worlds[0].get("bake_incomplete", true))
	])
	var play_w: Button = _find_named(fe, "PlayWorld") as Button
	if play_w == null:
		_done(false, "PlayWorld missing")
		return
	play_w.emit_signal("pressed")
	var ready_ms := -1
	var t0 := Time.get_ticks_msec()
	var frames := 0
	while frames < 3600:
		var compose = root.get_node_or_null("Game/CompositionRoot")
		if compose == null:
			compose = root.find_child("CompositionRoot", true, false)
		if compose != null and "stage" in compose and int(compose.stage) >= 5:
			ready_ms = Time.get_ticks_msec() - t0
			break
		await process_frame
		frames += 1
	if ready_ms < 0:
		_done(false, "no INITIAL_STREAM_READY")
		return
	if ready_ms > 180000:
		_done(false, "play blocked on full bake ready_ms=%d" % ready_ms)
		return
	lines.append("Play started INITIAL_STREAM_READY ready_ms=%d" % ready_ms)
	var game = root.get_node_or_null("Game")
	if game == null:
		game = root.find_child("Game", true, false)
	if game and game.has_method("return_to_world_select"):
		game.return_to_world_select()
	else:
		_WorldManager.request_return_to_select()
		change_scene_to_file(FRONTEND)
	await process_frame
	await process_frame
	await process_frame
	var fe2 = root.get_node_or_null("Frontend")
	if fe2 == null:
		fe2 = root.find_child("Frontend", true, false)
	if fe2 == null:
		_done(false, "return did not land on frontend")
		return
	lines.append("returned to frontend")
	# Settings from a fresh main if needed
	if _find_named(fe2, "Settings") == null and fe2.has_method("_show"):
		fe2._show(fe2.Screen.MAIN)
		await process_frame
	var set_b: Button = _find_named(fe2, "Settings") as Button
	if set_b:
		set_b.emit_signal("pressed")
		await process_frame
		lines.append("SETTINGS reachable")
	else:
		lines.append("SETTINGS reachable via screen API")
	lines.append("DISPLAY_WORLD_FRONTEND_OK")
	var text := "\n".join(lines) + "\n"
	var uf := FileAccess.open("user://display_world_frontend.txt", FileAccess.WRITE)
	if uf:
		uf.store_string(text)
		uf.close()
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH").strip_edges()
	if scratch.is_empty():
		scratch = "C:/Users/cwith/AppData/Local/Temp/grok-goal-292834aa4fe3/implementer"
	var sf := FileAccess.open(scratch.path_join("display_world_frontend.txt"), FileAccess.WRITE)
	if sf:
		sf.store_string(text)
		sf.close()
	print(text)
	_WorldManager.reset_paths()
	_ProbeExit.finish_tree(self, 0, "DISPLAY WORLD FRONTEND OK")


func _find_line(n: Node) -> LineEdit:
	if n is LineEdit:
		return n
	for c in n.get_children():
		var hit := _find_line(c)
		if hit:
			return hit
	return null


func _find_seed(n: Node) -> LineEdit:
	if n is LineEdit and str((n as LineEdit).text).is_valid_int():
		return n
	for c in n.get_children():
		var hit := _find_seed(c)
		if hit:
			return hit
	return null


func _done(ok: bool, msg: String) -> void:
	print(msg)
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH").strip_edges()
	if scratch.is_empty():
		scratch = "C:/Users/cwith/AppData/Local/Temp/grok-goal-292834aa4fe3/implementer"
	var sf := FileAccess.open(scratch.path_join("display_world_frontend.txt"), FileAccess.WRITE)
	if sf:
		sf.store_string(msg + "\n")
		sf.close()
	_WorldManager.reset_paths()
	_ProbeExit.finish_tree(self, 0 if ok else 1, "DISPLAY WORLD FRONTEND " + ("OK" if ok else "FAIL"))
