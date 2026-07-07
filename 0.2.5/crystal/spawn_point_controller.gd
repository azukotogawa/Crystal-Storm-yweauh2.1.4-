class_name SpawnPointController
extends RefCounted

const _CombatLog = preload("res://systems/combat_log.gd")

signal spawn_destroyed(spawn: CrystalSpawnPoint)
signal spawn_damaged(spawn: CrystalSpawnPoint, amount: float)
signal all_spawns_destroyed
signal boss_gate_blocked(spawn: CrystalSpawnPoint)

var emit_weaken_mult: float = 1.0
var last_destroyed_label: String = ""

var _spawns: Array[CrystalSpawnPoint] = []
var _active_cells: Dictionary = {}


func set_spawns(spawns: Array) -> void:
	_spawns.clear()
	for s in spawns:
		if s is CrystalSpawnPoint:
			_spawns.append(s)
	rebuild_active_cache()


func get_spawns() -> Array[CrystalSpawnPoint]:
	return _spawns


func get_active_spawns() -> Array[CrystalSpawnPoint]:
	var active: Array[CrystalSpawnPoint] = []
	for spawn in _spawns:
		if spawn.active:
			active.append(spawn)
	return active


func count_active_non_boss() -> int:
	var n := 0
	for spawn in _spawns:
		if spawn.active and not spawn.is_boss:
			n += 1
	return n


func can_damage_spawn(spawn: CrystalSpawnPoint) -> bool:
	if spawn == null or not spawn.active:
		return false
	if spawn.is_boss and count_active_non_boss() > 0:
		return false
	return true


func rebuild_active_cache() -> void:
	_active_cells.clear()
	for spawn in _spawns:
		if spawn.active:
			_active_cells[spawn.world_pos] = spawn


func get_spawn_at_cell(wx: int, wz: int) -> CrystalSpawnPoint:
	return _active_cells.get(Vector2i(wx, wz))


func get_progress() -> Dictionary:
	var active := get_active_spawns().size()
	return {
		"active": active,
		"total": _spawns.size(),
		"destroyed": _spawns.size() - active,
		"last_destroyed": last_destroyed_label,
		"emit_weaken_mult": emit_weaken_mult,
		"boss_active": _is_boss_active(),
		"boss_sealed": _is_boss_active() and count_active_non_boss() > 0,
	}


func damage_spawn(spawn_id: int, amount: float) -> bool:
	for spawn in _spawns:
		if spawn.id != spawn_id:
			continue
		return _try_damage_spawn(spawn, amount)
	return false


func damage_spawn_at_world(pos: Vector2i, amount: float, radius: float = 2.5) -> bool:
	var any_hit := false
	for spawn in _spawns:
		if not spawn.active:
			continue
		if Vector2(pos).distance_to(Vector2(spawn.world_pos)) > radius:
			continue
		if _try_damage_spawn(spawn, amount):
			any_hit = true
	return any_hit


func export_spawn_rows() -> Array:
	var rows: Array = []
	for spawn in _spawns:
		rows.append({
			"id": spawn.id,
			"x": spawn.world_pos.x,
			"z": spawn.world_pos.y,
			"kind": int(spawn.kind),
			"health": spawn.health,
			"max_health": spawn.max_health,
			"active": spawn.active,
			"is_boss": spawn.is_boss,
			"def_id": str(spawn.def_id),
			"display_name": spawn.display_name,
			"emit_rate": spawn.emit_rate,
			"weaken_factor": spawn.weaken_factor,
			"power_drain": spawn.power_drain,
		})
	return rows


func export_meta() -> Dictionary:
	return {
		"emit_weaken_mult": emit_weaken_mult,
		"last_destroyed_label": last_destroyed_label,
	}


func import_meta(data: Dictionary) -> void:
	emit_weaken_mult = float(data.get("emit_weaken_mult", emit_weaken_mult))
	last_destroyed_label = str(data.get("last_destroyed_label", last_destroyed_label))


func _try_damage_spawn(spawn: CrystalSpawnPoint, amount: float) -> bool:
	if not can_damage_spawn(spawn):
		if spawn.is_boss:
			var msg := "[Crystal] Origin boss sealed — destroy other spawns first"
			print(msg)
			_CombatLog.push(msg)
			boss_gate_blocked.emit(spawn)
		return false
	var hp_before: float = spawn.health
	if not spawn.apply_damage(amount):
		if spawn.active and hp_before > spawn.health:
			spawn_damaged.emit(spawn, hp_before - spawn.health)
		return false
	_on_destroyed(spawn)
	return true


func _on_destroyed(spawn: CrystalSpawnPoint) -> void:
	last_destroyed_label = spawn.display_name
	if not spawn.is_boss and spawn.weaken_factor > 0.0:
		emit_weaken_mult = maxf(emit_weaken_mult * (1.0 - spawn.weaken_factor), 0.25)
	rebuild_active_cache()
	var active_n := get_active_spawns().size()
	var total_n := _spawns.size()
	var boss_note := " (BOSS)" if spawn.is_boss else ""
	var msg := "[Crystal] Destroyed %s%s — spawns %d/%d | emit x%.2f" % [
		spawn.display_name,
		boss_note,
		active_n,
		total_n,
		emit_weaken_mult,
	]
	print(msg)
	_CombatLog.push(msg)
	spawn_destroyed.emit(spawn)

	if get_active_spawns().is_empty():
		print("[Crystal] All spawn points destroyed — victory!")
		all_spawns_destroyed.emit()


func _is_boss_active() -> bool:
	for spawn in _spawns:
		if spawn.active and spawn.is_boss:
			return true
	return false