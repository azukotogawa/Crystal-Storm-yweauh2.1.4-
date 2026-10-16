extends Node

const EVENT_CAP := 2048
const MERGE_WINDOW_MSEC := 1000

var session_id: String = ""
var events: Array[Dictionary] = []

var _player_deaths: int = 0
var _damage_taken: float = 0.0
var _dealt: Dictionary = {}
var _bound: Dictionary = {}


func _ready() -> void:
	begin_session()
	var tree := get_tree()
	if tree == null:
		return
	tree.node_added.connect(_on_node_added)
	call_deferred("_scan_tree")


func begin_session() -> void:
	session_id = _make_session_id()
	events.clear()
	_player_deaths = 0
	_damage_taken = 0.0
	_dealt.clear()


func player_deaths() -> int:
	return _player_deaths


func damage_taken_total() -> float:
	return _damage_taken


func damage_dealt(source: StringName) -> float:
	return float(_dealt.get(_source_key(source), 0.0))


func snapshot() -> Dictionary:
	return {
		"session_id": session_id,
		"player_deaths": _player_deaths,
		"damage_taken": _damage_taken,
		"damage_dealt_by_source": _dealt.duplicate(),
		"events": events.duplicate(true),
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
	return node.has_signal("damage_taken") or node.has_signal("combat_damaged")


func _try_bind(node: Node) -> void:
	if not is_instance_valid(node):
		return
	var id := node.get_instance_id()
	if _bound.has(id):
		return
	var hooked := false
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
	if node.has_signal("combat_damaged") and not node.combat_damaged.is_connected(_on_damage_dealt):
		node.combat_damaged.connect(_on_damage_dealt)
		hooked = true
	if node.is_in_group("crystal_enemy") and node.has_signal("killed") and not node.killed.is_connected(_on_enemy_killed):
		node.killed.connect(_on_enemy_killed)
		hooked = true
	elif node.is_in_group("world_entity") and node.has_signal("died") and not node.died.is_connected(_on_entity_died):
		node.died.connect(_on_entity_died)
		hooked = true
	return hooked


func _forget(id: int) -> void:
	_bound.erase(id)


func _on_damage_taken(amount: float, source: StringName) -> void:
	if amount <= 0.0:
		return
	var key := _source_key(source)
	_damage_taken += amount
	_note_damage("damage_taken", amount, key, "player")


func _on_damage_dealt(amount: float, _remaining: float, source: StringName) -> void:
	if amount <= 0.0:
		return
	var key := _source_key(source)
	_dealt[key] = float(_dealt.get(key, 0.0)) + amount
	_note_damage("damage_dealt", amount, key, "")


func _on_player_died() -> void:
	_push_death("player")


func _on_enemy_killed(enemy_id: StringName, _world_pos: Vector2i, _player_killed: bool) -> void:
	var actor := String(enemy_id)
	if actor == "":
		actor = "enemy"
	_push_death(actor)


func _on_entity_died(entity: Node, _world_pos: Vector2i) -> void:
	var actor := "entity"
	if is_instance_valid(entity) and "entity_kind" in entity:
		actor = String(entity.entity_kind)
		if actor == "":
			actor = "entity"
	_push_death(actor)


func _push_death(actor: String) -> void:
	if actor == "player":
		_player_deaths += 1
	var now := Time.get_ticks_msec()
	events.append(_row("death", "", actor, 0.0, Time.get_unix_time_from_system(), now))
	_trim()


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
				return
	events.append(_row(kind, source, actor, amount, unix, now))
	_trim()


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


func _source_key(source: StringName) -> String:
	if source == &"":
		return "unknown"
	return String(source)


func _make_session_id() -> String:
	return "%d-%08x" % [int(Time.get_unix_time_from_system()), randi()]
