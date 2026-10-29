extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")
const _GI = preload("res://helpers/gameplay_input.gd")

var p
var w


func _init() -> void:
	call_deferred("_run")


func _act(name: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _tap_action(name: String) -> void:
	_act(name, true)
	for _f in 2:
		await process_frame
	_act(name, false)
	for _f in 3:
		await process_frame


func _click(pos: Vector2, button: MouseButton) -> float:
	for _f in 30:
		await physics_frame
	w._cooldown_timer = 0.0
	var n0: int = w.world_clicks
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	Input.parse_input_event(mv)
	await process_frame
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = pos
	ev.global_position = pos
	ev.pressed = true
	Input.parse_input_event(ev)
	var peak := 0.0
	for _f in 6:
		await process_frame
		peak = maxf(peak, w._cooldown_timer)
	if OS.get_environment("P7_DBG") != "":
		print("P7_CLICKDBG btn=%d attack=%s place=%s ev=%s item=%s" % [button, Input.is_action_pressed("attack"), Input.is_action_pressed("build_place"), InputMap.action_get_events("attack"), w._active_item_id()])
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	for _f in 3:
		await process_frame
		peak = maxf(peak, w._cooldown_timer)
	return float(w.world_clicks - n0)


func _keys() -> Dictionary:
	var start: Vector3 = p.global_position
	_act("move_forward", true)
	_act("move_right", true)
	for _f in 20:
		await physics_frame
	_act("move_forward", false)
	_act("move_right", false)
	var moved: float = Vector2(p.global_position.x - start.x, p.global_position.z - start.z).length()
	var y0: float = p.global_position.y
	var top := y0
	_act("jump", true)
	for _f in 12:
		await physics_frame
		top = maxf(top, p.global_position.y)
	_act("jump", false)
	for _f in 40:
		await physics_frame
	return {"moved": moved, "jump": top - y0}


func _probe_all(tag: String) -> Dictionary:
	var vp: Vector2 = root.get_visible_rect().size
	var res := {}
	var slots := {"sword": 0, "pick": 1, "place": 2}
	for k in slots:
		w.select_hotbar(int(slots[k]))
		await process_frame
		var btn: MouseButton = MOUSE_BUTTON_RIGHT if k == "place" else MOUSE_BUTTON_LEFT
		var c1: float = await _click(vp * 0.5 + Vector2(90, 0), btn)
		var c2: float = await _click(Vector2(40, vp.y - 40), btn)
		res[k] = int(c1 > 0.0) + int(c2 > 0.0)
	w.select_hotbar(0)
	var kk: Dictionary = await _keys()
	res["move"] = int(kk.moved > 0.3)
	res["jump"] = int(kk.jump > 0.3)
	print("P7_PANELDBG %s %s moved=%.2f jump=%.2f" % [tag, res, kk.moved, kk.jump])
	return res


func _open(kind: String) -> void:
	match kind:
		"inventory":
			await _tap_action("inventory_toggle")
		"how_to_play":
			TutorialOverlay.open(self, true)
		"relic":
			RelicChoicePanel.open(self, null, ["crystal_ward", "flow_anchor", "mason_glove"], "probe")
		"pause":
			get_first_node_in_group("pause_menu").open()
		"skills":
			get_first_node_in_group("skill_tree").open()
		"map":
			get_first_node_in_group("topographical_map")._set_fullscreen_open(true)
	for _f in 5:
		await process_frame


func _close(kind: String) -> void:
	match kind:
		"inventory":
			await _tap_action("inventory_toggle")
		"how_to_play":
			TutorialOverlay.dismiss()
		"relic":
			RelicChoicePanel._open._close()
		"pause":
			get_first_node_in_group("pause_menu").close()
		"skills":
			get_first_node_in_group("skill_tree").close()
		"map":
			get_first_node_in_group("topographical_map")._set_fullscreen_open(false)
	for _f in 10:
		await process_frame


func _run() -> void:
	p = await C.boot(self)
	p.health = 100000.0
	w = C.weapon(p)
	w.inventory.set_slot(0, "wooden_sword", 1)
	w.inventory.set_slot(1, "stone_pick", 1)
	w.inventory.set_slot(2, "stone", 50)
	TutorialOverlay.dismiss()
	await _probe_all("warmup")
	var base: Dictionary = await _probe_all("baseline")
	var leaks := 0
	var unrestored := 0
	var line := " baseline=%s" % base
	for kind in ["inventory", "how_to_play", "relic", "pause", "skills", "map"]:
		await _open(kind)
		var o: Dictionary = await _probe_all(kind + "_open")
		await _close(kind)
		var c: Dictionary = await _probe_all(kind + "_closed")
		var leak := 0
		var lost := 0
		for k in o:
			leak += int(o[k])
			if int(base[k]) > 0 and int(c[k]) == 0:
				lost += 1
		leaks += leak
		unrestored += lost
		line += " %s:leak=%d lost=%d" % [kind, leak, lost]
	var ok: bool = leaks == 0 and unrestored == 0 and int(base.sword) > 0 and int(base.place) > 0
	print("P7_PANELS tag=%s%s %s" % [OS.get_environment("P7_TAG"), line, "OK" if ok else "FAIL"])
	quit()