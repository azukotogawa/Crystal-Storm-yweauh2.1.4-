class_name EnemySpawnDef
extends Resource

const _EntityBrainConfig = preload("res://config/entity_brain_config.gd")

@export var id: StringName = &"crystal_mite"
@export var display_name: String = "Crystal Mite"
@export var brain_config_id: StringName = &"crystal_mite"
@export var spawn_weight: float = 1.0
@export var min_crystal_tier: int = 0

@export_group("Combat")
@export var move_speed: float = 10.0
@export var max_health: float = 24.0
@export var contact_damage: float = 22.0
@export var lifetime: float = 45.0
@export var hit_radius: float = 0.38
@export_range(0.0, 0.85, 0.01)
var defense: float = 0.0

@export_group("Crystal Interaction")
@export var feeds_crystal_on_death: bool = false
@export var crystal_feed_power: float = 0.0
@export var absorption_tag: StringName = &"crystal_enemy"

@export_group("Visual")
@export var tint: Color = Color(0.72, 0.2, 0.95, 1.0)
@export var mesh_radius: float = 0.28
@export var mesh_height: float = 0.7