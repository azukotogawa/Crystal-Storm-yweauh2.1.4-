class_name EntityBrainConfig
extends Resource

const _StatModifier = preload("res://stats/stat_modifier.gd")

enum Disposition { PASSIVE, DEFENSIVE, AGGRESSIVE, CRYSTAL_HUNTER }

enum BehaviorProfile {
	PASSIVE_HERBIVORE,
	TOWN_MILITIA,
	SUICIDE_BOMBER,
	SHARD_GUARD,
	CRYSTAL_STALKER,
}

@export var id: StringName = &"rabbit"
@export var display_name: String = "Rabbit"
@export var disposition: Disposition = Disposition.PASSIVE
@export var behavior_profile: BehaviorProfile = BehaviorProfile.PASSIVE_HERBIVORE

@export_group("Movement")
@export var move_speed: float = 8.0
@export var wander_radius: float = 12.0
@export var patrol_radius: float = 8.0
@export var flee_distance: float = 6.0
@export var chase_distance: float = 18.0
@export var defend_radius: float = 16.0

@export_group("Combat")
@export var max_health: float = 20.0
@export var contact_damage: float = 0.0
@export var attack_cooldown: float = 1.2
@export var hit_radius: float = 0.35
@export_range(0.0, 0.85, 0.01)
var defense: float = 0.0
@export var detonate_on_contact: bool = false
@export var detonate_radius: float = 2.5

@export_group("Crystal Interaction")
@export var avoids_crystal: bool = true
@export var crystal_flee_depth: float = 0.15
@export var feeds_crystal_on_death: bool = true
@export var crystal_feed_power: float = 4.0
@export var crystal_hunt_min_depth: float = 0.12

@export_group("Stats")
@export var stat_bases: Dictionary = {}
@export var stat_modifiers: Array = []