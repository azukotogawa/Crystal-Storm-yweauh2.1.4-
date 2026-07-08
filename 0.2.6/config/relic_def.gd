class_name RelicDef
extends Resource

const _StatModifier = preload("res://stats/stat_modifier.gd")

enum Rarity { COMMON, UNCOMMON, RARE, LEGENDARY }

@export var id: StringName = &"relic_example"
@export var display_name: String = "Example Relic"
@export var description: String = ""
@export var rarity: Rarity = Rarity.COMMON

@export_group("Stat Modifiers")
@export var stat_modifiers: Array = []

@export_group("Crystal Hooks")
@export var crystal_flow_mult: float = 1.0
@export var crystal_damage_aura: float = 0.0
@export var grants_dig_through_crystal: bool = false

@export_group("Building Hooks")
@export var unlock_buildable_ids: Array[StringName] = []
@export var build_cost_mult: float = 1.0

@export_group("Entity Hooks")
@export var friendly_to_towns: bool = false
@export var spawns_entity_id: StringName = &""