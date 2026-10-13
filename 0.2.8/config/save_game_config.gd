class_name SaveGameConfig
extends Resource

@export_group("Paths")
@export var save_directory: String = "user://saves/"
@export var default_slot: int = 0
@export var slot_count: int = 3

@export_group("Auto Save")
@export var auto_save_enabled: bool = true
@export var auto_save_interval_sec: float = 300.0
@export var auto_save_on_enemy_unlock: bool = true
@export var auto_save_on_town_besieged: bool = true


static func create_default():
	return load("res://config/save_game_config.gd").new()