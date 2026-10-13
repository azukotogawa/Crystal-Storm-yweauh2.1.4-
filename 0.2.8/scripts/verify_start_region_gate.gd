extends SceneTree
## Start-region playable gate: status API + loading UI uses live occupancy.

const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

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
	var cm_script := load("res://chunks/chunk_manager.gd")
	if cm_script == null:
		_fail("chunk_manager missing")
		_finish()
		return
	var cm = cm_script.new()
	root.add_child(cm)
	if not cm.has_method("start_region_status") or not cm.has_method("is_start_region_ready"):
		_fail("start region API missing")
	else:
		var st: Dictionary = cm.start_region_status()
		for k in ["needed", "packages", "resident", "ready"]:
			if not st.has(k):
				_fail("start_region_status missing %s" % k)
		if int(st.get("needed", 0)) <= 0:
			_fail("start region needed must be > 0")
		else:
			_ok("start_region_status needed=%s resident=%s ready=%s" % [
				str(st.needed), str(st.resident), str(st.ready)
			])
		if bool(st.get("ready", true)) and int(st.get("resident", 0)) < int(st.get("needed", 1)):
			_fail("ready true while resident < needed")
		else:
			_ok("ready implies full occupancy")
	cm.queue_free()

	var src: String = (load("res://systems/composition_root.gd") as GDScript).source_code
	if "is_start_region_ready" not in src:
		_fail("composition_root must wait on is_start_region_ready")
	else:
		_ok("composition_root start-region gate present")
	if "chunks.size() >= 1" in src and "is_start_region_ready" not in src:
		_fail("composition_root still playable at one chunk")

	var load_src: String = (load("res://ui/loading_screen.gd") as GDScript).source_code
	if "start_region_status" not in load_src:
		_fail("loading screen must poll start_region_status")
	else:
		_ok("loading screen uses live start-region occupancy")
	if "0.40 + clampf(progress" in load_src:
		_fail("loading screen still maps full-world fill onto the start bar")
	else:
		_ok("loading screen does not use stale fill percent for start gate")

	_GameplayInput.set_world_loading(true)
	if not _GameplayInput.blocks_actions():
		_fail("world_loading must block gameplay actions")
	else:
		_ok("world_loading blocks actions")
	_GameplayInput.set_world_loading(false)

	_finish()


func _finish() -> void:
	if _failed > 0:
		_ProbeExit.finish_tree(self, 1, "Start region gate FAILED")
	else:
		_ProbeExit.finish_tree(self, 0, "All start region gate tests OK")
