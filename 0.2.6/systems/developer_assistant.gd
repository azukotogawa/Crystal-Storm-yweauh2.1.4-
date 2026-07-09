class_name DeveloperAssistant
extends Node
## In-game dev chat backend: local slash commands + file bridge for external AI (Cursor/Grok).

signal response_ready(text: String)

const REQUEST_LOG := "requests.jsonl"
const RESPONSE_LOG := "responses.jsonl"

var _request_seq: int = 0
var _pending_id: String = ""
var _pending_since_msec: int = 0
var _poll_timer: float = 0.0


func _enter_tree() -> void:
	add_to_group("developer_assistant")
	_ensure_assistant_dir()


func _process(delta: float) -> void:
	if _pending_id.is_empty():
		return
	_poll_timer -= delta
	if _poll_timer > 0.0:
		return
	_poll_timer = 0.35
	var reply := _poll_external_response(_pending_id)
	if reply.is_empty():
		if Time.get_ticks_msec() - _pending_since_msec > 120_000:
			_finish_pending("Assistant timeout — check Godot Output or %s" % get_assistant_dir())
		return
	_finish_pending(reply)


func get_assistant_dir() -> String:
	var env := OS.get_environment("CRYSTALSTORM_DEV_ASSISTANT_DIR").strip_edges()
	if not env.is_empty():
		return env
	return ProjectSettings.globalize_path("user://dev_assistant")


func send_message(text: String) -> String:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return ""
	if trimmed.begins_with("/"):
		var local := _handle_slash_command(trimmed)
		print("[DevAssistant] %s" % local)
		response_ready.emit(local)
		return local
	return _forward_to_assistant(trimmed)


func _finish_pending(text: String) -> void:
	_pending_id = ""
	print("[DevAssistant] %s" % text)
	response_ready.emit(text)


func _forward_to_assistant(message: String) -> String:
	_request_seq += 1
	var req_id := "req_%d_%d" % [Time.get_ticks_msec(), _request_seq]
	var context := _capture_context()
	var payload := {
		"id": req_id,
		"timestamp_ms": Time.get_ticks_msec(),
		"message": message,
		"context": context,
	}
	_append_json_line(get_assistant_dir().path_join(REQUEST_LOG), payload)
	_pending_id = req_id
	_pending_since_msec = Time.get_ticks_msec()
	var ack := "Sent to debug (id=%s)." % req_id
	print("[DevAssistant] >> %s" % message)
	print("[DevAssistant] request logged: %s" % get_assistant_dir().path_join(REQUEST_LOG))
	response_ready.emit(ack)
	return ack


func _poll_external_response(req_id: String) -> String:
	var path := get_assistant_dir().path_join(RESPONSE_LOG)
	if not FileAccess.file_exists(path):
		return ""
	var text := FileAccess.get_file_as_string(path)
	for line in text.split("\n"):
		for payload in _parse_jsonl_fragments(line):
			if str(payload.get("id", "")) == req_id:
				return str(payload.get("response", ""))
	return ""


static func _parse_jsonl_fragments(line: String) -> Array:
	var trimmed := line.strip_edges()
	if trimmed.is_empty():
		return []
	var candidates: PackedStringArray = PackedStringArray()
	if "}{" in trimmed:
		var parts: PackedStringArray = trimmed.split("}{")
		for i in parts.size():
			var chunk: String = parts[i]
			if i > 0:
				chunk = "{" + chunk
			if i < parts.size() - 1:
				chunk = chunk + "}"
			candidates.append(chunk)
	else:
		candidates.append(trimmed)
	var out: Array = []
	var json := JSON.new()
	for chunk in candidates:
		if json.parse(chunk) == OK and json.data is Dictionary:
			out.append(json.data)
	return out


func write_external_response(req_id: String, response: String) -> void:
	var payload := {
		"id": req_id,
		"timestamp_ms": Time.get_ticks_msec(),
		"response": response,
	}
	_append_json_line(get_assistant_dir().path_join(RESPONSE_LOG), payload)


func _handle_slash_command(text: String) -> String:
	var parts := text.split(" ", false)
	var cmd := parts[0].to_lower()
	match cmd:
		"/help":
			return (
				"Dev chat: type a message + Enter to send to debug log. Slash commands:\n"
				+ "/help /status /preset <low|medium|high> /tp <x> <z>\n"
				+ "Logs: %s" % get_assistant_dir()
			)
		"/status":
			return _status_line()
		"/preset":
			if parts.size() < 2:
				return "Usage: /preset low|medium|high"
			return _apply_preset(parts[1].to_lower())
		"/tp":
			if parts.size() < 3:
				return "Usage: /tp <world_x> <world_z>"
			return _teleport_player(parts[1], parts[2])
		_:
			return "Unknown command '%s'. Try /help" % cmd


func _status_line() -> String:
	var player: Node = get_tree().get_first_node_in_group("player")
	var chunk_manager: ChunkManager = get_tree().get_first_node_in_group("chunk_manager")
	var perf = get_tree().get_first_node_in_group("performance_service")
	var chunks := 0
	if chunk_manager and "chunks" in chunk_manager:
		chunks = chunk_manager.chunks.size()
	var pos := Vector3.ZERO
	if player and "voxel_position" in player:
		pos = player.voxel_position
	var preset := "?"
	if perf and "quality" in perf and perf.quality:
		preset = str(int(perf.quality.preset))
	return "pos=(%.1f,%.1f,%.1f) chunks=%d preset=%s fps=%d" % [
		pos.x, pos.y, pos.z, chunks, preset, Engine.get_frames_per_second()
	]


func _apply_preset(name: String) -> String:
	var perf = get_tree().get_first_node_in_group("performance_service")
	if perf == null or not perf.has_method("apply_preset"):
		return "PerformanceService unavailable"
	var preset_id := -1
	match name:
		"low": preset_id = 0
		"medium": preset_id = 1
		"high": preset_id = 2
		"safe": preset_id = 3
		_:
			return "Unknown preset '%s'" % name
	perf.apply_preset(preset_id)
	return "Applied preset=%s" % name


func _teleport_player(sx: String, sz: String) -> String:
	if not sx.is_valid_float() or not sz.is_valid_float():
		return "Invalid coordinates"
	var player: Player = get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return "Player not found"
	var wx := float(sx)
	var wz := float(sz)
	player.voxel_position.x = wx + 0.5
	player.voxel_position.z = wz + 0.5
	if player.has_method("_sync_global_from_voxel"):
		player.call("_sync_global_from_voxel")
	return "Teleported to (%.1f, %.1f)" % [wx, wz]


func _capture_context() -> Dictionary:
	var player: Node = get_tree().get_first_node_in_group("player")
	var chunk_manager: ChunkManager = get_tree().get_first_node_in_group("chunk_manager")
	var out := {
		"scene": "main",
		"fps": Engine.get_frames_per_second(),
	}
	if player and "voxel_position" in player:
		out["player_voxel"] = str(player.voxel_position)
	if chunk_manager and "chunks" in chunk_manager:
		out["chunks_loaded"] = chunk_manager.chunks.size()
	return out


func _ensure_assistant_dir() -> void:
	var dir := get_assistant_dir()
	DirAccess.make_dir_recursive_absolute(dir)


func _append_json_line(path: String, payload: Dictionary) -> void:
	_ensure_assistant_dir()
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("DevAssistant could not write %s" % path)
		return
	if f.get_length() > 0:
		f.seek_end()
		f.store_string("\n")
	f.store_string(JSON.stringify(payload))
	f.close()
