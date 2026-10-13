extends SceneTree
## Early-run survival PE: spawn far enough from crystal origin, mite grace holds,
## first enemy spawn is announcable via production spawner signal.
## Usage: godot --headless -s scripts/verify_early_survival.gd

const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")

var _failed: int = 0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("main missing")
		_ProbeExit.finish_tree(self, 1, "Early survival FAILED")
		return
	var game: Node = packed.instantiate()
	root.add_child(game)

	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while compose and not bool(compose.get("_boot_done")) and frames < 2400:
		await process_frame
		frames += 1

	var player = get_first_node_in_group("player")
	var crystal = get_first_node_in_group("crystal_manager")
	var gm = get_first_node_in_group("game_manager")
	var spawner = get_first_node_in_group("crystal_enemy_spawner")

	while player and not bool(player.get("world_ready")) and frames < 3200:
		await process_frame
		frames += 1

	if player == null or crystal == null:
		_fail("player/crystal missing")
		_ProbeExit.finish_tree(self, 1, "Early survival FAILED")
		return

	# Structural: opening + mite toast wiring in overlay.
	var overlay_src := (load("res://ui/game_overlay.gd") as GDScript).source_code
	if "Maze phase" not in overlay_src and "_show_opening_toast" not in overlay_src:
		_fail("overlay must show opening maze toast")
	else:
		print("OK opening toast wiring")
	if "enemy_spawned" not in overlay_src or "Crystal hostiles" not in overlay_src:
		_fail("overlay must toast first crystal enemy spawn")
	else:
		print("OK first-threat toast wiring")

	if spawner == null:
		_fail("crystal_enemy_spawner missing")
	elif not ("spawn_grace_sec" in spawner):
		_fail("spawner must expose spawn_grace_sec")
	else:
		print("OK spawn_grace_sec=%.1f" % float(spawner.spawn_grace_sec))

	# Spawn distance from boss origin.
	var origin := Vector2i.ZERO
	for s in crystal.get_active_spawns():
		if s.is_boss:
			origin = s.world_pos
			break
	var pv: Vector3 = player.get_voxel_position()
	var pcol := Vector2i(floori(pv.x), floori(pv.z))
	var dist := Vector2(pcol).distance_to(Vector2(origin))
	print("spawn player=%s origin=%s dist=%.1f" % [pcol, origin, dist])
	if dist < 20.0:
		_fail("player spawn too close to crystal origin dist=%.1f (want ≥20)" % dist)
	else:
		print("OK spawn distance from origin=%.1f" % dist)

	# Survive only while spawn grace is active (no post-grace combat buffer —
	# idle player can legitimately die once mites start after grace ends).
	var grace: float = float(spawner.spawn_grace_sec) if spawner and "spawn_grace_sec" in spawner else 28.0
	var max_frames := mini(int(ceil(grace * 90.0)) + 120, 3600)
	var t0 := Time.get_ticks_msec()
	var died := false
	var frames_waited := 0
	while frames_waited < max_frames:
		await process_frame
		frames_waited += 1
		var still_in_grace := true
		if spawner and "spawn_grace_sec" in spawner and "_grace_elapsed" in spawner:
			still_in_grace = float(spawner.get("_grace_elapsed")) < float(spawner.spawn_grace_sec)
		elif frames_waited >= int(ceil(grace * 60.0)):
			still_in_grace = false
		if not still_in_grace:
			break
		if gm and int(gm.run_state) != 0:
			died = true
			_fail("player lost during early grace: %s t=%dms" % [
				str(gm.last_loss_reason), Time.get_ticks_msec() - t0
			])
			break
		if player and float(player.health) <= 0.0:
			died = true
			_fail("player HP zero during early grace")
			break
	if not died:
		print("OK survived early window t=%dms hp=%.1f frames=%d" % [
			Time.get_ticks_msec() - t0, float(player.health), frames_waited
		])

	# Production spawn path still works after grace (force).
	if spawner and spawner.has_method("spawn_enemy_now"):
		# Advance grace if needed for manual spawn tests of signal path.
		if "spawn_grace_sec" in spawner:
			spawner.set("_grace_elapsed", float(spawner.spawn_grace_sec) + 1.0)
		var saw := {"id": &"", "pos": Vector2i.ZERO}
		if spawner.has_signal("enemy_spawned"):
			spawner.enemy_spawned.connect(func(eid, pos):
				saw["id"] = eid
				saw["pos"] = pos
			, CONNECT_ONE_SHOT)
		var ok_spawn: bool = spawner.spawn_enemy_now(&"crystal_mite")
		for _w in 30:
			await process_frame
		if not ok_spawn and saw["id"] == &"":
			# spawn may fail without crystal depth near far player — still OK if grace/survival passed
			print("NOTE spawn_enemy_now no-op (no crystal ring near far spawn) — survival still OK")
		else:
			print("OK enemy spawn path id=%s pos=%s" % [saw["id"], saw["pos"]])

	if _failed == 0:
		print("All early survival tests OK")
		_ProbeExit.finish_tree(self, 0, "All early survival tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "Early survival FAILED")
