extends SceneTree
## Live opening + crystal→mite→combat chain. Windowed camera/F3/F4 are truth.

const MAIN_SCENE := "res://scenes/main.tscn"
const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _LiveWorldQuery = preload("res://helpers/live_world_query.gd")
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _WorldVisualCoords = preload("res://helpers/world_visual_coords.gd")


var _scratch: String = ""
var _findings: Array = []
var _snaps: Dictionary = {}
var _shots: PackedStringArray = PackedStringArray()
var _failed: int = 0
var _toast_log: PackedStringArray = PackedStringArray()


func _init() -> void:
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	if OS.get_environment("CRYSTALSTORM_BAKE_RADIUS").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	if OS.get_environment("CRYSTALSTORM_FULL_WORLD_BAKE").is_empty():
		OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	if OS.get_environment("CRYSTALSTORM_BAKE_ON_NEW").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	call_deferred("_run")


func _note(kind: String, msg: String, extra: Dictionary = {}) -> void:
	var row := {"kind": kind, "msg": msg}
	for k in extra.keys():
		row[k] = extra[k]
	_findings.append(row)
	print("%s %s" % [kind.to_upper(), msg])


func _fail(msg: String) -> void:
	_failed += 1
	_note("fail", msg)


func _run() -> void:
	_scratch = OS.get_environment("CRYSTALSTORM_SCRATCH")
	if _scratch.is_empty():
		_scratch = "C:/Users/cwith/AppData/Local/Temp/grok-goal-961aca94c53e/implementer"
	DirAccess.make_dir_recursive_absolute(_scratch)
	print("COMBAT_OPENING_AUDIT_START windowed=%s" % str(DisplayServer.get_name() != "headless"))
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("no main scene")
		_finish()
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while frames < 3600:
		if compose != null and int(compose.stage) >= compose.Stage.INITIAL_STREAM_READY:
			break
		await process_frame
		frames += 1
	if compose == null or int(compose.stage) < compose.Stage.INITIAL_STREAM_READY:
		_fail("start region not ready")
		_finish()
		return
	for _w in 40:
		await process_frame
		if not _GameplayInput.world_loading:
			break
	var player = get_first_node_in_group("player")
	var wait_p := 0
	while player and not bool(player.get("world_ready")) and wait_p < 240:
		await process_frame
		wait_p += 1
	for _s in 12:
		await process_frame

	var insp = game.get_node_or_null("LiveWorldInspector")
	if insp == null:
		insp = get_first_node_in_group("live_world_inspector")
	if insp:
		insp.panel_open = true
	_bind_toast_watch()

	# --- Opening presentation at native spawn (do not teleport). ---
	_snaps["opening"] = _opening_snapshot("t0")
	_dump_f3()
	await _shot("open_spawn")
	_note("observe", "opening %s" % str(_snaps["opening"]))
	var ohud := str(_snaps["opening"].get("hud", ""))
	var has_bearing := false
	for d in [" N", " NE", " E", " SE", " S", " SW", " W", " NW", "front"]:
		if d in ohud:
			has_bearing = true
			break
	if float(_snaps["opening"].get("crystal_dist", 0.0)) > 8.0 and not has_bearing:
		_note("disagree", "HUD missing crystal bearing at spawn: %s" % ohud)

	# Stay at spawn through grace (28s) + a little more.
	await _wait_msec(32000, "spawn_grace")
	_snaps["after_grace_at_spawn"] = _opening_snapshot("grace32")
	await _shot("open_after_grace")
	_note("observe", "after_grace_at_spawn enemies=%s unlocked=%s dist=%.1f tiles=%s" % [
		str(_snaps["after_grace_at_spawn"].get("enemies", 0)),
		str(_snaps["after_grace_at_spawn"].get("unlocked", [])),
		float(_snaps["after_grace_at_spawn"].get("crystal_dist", -1)),
		str(_snaps["after_grace_at_spawn"].get("tiles", 0)),
	])
	if int(_snaps["after_grace_at_spawn"].get("enemies", 0)) == 0:
		_note("gap", "no mites at spawn after 32s (player %.0fc from crystal, mite ring 10c)" % [
			float(_snaps["after_grace_at_spawn"].get("crystal_dist", -1))
		])

	# Walk to the existing crystal origin — combat is designed at the front.
	var crystal = get_first_node_in_group("crystal_manager")
	var origin := Vector2i.ZERO
	if crystal and crystal.has_method("get_origin_cell"):
		origin = crystal.get_origin_cell()
	_look_at(origin.x, origin.y)
	var cm = get_first_node_in_group("chunk_manager")
	await _idle(cm)
	if insp:
		insp.pin_cell = origin
	for _c in 8:
		await process_frame
	var origin_snap: Dictionary = _LiveWorldQuery.inspect_cell(self, origin.x, origin.y)
	_snaps["crystal_origin_f4"] = origin_snap
	_note("observe", "at_origin F4 has_crystal=%s visual=%s disc=%s" % [
		str(origin_snap.get("has_crystal")), str(origin_snap.get("visual_id")),
		str(origin_snap.get("discrepancies", [])),
	])
	await _shot("open_crystal_front")

	# Wait for existing spawner (grace already elapsed, mites unlocked at boot).
	var mite_wait_ms := 25000
	var t_mite := Time.get_ticks_msec()
	var saw_mite := false
	while Time.get_ticks_msec() - t_mite < mite_wait_ms:
		await process_frame
		_capture_toast()
		if get_nodes_in_group("crystal_enemy").size() > 0:
			saw_mite = true
			break
	_snaps["at_front"] = _opening_snapshot("front")
	if not saw_mite:
		_note("disagree", "no crystal_enemy at origin after grace+25s unlocked=%s grace=%s" % [
			str(_snaps["at_front"].get("unlocked", [])),
			str(_snaps["at_front"].get("grace_elapsed", -1)),
		])
		await _shot("open_no_mites")
		_write_reports()
		_finish()
		return

	var enemies: Array = get_nodes_in_group("crystal_enemy")
	var mite: Node3D = enemies[0] as Node3D
	var mcol: Vector2 = _WorldVisualCoords.column_from_node(mite)
	# Stand 1 column SE so iso look-dir (NW) includes the mite inside melee range.
	_look_at(int(round(mcol.x)) + 1, int(round(mcol.y)) + 1)
	if player:
		player.voxel_position.x = mcol.x + 1.0
		player.voxel_position.z = mcol.y + 1.0
		if player.has_method("_sync_global_from_voxel"):
			player._sync_global_from_voxel()
		if player.has_method("_snap_to_ground"):
			player._snap_to_ground()
	await _idle(cm)
	if insp:
		insp.pin_cell = Vector2i(int(round(mcol.x)), int(round(mcol.y)))
	for _f in 12:
		await process_frame
	_snaps["mite_f4"] = _LiveWorldQuery.inspect_cell(self, int(round(mcol.x)), int(round(mcol.y)))
	_note("observe", "mite id=%s col=%.1f,%.1f visible_mesh=%s sprite=%s voxel=%s hp=%.1f" % [
		str(mite.get("enemy_id")), mcol.x, mcol.y,
		str(_has_visible_child(mite, "MeshInstance3D")),
		str(_has_visible_child(mite, "Sprite3D")),
		str(mite.get_node_or_null("VoxelProp") != null),
		float(mite.get("health")),
	])
	await _shot("open_mite")

	# Fight with the existing sword path (aim at the mite like a mouse hover).
	if player:
		var world = get_first_node_in_group("world")
		_ActionTargeting.warp_mouse_to_column(player, world, mcol.x, mcol.y)
		for _aim in 6:
			await process_frame
		var weapon = player.get_node_or_null("WeaponController")
		if weapon and weapon.has_method("set_active_hotbar_index"):
			weapon.set_active_hotbar_index(0)
		var hp0 := float(mite.get("health"))
		var hits := 0
		var vfx_n := 0
		for _swing in 8:
			if weapon and weapon.has_method("_try_attack"):
				weapon._try_attack()
			hits += 1
			for _w2 in 8:
				await process_frame
			vfx_n = _count_combat_vfx()
			if not is_instance_valid(mite) or float(mite.get("health")) < hp0 - 0.01:
				break
		var hp1 := float(mite.get("health")) if is_instance_valid(mite) else 0.0
		_snaps["combat"] = {
			"swings": hits,
			"hp_before": hp0,
			"hp_after": hp1,
			"killed": not is_instance_valid(mite) or hp1 <= 0.0,
			"vfx": vfx_n,
			"player_hp": float(player.get("health")) if player else -1.0,
		}
		if hp1 >= hp0 - 0.01 and is_instance_valid(mite):
			_note("disagree", "sword swings did not reduce mite hp %.1f→%.1f vfx=%d" % [hp0, hp1, vfx_n])
		else:
			_note("observe", "combat hp %.1f→%.1f killed=%s vfx=%d" % [
				hp0, hp1, str(_snaps["combat"]["killed"]), vfx_n
			])
		await _shot("open_combat")

	_snaps["toasts"] = _toast_log
	_write_reports()
	_finish()


