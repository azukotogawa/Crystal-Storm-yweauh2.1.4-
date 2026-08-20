extends SceneTree
## Windowed: main scene start-region gate + Live World Inspector snapshot.

const MAIN_SCENE := "res://scenes/main.tscn"
const _LiveWorldQuery = preload("res://helpers/live_world_query.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")


func _init() -> void:
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_ProbeExit.finish_tree(self, 1, "DISPLAY INSPECTOR FAIL no main")
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var ready_ms := -1
	var blocked_during_wait := false
	var frames := 0
	while frames < 3600:
		if _GameplayInput.blocks_actions():
			blocked_during_wait = true
		if compose != null and int(compose.stage) >= compose.Stage.INITIAL_STREAM_READY:
			ready_ms = Time.get_ticks_msec() - t0
			break
		await process_frame
		frames += 1
	if ready_ms < 0:
		_ProbeExit.finish_tree(self, 1, "DISPLAY INSPECTOR FAIL no INITIAL_STREAM_READY")
		return
	var cm = get_first_node_in_group("chunk_manager")
	var st: Dictionary = cm.start_region_status() if cm and cm.has_method("start_region_status") else {}
	if not bool(st.get("ready", false)):
		_ProbeExit.finish_tree(self, 1, "DISPLAY INSPECTOR FAIL start region not ready at ICS")
		return
	for _w in 20:
		await process_frame
	var insp = game.get_node_or_null("LiveWorldInspector")
	if insp == null:
		_ProbeExit.finish_tree(self, 1, "DISPLAY INSPECTOR FAIL missing inspector")
		return
	var snap: Dictionary = _LiveWorldQuery.inspect_targeted(self)
	print("DISPLAY_INSPECTOR ready_ms=%d start=%s/%s inspector=%s snap_ok=%s wx=%s origin=%s blocked_wait=%s" % [
		ready_ms,
		str(st.get("resident", 0)),
		str(st.get("needed", 0)),
		insp.name,
		str(snap.get("ok", false)),
		str(snap.get("wx", "")),
		str(snap.get("origin", "")),
		str(blocked_during_wait),
	])
	_ProbeExit.finish_tree(self, 0, "DISPLAY INSPECTOR OK")
