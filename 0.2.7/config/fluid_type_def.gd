class_name FluidTypeDef
extends Resource

enum FlowModel { PRESSURE_POOL, GRAVITY_CHANNEL }

@export var id: StringName = &"water"
@export var display_name: String = "Water"
@export var flow_model: FlowModel = FlowModel.GRAVITY_CHANNEL
@export_range(0.0, 1.0, 0.01)
var gravity_preference: float = 1.0
@export_range(0.05, 8.0, 0.05)
var spread_speed: float = 1.0
@export_range(0.05, 4.0, 0.05)
var viscosity: float = 0.25
@export_range(0.2, 12.0, 0.1)
var max_flow_distance: float = 1.05
@export_range(0.0, 1.0, 0.01)
var uphill_capability: float = 0.0
@export_range(1.0, 30.0, 0.5)
var update_rate_hz: float = 8.0
@export_range(0.01, 1.0, 0.01)
var min_depth: float = 0.05
@export_range(0.5, 16.0, 0.1)
var max_depth: float = 1.0