class_name DeveloperAssistant
extends Node

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
	var ack := "Sent to AI assistant (id=%s). Reply will appear here or in Output." % req_id
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


const _EnemySpawnRegistry = preload("res://entities/enemy_spawn_registry.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _ScenarioPresets = preload("res://helpers/scenario_presets.gd")
const DEBUG_TOGGLES := ["view", "overlay", "inspector", "collision_shapes", "voxel_boundaries", "chunk_boundaries", "mesh_bounds", "walkable_surface", "terrain_height", "feature_anchors", "water_cells", "crystal_cells", "stream_bake_state"]


func _handle_slash_command(text: String) -> String:
	var parts := text.split(" ", false)
	var cmd := parts[0].to_lower()
	match cmd:
		"/help":
			return (
				"Dev chat: type a message + Enter to send to AI. Slash commands:\n"
				+ "/help /status /seed /heal /god [on|off] /time [scale]\n"
				+ "/tp <x> <z>  /give <item> [n]  /spawn <entity> [n]  /kill [radius|all]\n"
				+ "/debug <toggle> [on|off]  /preset <low|medium|high>  /scenarios\n"
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
		"/give":
			if parts.size() < 2:
				return "Usage: /give <item> [n]"
			return _give(parts[1].to_lower(), parts[2] if parts.size() > 2 else "1")
		"/heal":
			return _heal()
		"/god":
			return _god(parts[1].to_lower() if parts.size() > 1 else "")
		"/time":
			return _time(parts[1] if parts.size() > 1 else "")
		"/spawn":
			if parts.size() < 2:
				return "Usage: /spawn <entity> [n]"
			return _spawn(parts[1].to_lower(), parts[2] if parts.size() > 2 else "1")
		"/kill":
			return _kill(parts[1].to_lower() if parts.size() > 1 else "32")
		"/seed":
			return _seed()
		"/scenarios":
			return "Scenarios: %s" % ", ".join(_ScenarioPresets.list_ids())
		"/debug":
			if parts.size() < 2:
				return "Usage: /debug <%s> [on|off]" % "|".join(DEBUG_TOGGLES)
			return _debug(parts[1].to_lower(), parts[2].to_lower() if parts.size() > 2 else "")
		_:
			return "Unknown command '%s'. Try /help" % cmd


func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player


func _give(item_id: String, sn: String) -> String:
	var player := _player()
	if player == null or player.inventory == null:
		return "Player inventory not found"
	if not _ItemTypes.is_valid(item_id):
		return "Unknown item '%s'. Try /help" % item_id
	if not sn.is_valid_int() or int(sn) <= 0:
		return "Usage: /give <item> [n]"
	var n := mini(int(sn), 999)
	var left: int = player.inventory.add_item(item_id, n)
	return "Gave %d %s%s" % [n - left, item_id, (" (%d did not fit)" % left) if left > 0 else ""]


func _heal() -> String:
	var player := _player()
	if player == null:
		return "Player not found"
	player.heal(player.max_health)
	return "Healed to %d/%d" % [int(player.health), int(player.max_health)]


func _god(arg: String) -> String:
	var player := _player()
	if player == null:
		return "Player not found"
	match arg:
		"on": player.dev_god = true
		"off": player.dev_god = false
		"": player.dev_god = not player.dev_god
		_: return "Usage: /god [on|off]"
	return "God mode %s" % ("ON" if player.dev_god else "OFF")


func _time(arg: String) -> String:
	if not arg.is_empty():
		if not arg.is_valid_float():
			return "Usage: /time [scale 0.1-4]"
		Engine.time_scale = clampf(float(arg), 0.1, 4.0)
	return "Time: %.1fs played, scale %.2f" % [Time.get_ticks_msec() / 1000.0, Engine.time_scale]


func _spawn(entity: String, sn: String) -> String:
	var player := _player()
	if player == null:
		return "Player not found"
	if not sn.is_valid_int() or int(sn) <= 0:
		return "Usage: /spawn <entity> [n]"
	var n := mini(int(sn), 20)
	var px := int(floor(player.voxel_position.x))
	var pz := int(floor(player.voxel_position.z))
	_EnemySpawnRegistry.ensure_builtins()
	var made := 0
	if _EnemySpawnRegistry.get_def(StringName(entity)) != null:
		var spawner = get_tree().get_first_node_in_group("crystal_enemy_spawner")
		if spawner == null:
			return "Enemy spawner not found"
		for i in n:
			if spawner.spawn_enemy_at_column(StringName(entity), px + 4 + (i % 5), pz + 4 + int(i / 5), Vector2i.ZERO, true):
				made += 1
	else:
		var em = get_tree().get_first_node_in_group("entity_manager")
		if em == null or not em.has_method("dev_spawn_animal"):
			return "Entity manager not found"
		for i in n:
			if not em.dev_spawn_animal(entity, px + 4 + (i % 5), pz + 4 + int(i / 5)):
				if i == 0:
					return "Unknown entity '%s'. Enemies: crystal_mite, thornling, ...; animals: deer, boar, rabbit, bird, fox, goat, duck" % entity
				break
			made += 1
	return "Spawned %d %s" % [made, entity]


func _kill(arg: String) -> String:
	var player := _player()
	if player == null:
		return "Player not found"
	var all := arg == "all"
	if not all and not arg.is_valid_float():
		return "Usage: /kill [radius|all]"
	var r := float(arg) if not all else 0.0
	var killed := 0
	for e in get_tree().get_nodes_in_group("crystal_enemy"):
		if not (e is Node3D) or not e.has_method("take_damage") or e.is_queued_for_deletion():
			continue
		if all or (e as Node3D).global_position.distance_to(player.global_position) <= r:
			e.take_damage(1.0e6, &"dev")
			killed += 1
	return "Killed %d enemies" % killed


func _seed() -> String:
	var world = get_tree().get_first_node_in_group("world")
	if world == null or not ("world_seed" in world):
		return "World not found"
	return "Seed %d" % int(world.world_seed)


func _debug(key: String, arg: String) -> String:
	if not key in DEBUG_TOGGLES:
		return "Unknown toggle '%s'. Options: %s" % [key, ", ".join(DEBUG_TOGGLES)]
	if not arg in ["", "on", "off"]:
		return "Usage: /debug <toggle> [on|off]"
	var coord = get_tree().get_first_node_in_group("dev_tools_coordinator")
	var insp = get_tree().get_first_node_in_group("live_world_inspector")
	var state := false
	match key:
		"view":
			if coord == null:
				return "Dev tools not found"
			state = coord.set_debug_view(not coord.is_debug_view_visible() if arg == "" else arg == "on")
		"overlay":
			if coord == null:
				return "Dev tools not found"
			if arg == "" or (arg == "on") != coord.is_debug_overlay_visible():
				coord.toggle_debug_overlay()
			state = coord.is_debug_overlay_visible()
		"inspector":
			if insp == null:
				return "Inspector not found"
			insp.panel_open = not insp.panel_open if arg == "" else arg == "on"
			state = insp.panel_open
		_:
			if insp == null:
				return "Inspector not found"
			state = not bool(insp.toggles.get(key, false)) if arg == "" else arg == "on"
			insp.set_toggle(key, state)
			if state and not insp.panel_open:
				insp.panel_open = true
	return "Debug %s %s" % [key, "ON" if state else "OFF"]

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