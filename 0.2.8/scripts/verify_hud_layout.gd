extends SceneTree

const _Layout = preload("res://config/hud_layout.gd")
const _OverlayScene = preload("res://ui/game_overlay.tscn")
const _Hotbar = preload("res://ui/hotbar.gd")
const _Hud = preload("res://scripts/honest_bot/honest_showcase_hud.gd")
const _F3Scene = preload("res://scenes/f3_overlay.tscn")
const _Inventory = preload("res://inventory/inventory.gd")
const _SkillBar = preload("res://ui/skill_bar.gd")
const _Map = preload("res://ui/topographical_map.gd")
const _Chat = preload("res://ui/dev_chat_overlay.gd")
const _WorldManager = preload("res://systems/world_manager.gd")

const SIZES := [Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1366, 768), Vector2i(1920, 1080), Vector2i(2560, 1440)]

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	push_error("FAIL " + msg)
	_failed = true


func _run() -> void:
	var layout := _Layout.load_active()
	var view := Vector2(1280, 720)
	var chapter: Rect2 = layout.chapter_rect(view)
	var clock := Rect2(layout.clock_position(), Vector2(180, 36))
	var debug := Rect2(layout.debug_position(), Vector2(layout.debug_width, layout.debug_height))
	if not layout.misses_objective(chapter):
		_fail("chapter overlaps the crystal panel")
	if chapter.position.x < 360.0:
		_fail("chapter is not on the right")
	if not layout.misses_objective(clock):
		_fail("clock overlaps the crystal panel")
	if not layout.misses_objective(debug):
		_fail("debug readout overlaps the crystal panel")
	if layout.backing.a < 0.35 or layout.backing.a > 0.8:
		_fail("backing alpha is not a dark plate")
	root.size = Vector2i(1280, 720)
	var player := _player()
	root.add_child(player)
	var overlay: Control = _OverlayScene.instantiate()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)
	var bar := _Hotbar.new()
	root.add_child(bar)
	var hud = _Hud.new()
	root.add_child(hud)
	hud.set_readout("0:01.25", "movement")
	var f3 := _F3Scene.instantiate()
	root.add_child(f3)
	await process_frame
	await process_frame
	_check_live(layout, overlay, bar, hud, f3)
	_WorldManager.launched_from_catalog = true
	await _check_sizes(layout)
	if _failed:
		quit(1)
		return
	print("All hud layout tests OK")
	quit(0)


func _check_live(layout, overlay: Control, bar: Control, hud, f3) -> void:
	var plate := overlay.get_node_or_null("VitalsBacking") as Panel
	if plate == null:
		_fail("vitals backing missing")
	else:
		var style := plate.get_theme_stylebox("panel") as StyleBoxFlat
		if style == null or style.bg_color.a < 0.35:
			_fail("vitals backing is not a dark plate")
		if plate.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			_fail("vitals backing steals clicks")
	var hot := bar.get_node_or_null("HotbarBacking") as Panel
	if hot == null:
		_fail("hotbar backing missing")
	else:
		var hstyle := hot.get_theme_stylebox("panel") as StyleBoxFlat
		if hstyle == null or hstyle.bg_color.a < 0.35:
			_fail("hotbar backing is not a dark plate")
		if hot.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			_fail("hotbar backing steals clicks")
	var objective := overlay.get_node_or_null("ObjectiveHud") as Control
	if objective == null:
		_fail("objective panel missing")
	elif absf(objective.offset_right - layout.region(_Layout.view_of(overlay), "objective").end.x) > 0.5:
		_fail("objective panel ignores the layout")
	if f3.is_overlay_visible():
		_fail("debug text starts visible")
	var readout := f3.get_node_or_null("Readout") as Label
	if readout == null:
		_fail("f3 readout missing")
	elif readout.offset_left < layout.objective_rect().end.x:
		_fail("f3 readout overlaps the crystal panel")
	f3.set_overlay_visible(true)
	if not f3.is_overlay_visible():
		_fail("f3 did not show")
	f3.set_overlay_visible(false)
	if f3.is_overlay_visible():
		_fail("f3 stayed visible")
	var chapter := hud.get_child(1) as Label
	if chapter == null or chapter.anchor_right < 0.99:
		_fail("chapter label is not anchored to the right")
	elif chapter.offset_top < layout.objective_rect().position.y:
		_fail("chapter label sits on the crystal panel")
	var clock := hud.get_child(0) as Label
	if clock == null:
		_fail("clock missing")
	elif clock.position.y < layout.objective_rect().end.y:
		_fail("clock overlaps the crystal panel")