func _opening_snapshot(tag: String) -> Dictionary:
	_capture_toast()
	var player = get_first_node_in_group("player")
	var crystal = get_first_node_in_group("crystal_manager")
	var overlay = get_first_node_in_group("game_overlay")
	var spawner = get_first_node_in_group("crystal_enemy_spawner")
	var hud := ""
	if overlay:
		var h = overlay.get_node_or_null("GameHud")
		if h:
			hud = str(h.text)
	var pcol := Vector2i.ZERO
	if player and player.has_method("get_voxel_position"):
		var pv: Vector3 = player.get_voxel_position()
		pcol = Vector2i(floori(pv.x), floori(pv.z))
	var ocol := Vector2i.ZERO
	if crystal and crystal.has_method("get_origin_cell"):
		ocol = crystal.get_origin_cell()
	var dist := Vector2(pcol).distance_to(Vector2(ocol))
	var evo := {}
	if crystal and crystal.has_method("get_evolution"):
		var ev = crystal.get_evolution()
		if ev and ev.has_method("get_summary"):
			evo = ev.get_summary()
	var plants := 0
	var visuals := 0
	var feat_layer = get_first_node_in_group("feature_visual_layer")
	for dz in range(-8, 24):
		for dx in range(-8, 24):
			var feat: Dictionary = _FeatureRegistry.get_feature(pcol.x + dx, pcol.y + dz)
			if str(feat.get("plant_id", "")) != "":
				plants += 1
				if feat_layer and feat_layer.has_method("get_anchor_at") \
						and feat_layer.get_anchor_at(pcol.x + dx, pcol.y + dz) != null:
					visuals += 1
	var ents: Array = get_nodes_in_group("world_entity")
	var nearest_ent := 1.0e9
	for e in ents:
		if e is Node3D:
			var c: Vector2 = _WorldVisualCoords.column_from_node(e)
			nearest_ent = minf(nearest_ent, Vector2(pcol).distance_to(c))
	var in_start := false
	var cm = get_first_node_in_group("chunk_manager")
	if cm and cm.has_method("start_stream_coords"):
		var ck := Vector2i(
			int(floor(float(ocol.x) / float(_ChunkData.SIZE))),
			int(floor(float(ocol.y) / float(_ChunkData.SIZE)))
		)
		for v in cm.start_stream_coords():
			if v == ck:
				in_start = true
				break
	var grace := -1.0
	if spawner and "_grace_elapsed" in spawner:
		grace = float(spawner.get("_grace_elapsed"))
	return {
		"tag": tag,
		"hud": hud,
		"toast": _last_toast(),
		"player": [pcol.x, pcol.y],
		"crystal_origin": [ocol.x, ocol.y],
		"crystal_dist": dist,
		"crystal_in_start": in_start,
		"tiles": int(crystal.covered_cells) if crystal and "covered_cells" in crystal else 0,
		"power": float(crystal.power) if crystal and "power" in crystal else 0.0,
		"unlocked": evo.get("unlocked_enemies", []),
		"absorbed": evo.get("absorbed", {}),
		"enemies": get_nodes_in_group("crystal_enemy").size(),
		"entities": ents.size(),
		"nearest_entity": nearest_ent if nearest_ent < 1.0e8 else -1.0,
		"plants": plants,
		"plant_visuals": visuals,
		"grace_elapsed": grace,
		"phase": _phase_name(),
		"f3": _dump_f3(),
	}


