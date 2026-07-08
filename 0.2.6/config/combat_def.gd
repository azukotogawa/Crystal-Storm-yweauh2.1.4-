class_name CombatDef
extends Resource

@export_group("Melee")
@export_range(20.0, 120.0, 1.0)
var melee_arc_degrees: float = 70.0
@export var melee_vertical_tolerance: float = 2.2
@export_range(1, 8, 1)
var max_melee_targets: int = 4

@export_group("Ranged")
@export var ranged_hit_radius: float = 0.42
@export var ranged_vertical_tolerance: float = 2.5

@export_group("Debug")
@export var log_hits_to_console: bool = true
@export var log_hits_to_panel: bool = true


static func create_default():
	var d = load("res://config/combat_def.gd").new()
	return d