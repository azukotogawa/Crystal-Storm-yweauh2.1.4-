class_name SpawnPointDef
extends Resource

@export var id: StringName = &"ruin_miniboss"
@export var display_name: String = "Crystal Spawn"
@export var spawn_kind: int = 1
@export var max_health: float = 120.0
@export var is_boss: bool = false
@export var emit_rate: float = 1.1

@export_group("On Destroy")
## Multiplier applied to global crystal emit rate (0.12 = 12% slower expansion).
@export_range(0.0, 0.5, 0.01)
var weaken_factor: float = 0.12
@export var power_drain: float = 8.0