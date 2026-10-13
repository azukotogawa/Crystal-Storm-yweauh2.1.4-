extends SceneTree
## Structural: ESC pause menu, F3 compact debug, F4 inspector, F11 bug report.

const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")

var _failed: int = 0


func _init() -> void:
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _fail(m: String) -> void:
	_failed += 1
	push_error(m)
	print("FAIL: %s" % m)


func _ok(m: String) -> void:
	print("OK %s" % m)


func _run() -> void:
	if not InputMap.has_action("debug_overlay_toggle"):
		_fail("missing debug_overlay_toggle")
	else:
		_ok("F3 action registered")
	if not InputMap.has_action("bug_report"):
		_fail("missing bug_report")
	else:
		_ok("F11 action registered")
	if not FileAccess.file_exists("res://ui/pause_menu.gd"):
		_fail("pause_menu.gd missing")
	else:
		_ok("pause_menu.gd present")
	var pause_src: String = (load("res://ui/pause_menu.gd") as GDScript).source_code
	for needle in ["Resume", "Settings", "Return to World Select", "Quit", "KEY_ESCAPE", "refresh_now"]:
		if needle not in pause_src:
			_fail("pause menu missing %s" % needle)
	if "volume" in pause_src.to_lower() and "unsupported" not in pause_src:
		pass
	_ok("pause menu actions present")
	var dbg_src: String = (load("res://ui/debug_panel.gd") as GDScript).source_code
	if "func toggle_overlay" not in dbg_src:
		_fail("debug panel missing toggle_overlay")
	else:
		_ok("debug panel toggle_overlay")
	if "Crystal Volume" in dbg_src and "F3  %d fps" not in dbg_src:
		_fail("debug panel still dumps full stat wall")
	else:
		_ok("debug panel compact F3 format")
	var insp := load("res://ui/live_world_inspector.gd")
	if insp == null:
		_fail("inspector missing")
	else:
		var layer := CanvasLayer.new()
		layer.set_script(insp)
		root.add_child(layer)
		await process_frame
		_ok("inspector instantiates")
	var pause_scr := load("res://ui/pause_menu.gd")
	var pl := CanvasLayer.new()
	pl.set_script(pause_scr)
	root.add_child(pl)
	await process_frame
	if not pl.has_method("open"):
		_fail("pause missing open")
	else:
		pl.open()
		if not _GameplayInput.pause_open:
			_fail("pause_open not set")
		else:
			_ok("pause blocks via GameplayInput")
		pl.close()
	if FileAccess.file_exists("res://world/validation_yard.gd"):
		_ok("validation yard present")
	else:
		_fail("validation yard missing")
	if _failed > 0:
		_ProbeExit.finish_tree(self, 1, "Pause/debug UI FAILED")
	else:
		_ProbeExit.finish_tree(self, 0, "All pause/debug UI tests OK")
