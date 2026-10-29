extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")
const GI = preload("res://helpers/gameplay_input.gd")


func _timers(n: Node, acc: Array) -> void:
	if n is Timer and not n.is_stopped():
		acc[0] += n.time_left
	for ch in n.get_children():
		_timers(ch, acc)


func _snap(p) -> Dictionary:
	var ms: Array = []
	for m in get_nodes_in_group("crystal_enemy"):
		ms.append(m.global_position)
	var acc: Array = [0.0]
	_timers(root, acc)
	return {"p": p.global_position, "m": ms, "t": acc[0]}


func _run() -> void:
	var tag := OS.get_environment("P7_TAG")
	var p = await C.boot(self)
	GI.world_loading = false
	GI.modal_open = false
	var pc: Vector2i = C.pcol(p)
	for i in 4:
		var m = await C.spawn_mite(self, pc + Vector2i(4 + i, 2), false)
		if m:
			m.contact_damage = 0.0
	for _i in 30:
		await physics_frame
	var gm = get_first_node_in_group("game_manager")
	var ov = get_first_node_in_group("game_overlay")
	gm._set_lost("probe")
	await process_frame
	await physics_frame
	var a := _snap(p)
	Input.action_press("move_forward")
	for _i in 180:
		await physics_frame
	Input.action_release("move_forward")
	var b := _snap(p)
	var mmax := 0.0
	for i in mini(a.m.size(), b.m.size()):
		mmax = maxf(mmax, (a.m[i] - b.m[i]).length())
	var panel: Control = ov._panel
	var vp := panel.get_viewport_rect().size
	var c := panel.get_global_rect().get_center()
	var layer = panel.get_parent()
	var lnum: int = layer.layer if layer is CanvasLayer else -1
	var maxl := 0
	for n in root.find_children("*", "CanvasLayer", true, false):
		if n != layer:
			maxl = maxi(maxl, n.layer)
	print("P7_D tag=%s paused=%s frames=180 player_move=%.4f mite_move_max=%.4f mites=%d timer_delta=%.4f panel_visible=%s layer=%d other_max_layer=%d center_off=(%.1f,%.1f) vp=%s" % [tag, str(paused), (a.p - b.p).length(), mmax, a.m.size(), absf(a.t - b.t), str(panel.visible), lnum, maxl, c.x - vp.x * 0.5, c.y - vp.y * 0.5, str(vp)])
	quit()


func _init() -> void:
	call_deferred("_run")
