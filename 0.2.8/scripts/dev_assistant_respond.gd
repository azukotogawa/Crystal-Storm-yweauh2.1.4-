extends SceneTree
## External helper: read latest DevAssistant request and write a response line.
## Usage: godot --headless -s scripts/dev_assistant_respond.gd -- "Your reply text"


const _DeveloperAssistant = preload("res://systems/developer_assistant.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assistant := _DeveloperAssistant.new()
	var dir := assistant.get_assistant_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var req_path := dir.path_join(_DeveloperAssistant.REQUEST_LOG)
	if not FileAccess.file_exists(req_path):
		push_error("No requests at %s" % req_path)
		quit(1)
		return
	var last_req: Dictionary = {}
	for line in FileAccess.get_file_as_string(req_path).split("\n"):
		if line.strip_edges().is_empty():
			continue
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			last_req = parsed
	if last_req.is_empty():
		push_error("No valid request entries")
		quit(1)
		return
	var reply := _reply_text(last_req)
	assistant.write_external_response(str(last_req.get("id", "")), reply)
	print("OK wrote response for %s" % last_req.get("id", ""))
	quit(0)


func _reply_text(req: Dictionary) -> String:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		return " ".join(PackedStringArray(args))
	return "Acknowledged: %s" % str(req.get("message", ""))