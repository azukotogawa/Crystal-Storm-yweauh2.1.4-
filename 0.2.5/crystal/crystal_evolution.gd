class_name CrystalEvolution
extends RefCounted

signal enemy_unlocked(enemy_id: StringName)
signal absorption_recorded(source_id: StringName, total: int)

const UNLOCKS: Array[Dictionary] = [
	{"source": &"farmland", "threshold": 2, "enemy": &"farm_bomber"},
	{"source": &"tree", "threshold": 4, "enemy": &"crystal_stag"},
	{"source": &"bush", "threshold": 6, "enemy": &"thornling"},
	{"source": &"grass", "threshold": 10, "enemy": &"crystal_mite"},
	{"source": &"animal", "threshold": 3, "enemy": &"corrupted_beast"},
	{"source": &"ruin", "threshold": 1, "enemy": &"shard_guard"},
]

var absorbed_counts: Dictionary = {}  # StringName -> int
var unlocked_enemies: Array[StringName] = []


func record_absorption(source_id: StringName, amount: int = 1) -> void:
	if source_id == &"":
		return
	var total: int = int(absorbed_counts.get(source_id, 0)) + amount
	absorbed_counts[source_id] = total
	absorption_recorded.emit(source_id, total)
	_check_unlocks(source_id)


func _check_unlocks(source_id: StringName) -> void:
	for entry in UNLOCKS:
		if entry.source != source_id:
			continue
		if int(absorbed_counts.get(source_id, 0)) < int(entry.threshold):
			continue
		var enemy_id: StringName = entry.enemy
		if enemy_id in unlocked_enemies:
			continue
		unlocked_enemies.append(enemy_id)
		enemy_unlocked.emit(enemy_id)


func is_unlocked(enemy_id: StringName) -> bool:
	return enemy_id in unlocked_enemies


func get_summary() -> Dictionary:
	return {
		"absorbed": absorbed_counts.duplicate(),
		"unlocked_enemies": unlocked_enemies.duplicate(),
	}