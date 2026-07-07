class_name StatIds
extends RefCounted

# Core player / entity stats. Use StringName keys everywhere for hot-path lookups.

const MAX_HEALTH := &"max_health"
const HEALTH_REGEN := &"health_regen"
const MOVE_SPEED := &"move_speed"
const JUMP_FORCE := &"jump_force"

const CRYSTAL_RESISTANCE := &"crystal_resistance"      # Reduces crystal DOT (0–1)
const CRYSTAL_DAMAGE := &"crystal_damage"              # Multiplier on damage to spawns
const CRYSTAL_YIELD := &"crystal_yield"                # Power gain multiplier (future)

const DIG_SPEED := &"dig_speed"                        # Multiplier: higher = faster digs
const BUILD_COST := &"build_cost"                      # Multiplier on material cost (<1 cheaper)
const PLANT_SPEED := &"plant_speed"                    # Multiplier: faster planting / growth assist
const CHANNEL_SPEED := &"channel_speed"                # Multiplier: faster channel digs / edits

const MELEE_DAMAGE := &"melee_damage"
const RANGED_DAMAGE := &"ranged_damage"
const DEFENSE := &"defense"                            # General damage reduction (0–1)

const BUILD_FLOW_BLOCK := &"build_flow_block"          # How strongly walls block crystal (0–1)

const ALL := [
	MAX_HEALTH, HEALTH_REGEN, MOVE_SPEED, JUMP_FORCE,
	CRYSTAL_RESISTANCE, CRYSTAL_DAMAGE, CRYSTAL_YIELD,
	DIG_SPEED, BUILD_COST, PLANT_SPEED, CHANNEL_SPEED,
	MELEE_DAMAGE, RANGED_DAMAGE, DEFENSE,
	BUILD_FLOW_BLOCK,
]

const DEFAULT_BASES := {
	MAX_HEALTH: 100.0,
	HEALTH_REGEN: 0.0,
	MOVE_SPEED: 16.0,
	JUMP_FORCE: 70.0,
	CRYSTAL_RESISTANCE: 0.0,
	CRYSTAL_DAMAGE: 1.0,
	CRYSTAL_YIELD: 1.0,
	DIG_SPEED: 1.0,
	BUILD_COST: 1.0,
	PLANT_SPEED: 1.0,
	CHANNEL_SPEED: 1.0,
	MELEE_DAMAGE: 1.0,
	RANGED_DAMAGE: 1.0,
	DEFENSE: 0.0,
	BUILD_FLOW_BLOCK: 0.85,
}