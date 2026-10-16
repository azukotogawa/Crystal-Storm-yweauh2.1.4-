extends Node

const EVENT_CAP := 2048
const MERGE_WINDOW_MSEC := 1000
const FLUSH_GAP_MSEC := 250
const LEVEL_UP_CAP := 256
const EVIDENCE_ROOT := "D:/ARCHIVE/CrystalStorm/verify-evidence"

var session_id: String = ""
var events: Array[Dictionary] = []

var _player_deaths: int = 0
var _damage_taken: float = 0.0
var _dealt: Dictionary = {}
var _bound: Dictionary = {}
var _open_fights: Dictionary = {}
var _ttk_kills: Dictionary = {}
var _ttk_total: Dictionary = {}
var _ttk_min: Dictionary = {}
var _ttk_max: Dictionary = {}
var _xp_gained: int = 0
var _xp_level: int = 1
var _level_ups: Array[Dictionary] = []
var _session_start_msec: int = 0
var _session_start_unix: float = 0.0
var _last_flush_msec: int = -100000
var _flush_pending: bool = false


func _ready() -> void:
	begin_session()
	var tree := get_tree()
	if tree == null:
		return
	tree.node_added.connect(_on_node_added)
	call_deferred("_scan_tree")


func _process(_delta: float) -> void:
	if not _flush_pending:
		return
	if Time.get_ticks_msec() - _last_flush_msec >= FLUSH_GAP_MSEC:
		flush()


func _exit_tree() -> void:
	flush()


func begin_session() -> void:
	if session_id != "":
		flush()
	session_id = _make_session_id()
	events.clear()
	_player_deaths = 0
	_damage_taken = 0.0
	_dealt.clear()
	_open_fights.clear()
	_ttk_kills.clear()
	_ttk_total.clear()
	_ttk_min.clear()
	_ttk_max.clear()
	_xp_gained = 0
	_level_ups.clear()
	_session_start_msec = Time.get_ticks_msec()
	_session_start_unix = Time.get_unix_time_from_system()
	_flush_pending = false
	_sync_level()
	flush()


func player_deaths() -> int:
	return _player_deaths


func damage_taken_total() -> float:
	return _damage_taken


func damage_dealt(source: StringName) -> float:
	return float(_dealt.get(_source_key(source), 0.0))


func time_to_kill(kind: String) -> Dictionary:
	if not _ttk_kills.has(kind):
		return ttk_summary(0, 0, 0, 0)
	return ttk_summary(
		int(_ttk_kills[kind]),
		int(_ttk_total[kind]),
		int(_ttk_min[kind]),
		int(_ttk_max[kind])
	)


func xp_gained_total() -> int:
	return _xp_gained


func xp_snapshot() -> Dictionary:
	var elapsed := _elapsed_msec()
	return {
		"gained": _xp_gained,
		"per_minute": xp_per_minute(_xp_gained, elapsed),
		"elapsed_msec": elapsed,
		"level": _xp_level,
		"level_ups": _level_ups.duplicate(true),
	}


func snapshot() -> Dictionary:
	return {
		"session_id": session_id,
		"started_unix": _session_start_unix,
		"elapsed_msec": _elapsed_msec(),
		"player_deaths": _player_deaths,
		"damage_taken": _damage_taken,
		"damage_dealt_by_source": _dealt.duplicate(),
		"time_to_kill": _time_to_kill_map(),
		"xp": xp_snapshot(),
		"events": events.duplicate(true),
	}


func user_json_path() -> String:
	return "user://telemetry/%s.json" % _file_stem()


func evidence_json_path() -> String:
	var run := _evidence_run_dir()
	if run == "":
		return ""
	return "%s/telemetry/%s.json" % [run, _file_stem()]


func flush() -> String:
	_flush_pending = false
	_last_flush_msec = Time.get_ticks_msec()
	if session_id == "":
		return ""
	var body := JSON.stringify(snapshot(), "\t")
	var user_path := _write_user(body)
	var evidence_path := _write_evidence(body)
	if evidence_path != "":
		return evidence_path
	return user_path