func _player() -> Node:
	var scr := GDScript.new()
	scr.source_code = """extends Node3D
signal health_changed(current: float, maximum: float)
var health: float = 72.0
var max_health: float = 100.0
var inventory = null
"""
	scr.reload()
	var player := Node3D.new()
	player.set_script(scr)
	player.add_to_group("player")
	player.inventory = _Inventory.new()
	return player


func _check_sizes(layout) -> void:
	var sub := SubViewport.new()
	sub.size = SIZES[0]
	sub.disable_3d = true
	root.add_child(sub)
	var overlay: Control = _OverlayScene.instantiate()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub.add_child(overlay)
	var bar := _Hotbar.new()
	sub.add_child(bar)
	var skills := _SkillBar.new()
	sub.add_child(skills)
	var map := _Map.new()
	sub.add_child(map)
	var chat := _Chat.new()
	sub.add_child(chat)
	chat.visible = true
	await process_frame
	overlay._ensure_leave_world_button()
	for size in SIZES:
		sub.size = size
		await process_frame
		await process_frame
		await process_frame
		var view := Vector2(size)
		var safe: Rect2 = layout.safe_area(view)
		var table: Dictionary = layout.regions(view)
		var live := {}
		live["objective"] = (overlay.get_node("ObjectiveHud") as Control).get_global_rect()
		live["vitals"] = (overlay.get_node("VitalsBacking") as Control).get_global_rect()
		live["hotbar"] = (bar.get_node("HotbarBacking") as Control).get_global_rect()
		live["skill_bar"] = skills.get_global_rect()
		live["minimap"] = map.get_minimap_screen_rect()
		live["leave_world"] = (overlay.get_node("LeaveWorld") as Control).get_global_rect()
		var chat_rect: Rect2 = chat.get_global_rect()
		live["chat"] = chat_rect
		for id in live:
			var rect: Rect2 = live[id]
			if not safe.grow(1.0).encloses(rect):
				_fail("%s %s at %s outside the safe area %s" % [id, rect, size, safe])
			var want: Rect2 = table[id]
			if id == "chat":
				if absf(rect.position.x - want.position.x) > 1.0 or absf(rect.end.y - want.end.y) > 1.0 or rect.end.x > want.end.x + 1.0:
					_fail("chat %s misses its region %s at %s" % [rect, want, size])
			elif rect.position.distance_to(want.position) > 1.5:
				_fail("%s %s misses its region %s at %s" % [id, rect, want, size])
		var ids := table.keys()
		for i in ids.size():
			var a: Rect2 = table[ids[i]]
			if not safe.grow(1.0).encloses(a):
				_fail("region %s %s outside the safe area at %s" % [ids[i], a, size])
			for j in range(i + 1, ids.size()):
				var b: Rect2 = table[ids[j]]
				if a.intersects(b):
					_fail("regions %s %s and %s %s overlap at %s" % [ids[i], a, ids[j], b, size])
		var live_ids := live.keys()
		for i in live_ids.size():
			for j in range(i + 1, live_ids.size()):
				if (live[live_ids[i]] as Rect2).intersects(live[live_ids[j]]):
					_fail("live %s %s and %s %s overlap at %s" % [live_ids[i], live[live_ids[i]], live_ids[j], live[live_ids[j]], size])
		var hot: Rect2 = live["hotbar"]
		if absf(hot.get_center().x - view.x * 0.5) > 1.0:
			_fail("hotbar not centered at %s (%s)" % [size, hot.get_center().x])
		print("OK hud %s regions" % size)