func _phase_name() -> String:
	var gm = get_first_node_in_group("game_manager")
	if gm == null:
		return ""
	match int(gm.phase):
		0:
			return "MAZE"
		1:
			return "ASSAULT"
		2:
			return "VICTORY"
		_:
			return str(gm.phase)


func _bind_toast_watch() -> void:
	_capture_toast()


func _capture_toast() -> void:
	var overlay = get_first_node_in_group("game_overlay")
	if overlay == null:
		return
	var toast = overlay.get_node_or_null("ToastLabel")
	if toast == null or not bool(toast.visible):
		return
	var t := str(toast.text).strip_edges()
	if t.is_empty():
		return
	if _toast_log.is_empty() or _toast_log[_toast_log.size() - 1] != t:
		_toast_log.append(t)
		print("TOAST %s" % t)


func _last_toast() -> String:
	if _toast_log.is_empty():
		return ""
	return _toast_log[_toast_log.size() - 1]


func _has_visible_child(n: Node, type_name: String) -> bool:
	for c in n.get_children():
		if c.get_class() == type_name and c is Node3D and bool(c.visible):
			return true
	return false


func _count_combat_vfx() -> int:
	var vfx = get_first_node_in_group("combat_visual_feedback")
	if vfx == null:
		return 0
	var n := 0
	var bursts = vfx.get_node_or_null("Bursts")
	if bursts:
		n += bursts.get_child_count()
	var labels = vfx.get_node_or_null("DamageLabels")
	if labels:
		for c in labels.get_children():
			if c is CanvasItem or c is Node3D:
				if "visible" in c and bool(c.visible):
					n += 1
	return n


