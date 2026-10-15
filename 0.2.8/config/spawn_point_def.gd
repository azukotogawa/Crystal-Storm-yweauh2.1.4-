class_name SpawnPointDef
extends Resource

const _CrystalTypes = preload("res://helpers/crystal_types.gd")

const POSITION_RULE_ORIGIN_CELL := &"origin_cell"
const RELEASED_CRYSTAL_HEALTH := 500.0

@export var id: StringName = &"ruin_miniboss"
@export var display_name: String = "Crystal Spawn"
@export var spawn_kind: int = 1
@export var max_health: float = 120.0
@export var is_boss: bool = false
@export var emit_rate: float = 1.1
@export var position_rule: StringName = &""

@export_group("On Destroy")
@export_range(0.0, 0.5, 0.01)
var weaken_factor: float = 0.12
@export var power_drain: float = 8.0


static func resolved_crystal():
	var cfg = load("res://config/game_config.gd")
	if cfg == null or not bool(cfg.SINGLE_CRYSTAL):
		return null
	return make_released()


static func make_released() -> SpawnPointDef:
	var d := SpawnPointDef.new()
	d.id = &"released_crystal"
	d.display_name = "Crystal"
	d.spawn_kind = _CrystalTypes.SpawnKind.ORIGIN
	d.max_health = RELEASED_CRYSTAL_HEALTH
	d.is_boss = false
	d.emit_rate = _CrystalTypes.emit_rate_for(_CrystalTypes.SpawnKind.ORIGIN)
	d.weaken_factor = 0.0
	d.power_drain = 0.0
	d.position_rule = POSITION_RULE_ORIGIN_CELL
	return d