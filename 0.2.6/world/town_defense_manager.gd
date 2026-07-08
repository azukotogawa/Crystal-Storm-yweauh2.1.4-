class_name TownDefenseManager
extends Node

const _FeatureRegistry = preload("res://world/feature_registry.gd")

enum TownState { SAFE, ALERT, BESIEGED, FALLEN }

signal town_state_changed(town_name: String, state: int, center: Vector2i)
signal town_fallen(town_name: String, center: Vector2i)
signal militia_requested(town: Dictionary, count: int)

@export var alert_depth: float = 0.12
@export var besieged_depth: float = 0.28
@export var fall_depth: float = 0.45
@export var check_radius_scale: float = 0.85
@export var militia_per_alert: int = 2
@export var militia_per_besieged: int = 4
@export var town_health_max: float = 100.0
@export var health_damage_per_second: float = 8.0

var _town_states: Dictionary = {}  # Vector2i center -> TownState
var _town_health: Dictionary = {}
var _crystal: CrystalManager
var _entity_manager: EntityManager


func _enter_tree() -> void:
	add_to_group("town_defense_manager")


func _ready() -> void:
	call_deferred("_bind")


func _bind() -> void:
	_crystal = get_tree().get_first_node_in_group("crystal_manager")
	_entity_manager = get_tree().get_first_node_in_group("entity_manager")
	for town in _FeatureRegistry.get_towns():
		var center: Vector2i = town.get("center", Vector2i.ZERO)
		_town_states[center] = TownState.SAFE
		_town_health[center] = town_health_max


func _process(delta: float) -> void:
	if _crystal == null:
		return
	for town in _FeatureRegistry.get_towns():
		_tick_town(town, delta)


func get_town_state(center: Vector2i) -> int:
	return int(_town_states.get(center, TownState.SAFE))


func is_any_town_fallen() -> bool:
	for state in _town_states.values():
		if int(state) == TownState.FALLEN:
			return true
	return false


func get_status_summary() -> Array:
	var out: Array = []
	for town in _FeatureRegistry.get_towns():
		var center: Vector2i = town.get("center", Vector2i.ZERO)
		out.append({
			"name": town.get("name", "Town"),
			"center": center,
			"state": _town_states.get(center, TownState.SAFE),
			"health": _town_health.get(center, town_health_max),
		})
	return out


func _tick_town(town: Dictionary, delta: float) -> void:
	var center: Vector2i = town.get("center", Vector2i.ZERO)
	var radius: float = float(town.get("radius", 12)) * check_radius_scale
	var max_depth := _max_crystal_depth_in_radius(center, int(radius))
	var prev: int = int(_town_states.get(center, TownState.SAFE))
	var next := _state_from_depth(max_depth)

	if next == TownState.BESIEGED or next == TownState.FALLEN:
		var health: float = float(_town_health.get(center, town_health_max))
		health -= health_damage_per_second * max_depth * delta
		_town_health[center] = health
		if health <= 0.0:
			next = TownState.FALLEN

	if next != prev:
		_town_states[center] = next
		var town_name: String = str(town.get("name", "Settlement"))
		town_state_changed.emit(town_name, next, center)
		if next == TownState.ALERT:
			_request_militia(town, militia_per_alert)
		elif next == TownState.BESIEGED:
			_request_militia(town, militia_per_besieged)
		elif next == TownState.FALLEN:
			town_fallen.emit(town_name, center)


func _state_from_depth(depth: float) -> int:
	if depth >= fall_depth:
		return TownState.FALLEN
	if depth >= besieged_depth:
		return TownState.BESIEGED
	if depth >= alert_depth:
		return TownState.ALERT
	return TownState.SAFE


func _max_crystal_depth_in_radius(center: Vector2i, radius: int) -> float:
	var best := 0.0
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if Vector2(dx, dz).length() > float(radius):
				continue
			best = maxf(best, _crystal.get_depth_at(center.x + dx, center.y + dz))
	return best


func export_state() -> Dictionary:
	const _Codec = preload("res://systems/save_codec.gd")
	return {
		"town_states": _Codec.encode_vec2i_dict(_town_states),
		"town_health": _Codec.encode_vec2i_dict(_town_health),
	}


func import_state(data: Dictionary) -> void:
	const _Codec = preload("res://systems/save_codec.gd")
	_town_states = _Codec.decode_vec2i_dict(data.get("town_states", {}))
	_town_health = _Codec.decode_vec2i_dict(data.get("town_health", {}))
	for town in _FeatureRegistry.get_towns():
		var center: Vector2i = town.get("center", Vector2i.ZERO)
		if not _town_states.has(center):
			_town_states[center] = TownState.SAFE
		if not _town_health.has(center):
			_town_health[center] = town_health_max


func _request_militia(town: Dictionary, count: int) -> void:
	militia_requested.emit(town, count)
	if _entity_manager and _entity_manager.has_method("spawn_town_defenders"):
		_entity_manager.spawn_town_defenders(town, count)