func _look_at(wx: int, wz: int) -> void:
	var player = get_first_node_in_group("player")
	if player == null:
		return
	player.voxel_position.x = float(wx) + 0.5
	player.voxel_position.z = float(wz) - 2.0
	if player.has_method("_sync_global_from_voxel"):
		player._sync_global_from_voxel()
	if player.has_method("_snap_to_ground"):
		player._snap_to_ground()


func _idle(cm) -> void:
	if cm and cm.has_method("await_rebuild_idle"):
		await cm.await_rebuild_idle(90)
	for _w in 4:
		await process_frame


func _wait_msec(ms: int, tag: String) -> void:
	var t0 := Time.get_ticks_msec()
	var last_log := t0
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame
		_capture_toast()
		if Time.get_ticks_msec() - last_log >= 8000:
			last_log = Time.get_ticks_msec()
			print("WAIT %s t=%dms enemies=%d tiles=%s" % [
				tag, Time.get_ticks_msec() - t0,
				get_nodes_in_group("crystal_enemy").size(),
				str(_opening_snapshot(tag).get("tiles", 0)),
			])


func _dump_f3() -> String:
	var panel = get_first_node_in_group("debug_panel")
	if panel == null:
		return ""
	if panel.has_method("set_overlay_visible"):
		panel.set_overlay_visible(true)
	if panel.has_method("refresh_now"):
		return str(panel.refresh_now())
	return ""


func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await process_frame
	if RenderingServer.has_method("force_draw"):
		RenderingServer.force_draw()
	var tex: Texture2D = root.get_texture()
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return
	var path := _scratch.path_join("%s.png" % name)
	img.save_png(path)
	_shots.append(path)
	print("SHOT %s" % path)


func _write_reports() -> void:
	var path := _scratch.path_join("combat_opening_audit.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"findings": _findings,
			"snaps": _snaps,
			"shots": _shots,
			"toasts": _toast_log,
			"failed": _failed,
		}, "\t"))
		f.close()
		print("WROTE %s" % path)
	var md := FileAccess.open(_scratch.path_join("combat_opening_audit.md"), FileAccess.WRITE)
	if md:
		var lines: PackedStringArray = PackedStringArray()
		lines.append("# Combat / opening audit")
		lines.append("fails=%d findings=%d" % [_failed, _findings.size()])
		for row in _findings:
			lines.append("- **%s**: %s" % [str(row.get("kind")), str(row.get("msg"))])
		lines.append("")
		lines.append("toasts: %s" % str(_toast_log))
		for s in _shots:
			lines.append("- %s" % s)
		md.store_string("\n".join(lines))
		md.close()


func _finish() -> void:
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "All combat opening audit OK")
	else:
		_ProbeExit.finish_tree(self, 1, "COMBAT OPENING AUDIT FAILED")
