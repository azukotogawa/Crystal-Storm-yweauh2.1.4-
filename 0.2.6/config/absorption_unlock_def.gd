class_name AbsorptionUnlockDef
extends Resource

## One row in the crystal absorption → enemy unlock table.

@export var source_id: StringName = &"grass"
@export var display_name: String = "Grass"
@export var threshold: int = 10
@export var enemy_id: StringName = &"crystal_mite"
@export var bonus_power: float = 0.0
@export var spawn_burst: int = 0