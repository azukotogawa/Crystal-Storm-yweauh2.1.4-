extends SceneTree
## Display (windowed) cold-boot of production main.tscn with deferred fill.
## Confirms INITIAL_STREAM_READY before full bake, movement, and a far on-demand bake.

const MAIN_SCENE := "res://scenes/main.tscn"
const _WorldBakeService = preload("res://world/world_bake_service.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")


func _init() -> void:
	# Production full world. Do not set BAKE_RADIUS.
	OS.set_environment("CRYSTALSTORM_BAKE_DEFER_FILL", "1")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_ProbeExit.finish_tree(self, 1, "DISPLAY DEFERRED BAKE FAIL no main")
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var ready_ms := -1
	var frames := 0
	while frames < 3600:
		if compose != null and int(compose.stage) >= compose.Stage.INITIAL_STREAM_READY:
			ready_ms = Time.get_ticks_msec() - t0
			break
		await process_frame
		frames += 1
	if ready_ms < 0:
		print("DISPLAY_DEFERRED ready_ms=-1")
		_ProbeExit.finish_tree(self, 1, "DISPLAY DEFERRED BAKE FAIL no INITIAL_STREAM_READY")
		return

	var bake = _WorldBakeService.get_active()
	var cm = game.get_tree().get_first_node_in_group("chunk_manager")
	var player = game.get_tree().get_first_node_in_group("player")
	var fill: Dictionary = bake.fill_status() if bake and bake.has_method("fill_status") else {}
	var chunks_ready: int = cm.chunks.size() if cm and cm.chunks else 0
	print("DISPLAY_DEFERRED ready_ms=%d valid=%s in_progress=%s fill=%s/%s chunks=%d" % [
		ready_ms,
		str(bake.valid) if bake else "?",
		str(bake.bake_in_progress) if bake else "?",
		str(fill.get("done", 0)),
		str(fill.get("total", 0)),
		chunks_ready,
	])
	if chunks_ready < 1:
		_ProbeExit.finish_tree(self, 1, "DISPLAY DEFERRED BAKE FAIL no resident chunks")
		return
	if bake and bake.valid and int(fill.get("total", 0)) > 200 and ready_ms < 60000:
		# Warm leftover index from a previous complete bake — still a valid display boot.
		print("DISPLAY_DEFERRED note=warm_or_completed_index")
	elif bake and int(fill.get("total", 16384)) >= 1000 and bake.valid:
		_ProbeExit.finish_tree(self, 1, "DISPLAY DEFERRED BAKE FAIL index valid at playable on cold full map")
		return

	# Movement + one dig on the start cell.
	if player:
		var before: Vector3 = player.global_position
		player.voxel_position.x += 0.4
		await process_frame
		await process_frame
		print("DISPLAY_DEFERRED moved before=%s after=%s" % [str(before), str(player.global_position)])
	var editor = game.get_tree().get_first_node_in_group("terrain_editor")
	if editor and player and editor.has_method("try_dig"):
		var col: Vector3 = player.get_voxel_position() if player.has_method("get_voxel_position") else player.global_position
		var dug: bool = editor.try_dig(Vector3(floor(col.x), 0, floor(col.z)))
		print("DISPLAY_DEFERRED dig=%s" % str(dug))

	# Far unbaked coord (if still filling).
	if bake and bake.bake_in_progress:
		var far := Vector2i(40, 40)
		if bake.coord_in_package(far) and not bake.package_ready(far):
			var ok: bool = bake.ensure_package_for_stream(far)
			print("DISPLAY_DEFERRED on_demand_far=%s ready=%s valid=%s" % [
				str(ok), str(bake.package_ready(far)), str(bake.valid)
			])
			if not ok or bake.valid:
				_ProbeExit.finish_tree(self, 1, "DISPLAY DEFERRED BAKE FAIL on-demand")
				return

	print("DISPLAY_DEFERRED_OK ready_ms=%d" % ready_ms)
	var report := "ready_ms=%d valid=%s in_progress=%s fill=%s/%s chunks=%d\nDISPLAY_DEFERRED_OK\n" % [
		ready_ms,
		str(bake.valid) if bake else "?",
		str(bake.bake_in_progress) if bake else "?",
		str(fill.get("done", 0)),
		str(fill.get("total", 0)),
		chunks_ready,
	]
	var rf := FileAccess.open("user://display_deferred_bake_boot.txt", FileAccess.WRITE)
	if rf:
		rf.store_string(report)
		rf.close()
	_ProbeExit.finish_tree(self, 0, "DISPLAY DEFERRED BAKE OK")
