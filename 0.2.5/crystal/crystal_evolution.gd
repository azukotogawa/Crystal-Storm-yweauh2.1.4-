class_name CrystalEvolution
extends RefCounted

signal enemy_unlocked(enemy_id: StringName)
signal absorption_recorded(source_id: StringName, total: int)

const _AbsorptionUnlockDef = preload("res://config/absorption_unlock_def.gd")

var unlock_table: Array = []
var absorbed_counts: Dictionary = {}  # StringName -> int
var unlocked_enemies: Array[StringName] = []


func configure(table: Array) -> void:
	unlock_table.clear()
	for entry in table:
		if entry is _AbsorptionUnlockDef:
			unlock_table.append(entry)
	if unlock_table.is_empty():
		unlock_table = _builtin_unlocks()


func record_absorption(source_id: StringName, amount: int = 1) -> Dictionary:
	if source_id == &"":
		return {}
	var total: int = int(absorbed_counts.get(source_id, 0)) + amount
	absorbed_counts[source_id] = total
	absorption_recorded.emit(source_id, total)
	return _check_unlocks(source_id)


func _check_unlocks(source_id: StringName) -> Dictionary:
	var result := {}
	for entry in unlock_table:
		var def: _AbsorptionUnlockDef = entry
		if def.source_id != source_id:
			continue
		if int(absorbed_counts.get(source_id, 0)) < def.threshold:
			continue
		var enemy_id: StringName = def.enemy_id
		if enemy_id in unlocked_enemies:
			continue
		unlocked_enemies.append(enemy_id)
		enemy_unlocked.emit(enemy_id)
		result = {
			"enemy_id": enemy_id,
			"bonus_power": def.bonus_power,
			"spawn_burst": def.spawn_burst,
		}
	return result


func is_unlocked(enemy_id: StringName) -> bool:
	return enemy_id in unlocked_enemies


func get_summary() -> Dictionary:
	return {
		"absorbed": absorbed_counts.duplicate(),
		"unlocked_enemies": unlocked_enemies.duplicate(),
	}


static func _builtin_unlocks() -> Array:
	var out: Array = []
	out.append(_row(&"farmland", "Farmland", 2, &"farm_bomber", 6.0, 2))
	out.append(_row(&"tree", "Trees", 4, &"crystal_stag", 4.0, 1))
	out.append(_row(&"bush", "Bushes", 6, &"thornling", 2.0, 1))
	out.append(_row(&"grass", "Grass", 10, &"crystal_mite", 0.0, 0))
	out.append(_row(&"animal", "Animals", 3, &"corrupted_beast", 3.0, 1))
	out.append(_row(&"ruin", "Ruins", 1, &"shard_guard", 12.0, 2))
	return out


static func _row(
	source: StringName,
	label: String,
	threshold: int,
	enemy: StringName,
	power: float,
	burst: int
) -> _AbsorptionUnlockDef:
	var d := _AbsorptionUnlockDef.new()
	d.source_id = source
	d.display_name = label
	d.threshold = threshold
	d.enemy_id = enemy
	d.bonus_power = power
	d.spawn_burst = burst
	return d