extends SceneTree

const LOG_PATH := "user://logs/dev_errors.log"

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("OK " + msg)
	else:
		_failed += 1
		print("FAIL " + msg)


func _boom() -> void:
	var n: Object = null
	n.call("definitely_missing")


func _run() -> void:
	await process_frame
	var dev = root.get_node_or_null("DevErrorLog")
	_check(dev != null, "DevErrorLog autoload present")
	if dev == null:
		quit(1)
		return
	_check(not dev.enabled, "off by default")
	_check(not dev.is_processing(), "no per-frame work when off")
	_check(dev.get_child_count() == 0, "no toast nodes when off")
	if FileAccess.file_exists(LOG_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG_PATH))
	push_error("devlog probe while off")
	await process_frame
	_check(dev.entries == 0, "nothing captured while off")
	dev.enable()
	push_error("devlog probe 4242")
	await process_frame
	await process_frame
	_check(dev.entries >= 1 and "devlog probe 4242" in dev.last_entry, "push_error captured: %s" % dev.last_entry)
	var lbl = dev.find_child("DevErrorToast", true, false)
	_check(lbl != null and lbl.visible and "devlog probe 4242" in str(lbl.text), "toast shows the error")
	var before: int = dev.entries
	_boom()
	await process_frame
	await process_frame
	_check(dev.entries > before and "[SCRIPT]" in dev.last_entry, "script error captured: %s" % dev.last_entry)
	var text := FileAccess.get_file_as_string(LOG_PATH)
	_check("devlog probe 4242" in text, "rolling log has push_error line")
	_check("[SCRIPT]" in text, "rolling log has script error line")
	_check(not ("devlog probe while off" in text), "rolling log skips errors from before enable")
	dev.disable()
	_check(not dev.enabled and not dev.is_processing(), "disable restores zero-cost state")
	print("LOG_PATH " + ProjectSettings.globalize_path(LOG_PATH))
	if _failed == 0:
		print("All dev error log tests OK")
		quit(0)
	else:
		quit(1)
