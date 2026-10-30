extends SceneTree

const _Gate = preload("res://helpers/debug_view_gate.gd")
const _Layer = preload("res://helpers/debug_view_layer.gd")

const _VIEWS: Array[String] = [
	"chunk_borders",
	"crystal_frontier",
	"collision",
	"perf_overlay",
]
const _ACTIONS: Array[String] = [
	"debug_view_chunk_borders",
	"debug_view_crystal_frontier",
	"debug_view_collision",
	"debug_view_perf",
]


class _ChunkStub extends Node:
	var chunks := {
		Vector2i(0, 0): true,
		Vector2i(1, 0): true,
	}

	func _ready() -> void:
		add_to_group("chunk_manager")


class _CrystalStub extends Node:
	func _ready() -> void:
		add_to_group("crystal_manager")

	func get_depth_cells_in_rect(_bounds: Rect2i) -> Dictionary:
		return {Vector2i(2, 2): 0.8}


class _ProbeStub extends Node:
	func _ready() -> void:
		add_to_group("voxel_floor_probe")

	func walkable_height_at(_wx: float, _wz: float) -> float:
		return 1.25


var _failed := false


func _init() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	print("FAIL %s" % message)


func _ok(message: String) -> void:
	print("OK %s" % message)


func _run() -> void:
	for path in ["res://helpers/debug_view_gate.gd", "res://helpers/debug_view_layer.gd"]:
		var scr: GDScript = load(path) as GDScript
		if scr == null or scr.reload() != OK:
			_fail("compile %s" % path)
		else:
			_ok("compile %s" % path)
	var main_src := FileAccess.get_file_as_string("res://main.gd")
	if "DebugViewLayer" not in main_src or "debug_view_layer.gd" not in main_src:
		_fail("main does not mount the debug view layer")
	else:
		_ok("main mounts debug view layer")
	if not _Gate.dev_flag_on_for(true, "1"):
		_ok("player build ignores dev flag")
	else:
		_fail("player build still enables dev views")
	if _Gate.dev_flag_on_for(false, "1") and not _Gate.dev_flag_on_for(false, "0") and not _Gate.dev_flag_on_for(false, ""):
		_ok("dev flag is explicit on only")
	else:
		_fail("dev flag predicate")
	_ok("debug build=%s" % str(OS.is_debug_build()))

	var chunks := _ChunkStub.new()
	var crystal := _CrystalStub.new()
	var player := Node3D.new()
	player.name = "ProbePlayer"
	player.add_to_group("player")
	player.position = Vector3(0, 2, 0)
	var probe := _ProbeStub.new()
	probe.name = "VoxelFloorProbe"
	player.add_child(probe)
	root.add_child(chunks)
	root.add_child(crystal)
	root.add_child(player)
	await process_frame

	_Gate.reset_player_build_override()
	OS.set_environment("CRYSTALSTORM_DEV_VIEWS", "0")
	var blocked := _spawn()
	await process_frame
	if blocked.dev_views_allowed() or blocked.is_processing_unhandled_input():
		_fail("views listen while dev flag is off")
	else:
		_ok("dev flag off disables input")
	for id in _VIEWS:
		if blocked.set_view(id, true) or blocked.is_view_on(id):
			_fail("set %s while dev flag off" % id)
	for action in _ACTIONS:
		blocked._unhandled_input(_pressed(action))
	blocked._unhandled_input(_pressed("debug_view_menu"))
	await process_frame
	if not blocked.all_views_off() or not blocked.render_idle() or blocked.menu_open() or blocked.debug_line_count() != 0:
		_fail("views active while dev flag off")
	else:
		_ok("views inactive while dev flag off")
	blocked.queue_free()
	await process_frame

	OS.set_environment("CRYSTALSTORM_DEV_VIEWS", "1")
	var layer := _spawn()
	await process_frame
	if not layer.dev_views_allowed():
		_fail("dev flag on should allow views in a debug build")
	elif not layer.render_idle() or not layer.all_views_off():
		_fail("views must start off even when the dev flag is on")
	else:
		_ok("views start off")
	var log := root.get_node_or_null("DevErrorLog")
	var errors_before := 0
	if log and log.has_method("enable"):
		log.enable()
		errors_before = int(log.entries)
	for i in _VIEWS.size():
		var id: String = _VIEWS[i]
		var action: String = _ACTIONS[i]
		layer._unhandled_input(_pressed(action))
		await process_frame
		if not layer.is_view_on(id):
			_fail("action did not enable %s" % id)
			continue
		if id == "perf_overlay":
			if not layer.perf_text().begins_with("PERF"):
				_fail("perf overlay text missing")
			else:
				_ok("perf overlay on")
		elif layer.debug_line_count() <= 0:
			_fail("%s drew no lines" % id)
		else:
			_ok("%s lines=%d" % [id, layer.debug_line_count()])
		layer._unhandled_input(_pressed(action))
		await process_frame
		if layer.is_view_on(id):
			_fail("action did not disable %s" % id)
		else:
			_ok("%s toggled off" % id)
	if not layer.render_idle():
		_fail("layer still drawing after every view off")
	else:
		_ok("idle after toggles, no debug mesh")
	layer._unhandled_input(_pressed("debug_view_menu"))
	await process_frame
	if not layer.menu_open():
		_fail("F8 did not open the dev menu")
	else:
		var check := layer.find_child("collision", true, false) as CheckBox
		if check == null:
			_fail("dev menu missing collision toggle")
		else:
			check.button_pressed = true
			await process_frame
			if layer.is_view_on("collision") and layer.debug_line_count() > 0:
				_ok("dev menu collision toggle")
			else:
				_fail("dev menu did not enable collision")
			check.button_pressed = false
			await process_frame
		layer._unhandled_input(_pressed("debug_view_menu"))
		await process_frame
		if layer.menu_open():
			_fail("F8 did not close the dev menu")
		else:
			_ok("dev menu closed")
	for id in _VIEWS:
		layer.set_view(id, true)
	await process_frame
	for _i in 8:
		await process_frame
	for id in _VIEWS:
		if not layer.is_view_on(id):
			_fail("combined set lost %s" % id)
	for id in _VIEWS:
		layer.set_view(id, false)
	await process_frame
	if layer.all_views_off() and layer.render_idle():
		_ok("combined toggles cleared")
	else:
		_fail("combined toggles left a view on")
	if log and int(log.entries) != errors_before:
		_fail("debug view errors: %s" % str(log.last_entry))
	else:
		_ok("no errors while toggling")
	layer.queue_free()
	await process_frame

	_Gate.force_player_build(true)
	OS.set_environment("CRYSTALSTORM_DEV_VIEWS", "1")
	if _Gate.dev_flag_on():
		_fail("player build override still sees the dev flag")
	var shipped := _spawn()
	await process_frame
	for id in _VIEWS:
		if shipped.set_view(id, true) or shipped.is_view_on(id):
			_fail("player build enabled %s" % id)
	shipped._unhandled_input(_pressed("debug_view_menu"))
	shipped._unhandled_input(_pressed("debug_view_chunk_borders"))
	await process_frame
	if shipped.dev_views_allowed() or not shipped.render_idle() or shipped.is_processing_unhandled_input():
		_fail("player build left debug views active")
	else:
		_ok("player build keeps every debug view inactive")
	_Gate.reset_player_build_override()
	OS.set_environment("CRYSTALSTORM_DEV_VIEWS", "0")

	if _failed:
		print("Debug view toggle tests FAILED")
		quit(1)
		return
	print("DEBUG VIEW TOGGLES OK")
	quit(0)


func _spawn():
	var layer = _Layer.new()
	layer.name = "DebugViewLayer"
	root.add_child(layer)
	return layer


func _pressed(action: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev
