extends SceneTree
## Crack stages, pooled break chips, place pop, and no node growth over 50 cycles.


const _BlockBreakFx = preload("res://systems/block_break_fx.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _PlayerSettings = preload("res://systems/player_settings.gd")

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _run() -> void:
	await process_frame
	var fx = _BlockBreakFx.new()
	root.add_child(fx)
	_check_stages(fx)
	_check_break_chips(fx)
	_check_place_pop(fx)
	_check_no_leak(fx)
	_check_crack_toggle(fx)
	_PlayerSettings.crack_overlay_enabled = true
	_PlayerSettings.hit_markers_enabled = true
	if _failed:
		quit(1)
	else:
		print("All block break place FX OK")
		quit(0)


func _check_stages(fx) -> void:
	var a := _BlockBreakFx.stage_for_progress(0.1)
	var b := _BlockBreakFx.stage_for_progress(0.5)
	var c := _BlockBreakFx.stage_for_progress(0.9)
	if not (a < b and b < c):
		_fail("crack stages did not advance (%s, %s, %s)" % [a, b, c])
		return
	if _BlockBreakFx.stage_for_progress(0.0) != 0 or _BlockBreakFx.stage_for_progress(1.0) != 4:
		_fail("crack stage endpoints are wrong")
		return
	if fx.set_progress(Vector3(1, 2, 3), 0.1) != a:
		_fail("set_progress 0.1 stage mismatch")
	if fx.set_progress(Vector3(1, 2, 3), 0.5) != b:
		_fail("set_progress 0.5 stage mismatch")
	if fx.set_progress(Vector3(1, 2, 3), 0.9) != c:
		_fail("set_progress 0.9 stage mismatch")
	var overlay: MeshInstance3D = fx.get_node("CrackOverlay")
	if not overlay.visible:
		_fail("crack overlay stayed hidden during a dig")
	elif overlay.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_fail("crack overlay casts a shadow")
	else:
		print("OK crack stages")


func _check_break_chips(fx) -> void:
	var tint := Color(0.15, 0.7, 0.25)
	if not fx.notify_break(Vector3(2, 1, 4), tint):
		_fail("break did not spawn pooled chips")
		return
	var pool = fx.get_node_or_null("BreakChips")
	var matched := false
	if pool:
		for child in pool.get_children():
			if child is CPUParticles3D and (child as CPUParticles3D).color.is_equal_approx(tint):
				matched = true
	if not matched:
		_fail("break chips did not keep the block tint")
	elif fx.break_count() < 1:
		_fail("break count did not move")
	else:
		print("OK break chips")


func _check_place_pop(fx) -> void:
	var vs: float = _WorldSettings.get_active().voxel_scale
	fx.notify_place(Vector3(4, 1, 3), Color(0.2, 0.8, 0.3))
	var start: float = float(fx.pop_scale())
	if absf(start - vs * 0.25) > 0.08:
		_fail("place pop started at %s, expected about %s" % [start, vs * 0.25])
		return
	fx.tick(0.04)
	var grown: float = float(fx.pop_scale())
	if grown <= start + 0.02:
		_fail("place pop did not scale up (%s -> %s)" % [start, grown])
		return
	for _i in 12:
		fx.tick(0.05)
	if fx.pop_scale() > 0.001:
		_fail("place pop did not hide")
	else:
		print("OK place pop")


func _check_no_leak(fx) -> void:
	var guard := 0
	while fx.emitter_count() < fx.emitter_cap() and guard < 40:
		if not fx.notify_break(Vector3(float(guard), 1.0, 0.0), Color(0.45, 0.32, 0.2)):
			break
		guard += 1
	if fx.emitter_count() < 1:
		_fail("chip pool never filled")
		return
	var before := _count_nodes(fx)
	for i in 50:
		fx.notify_break(Vector3(float(i), 2.0, 1.0), Color(0.5, 0.3, 0.2))
		fx.notify_place(Vector3(float(i), 2.0, 2.0), Color(0.3, 0.8, 0.3))
		fx.tick(0.02)
	var after := _count_nodes(fx)
	if after > before:
		_fail("break/place leaked nodes %d -> %d" % [before, after])
	elif fx.emitter_count() > fx.emitter_cap():
		_fail("chip pool grew past its cap")
	else:
		print("OK no node leak over 50 cycles (%d)" % after)


func _check_crack_toggle(fx) -> void:
	_PlayerSettings.crack_overlay_enabled = false
	fx.set_progress(Vector3(1, 2, 3), 0.8)
	var overlay: MeshInstance3D = fx.get_node("CrackOverlay")
	if overlay.visible:
		_fail("crack overlay ignored the settings toggle")
	elif fx.current_stage() < 2:
		_fail("hiding the overlay dropped the stage")
	else:
		_PlayerSettings.crack_overlay_enabled = true
		fx.set_progress(Vector3(1, 2, 3), 0.8)
		if not overlay.visible:
			_fail("crack overlay stayed hidden after the toggle")
		elif not fx.notify_break(Vector3(0, 1, 0), Color(0.4, 0.3, 0.2)):
			# The pool may already be full and still emitting, so a false return is not a leak.
			print("OK crack toggle (pool saturated)")
		else:
			print("OK crack toggle")


func _count_nodes(n: Node) -> int:
	var total := 1
	for child in n.get_children():
		total += _count_nodes(child)
	return total