static func xp_per_minute(gained: int, elapsed_msec: int) -> float:
	if gained <= 0 or elapsed_msec <= 0:
		return 0.0
	return float(gained) * 60000.0 / float(elapsed_msec)


static func ttk_summary(kills: int, total_msec: int, min_msec: int, max_msec: int) -> Dictionary:
	var mean := 0.0
	if kills > 0:
		mean = float(total_msec) / float(kills)
	return {
		"kills": kills,
		"total_msec": total_msec,
		"mean_msec": mean,
		"min_msec": min_msec,
		"max_msec": max_msec,
	}


func _scan_tree() -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	_walk(tree.root)


func _walk(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_walk(child)


func _on_node_added(node: Node) -> void:
	if _interesting(node):
		call_deferred("_try_bind", node)


func _interesting(node: Node) -> bool:
	if node.is_in_group("player") or node.is_in_group("world_entity") or node.is_in_group("crystal_enemy"):
		return true
	if node.is_in_group("progression_service"):
		return true
	return node.has_signal("damage_taken") or node.has_signal("combat_damaged") or node.has_signal("xp_gained")


func _try_bind(node: Node) -> void:
	if not is_instance_valid(node):
		return
	var id := node.get_instance_id()
	if _bound.has(id):
		return
	var hooked := false
	if node.is_in_group("progression_service") or node.has_signal("xp_gained"):
		hooked = _bind_progression(node) or hooked
	if node.is_in_group("player"):
		hooked = _bind_player(node) or hooked
	else:
		hooked = _bind_combatant(node) or hooked
	if not hooked:
		return
	_bound[id] = true
	if not node.tree_exiting.is_connected(_forget):
		node.tree_exiting.connect(_forget.bind(id))


func _bind_player(node: Node) -> bool:
	var hooked := false
	if node.has_signal("damage_taken") and not node.damage_taken.is_connected(_on_damage_taken):
		node.damage_taken.connect(_on_damage_taken)
		hooked = true
	if node.has_signal("died") and not node.died.is_connected(_on_player_died):
		node.died.connect(_on_player_died)
		hooked = true
	return hooked


func _bind_combatant(node: Node) -> bool:
	var hooked := false
	if node.has_signal("combat_damaged") and not node.combat_damaged.is_connected(_on_damage_dealt.bind(node)):
		node.combat_damaged.connect(_on_damage_dealt.bind(node))
		hooked = true
	if node.is_in_group("crystal_enemy") and node.has_signal("killed") and not node.killed.is_connected(_on_enemy_killed.bind(node)):
		node.killed.connect(_on_enemy_killed.bind(node))
		hooked = true
	elif node.is_in_group("world_entity") and node.has_signal("died") and not node.died.is_connected(_on_entity_died):
		node.died.connect(_on_entity_died)
		hooked = true
	return hooked


func _bind_progression(node: Node) -> bool:
	var hooked := false
	if node.has_signal("xp_gained") and not node.xp_gained.is_connected(_on_xp_gained):
		node.xp_gained.connect(_on_xp_gained)
		hooked = true
	if node.has_signal("level_up") and not node.level_up.is_connected(_on_level_up):
		node.level_up.connect(_on_level_up)
		hooked = true
	if hooked:
		_sync_level()
	return hooked


func _forget(id: int) -> void:
	_bound.erase(id)
	_open_fights.erase(id)


func _on_damage_taken(amount: float, source: StringName) -> void:
	if amount <= 0.0:
		return
	var key := _source_key(source)
	_damage_taken += amount
	_note_damage("damage_taken", amount, key, "player")


func _on_damage_dealt(amount: float, _remaining: float, source: StringName, combatant: Node = null) -> void:
	if amount <= 0.0:
		return
	var key := _source_key(source)
	_dealt[key] = float(_dealt.get(key, 0.0)) + amount
	_note_damage("damage_dealt", amount, key, "")
	if is_instance_valid(combatant) and not combatant.is_in_group("player"):
		_stamp_fight(combatant)


func _on_player_died() -> void:
	_push_death("player")


func _on_enemy_killed(enemy_id: StringName, _world_pos: Vector2i, _player_killed: bool, combatant: Node = null) -> void:
	var actor := String(enemy_id)
	if actor == "":
		actor = "enemy"
	_finish_fight(combatant, actor)
	_push_death(actor)


func _on_entity_died(entity: Node, _world_pos: Vector2i) -> void:
	var actor := "entity"
	if is_instance_valid(entity) and "entity_kind" in entity:
		actor = String(entity.entity_kind)
		if actor == "":
			actor = "entity"
	_finish_fight(entity, actor)
	_push_death(actor)


func _on_xp_gained(amount: int, _xp_now: int) -> void:
	if amount <= 0:
		return
	_xp_gained += amount
	_note_damage("xp", float(amount), "xp", "player")
	_touch(true)


func _on_level_up(level: int) -> void:
	var reached := maxi(level, 1)
	_xp_level = reached
	var now := Time.get_ticks_msec()
	_level_ups.append({
		"level": reached,
		"t_unix": Time.get_unix_time_from_system(),
		"t_msec": now,
		"elapsed_msec": _elapsed_msec(),
	})
	while _level_ups.size() > LEVEL_UP_CAP:
		_level_ups.pop_front()
	events.append(_row("level_up", "xp", "player", float(reached), Time.get_unix_time_from_system(), now))
	_trim()
	_touch(true)


func _stamp_fight(node: Node) -> void:
	var id := node.get_instance_id()
	if _open_fights.has(id):
		return
	_open_fights[id] = Time.get_ticks_msec()


func _finish_fight(node: Node, fallback_kind: String) -> void:
	var now := Time.get_ticks_msec()
	var start := now
	var kind := fallback_kind
	if is_instance_valid(node):
		var id := node.get_instance_id()
		if _open_fights.has(id):
			start = int(_open_fights[id])
			_open_fights.erase(id)
		if kind == "":
			kind = _kind_of(node)
	if kind == "":
		return
	_add_ttk(kind, maxi(now - start, 0))


func _kind_of(node: Node) -> String:
	if "enemy_id" in node:
		var enemy := String(node.enemy_id)
		if enemy != "":
			return enemy
	if "entity_kind" in node:
		var kind := String(node.entity_kind)
		if kind != "":
			return kind
	if node.is_in_group("crystal_enemy"):
		return "crystal_enemy"
	if node.is_in_group("world_entity"):
		return "world_entity"
	return ""


func _add_ttk(kind: String, elapsed_msec: int) -> void:
	var spent := maxi(elapsed_msec, 0)
	var kills := int(_ttk_kills.get(kind, 0)) + 1
	var total := int(_ttk_total.get(kind, 0)) + spent
	var lo := spent
	var hi := spent
	if _ttk_min.has(kind):
		lo = mini(int(_ttk_min[kind]), spent)
		hi = maxi(int(_ttk_max[kind]), spent)
	_ttk_kills[kind] = kills
	_ttk_total[kind] = total
	_ttk_min[kind] = lo
	_ttk_max[kind] = hi
	var now := Time.get_ticks_msec()
	events.append(_row("time_to_kill", kind, kind, float(spent) / 1000.0, Time.get_unix_time_from_system(), now))
	_trim()
	_touch(true)


func _push_death(actor: String) -> void:
	if actor == "player":
		_player_deaths += 1
	var now := Time.get_ticks_msec()
	events.append(_row("death", "", actor, 0.0, Time.get_unix_time_from_system(), now))
	_trim()
	_touch(true)


func _note_damage(kind: String, amount: float, source: String, actor: String) -> void:
	var now := Time.get_ticks_msec()
	var unix := Time.get_unix_time_from_system()
	if not events.is_empty():
		var last_i := events.size() - 1
		var last: Dictionary = events[last_i]
		if str(last.get("kind", "")) == kind and str(last.get("source", "")) == source and str(last.get("actor", "")) == actor:
			if now - int(last.get("t_msec", 0)) <= MERGE_WINDOW_MSEC:
				last["amount"] = float(last.get("amount", 0.0)) + amount
				last["t_unix_end"] = unix
				last["t_msec"] = now
				events[last_i] = last
				_touch(false)
				return
	events.append(_row(kind, source, actor, amount, unix, now))
	_trim()
	_touch(false)


func _row(kind: String, source: String, actor: String, amount: float, unix: float, msec: int) -> Dictionary:
	return {
		"session_id": session_id,
		"kind": kind,
		"source": source,
		"actor": actor,
		"amount": amount,
		"t_unix": unix,
		"t_unix_end": unix,
		"t_msec": msec,
	}


func _trim() -> void:
	while events.size() > EVENT_CAP:
		events.pop_front()


func _touch(force: bool) -> void:
	var now := Time.get_ticks_msec()
	if force or now - _last_flush_msec >= FLUSH_GAP_MSEC:
		flush()
		return
	_flush_pending = true


func _sync_level() -> void:
	_xp_level = 1
	var tree := get_tree()
	if tree == null:
		return
	var node := tree.get_first_node_in_group("progression_service")
	if node != null and "level" in node:
		_xp_level = maxi(int(node.level), 1)


func _elapsed_msec() -> int:
	return maxi(Time.get_ticks_msec() - _session_start_msec, 0)


func _time_to_kill_map() -> Dictionary:
	var out := {}
	for kind in _ttk_kills.keys():
		out[str(kind)] = time_to_kill(str(kind))
	return out


func _source_key(source: StringName) -> String:
	if source == &"":
		return "unknown"
	return String(source)


func _make_session_id() -> String:
	return "%d-%08x" % [int(Time.get_unix_time_from_system()), randi()]


func _file_stem() -> String:
	return _safe_token(session_id, "session")


func _write_user(body: String) -> String:
	var path := user_json_path()
	if not _ensure_dir(path):
		push_warning("telemetry mkdir %s" % path)
		return ""
	if not _write_text(path, body):
		push_warning("telemetry write %s" % path)
		return ""
	return path


func _write_evidence(body: String) -> String:
	var path := evidence_json_path()
	if path == "":
		return ""
	if not _ensure_dir(path):
		push_warning("telemetry evidence mkdir %s" % path)
		return ""
	if not _write_text(path, body):
		push_warning("telemetry evidence write %s" % path)
		return ""
	return path


func _ensure_dir(path: String) -> bool:
	var folder := path.get_base_dir()
	if folder.begins_with("user://"):
		folder = ProjectSettings.globalize_path(folder)
	return DirAccess.make_dir_recursive_absolute(folder) == OK


func _write_text(path: String, body: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(body)
	file.close()
	return true


func _evidence_run_dir() -> String:
	var explicit := OS.get_environment("CRYSTALSTORM_EVIDENCE").strip_edges().replace("\\", "/")
	while explicit.ends_with("/"):
		explicit = explicit.substr(0, explicit.length() - 1)
	if not explicit.is_empty():
		return explicit
	var run_id := OS.get_environment("CRYSTALSTORM_RUN_ID").strip_edges()
	if run_id.is_empty():
		return ""
	var token := _safe_token(run_id, "")
	if token.is_empty():
		return ""
	return "%s/%s" % [EVIDENCE_ROOT, token]


func _safe_token(raw: String, fallback: String) -> String:
	var out := ""
	var prev_break := false
	for i in raw.length():
		var c := raw.unicode_at(i)
		var ok := (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 45 or c == 95 or c == 46
		if ok:
			out += char(c)
			prev_break = false
		elif not prev_break and not out.is_empty():
			out += "_"
			prev_break = true
	while out.ends_with("_") or out.ends_with("."):
		out = out.substr(0, out.length() - 1)
	while out.begins_with("."):
		out = out.substr(1)
	if out.is_empty():
		return fallback
	return out
