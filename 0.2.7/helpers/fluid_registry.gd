class_name FluidRegistry
extends RefCounted

const _FluidTypeDef = preload("res://config/fluid_type_def.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")

static var _defs: Dictionary = {}


static func ensure_builtins() -> void:
	if not _defs.is_empty():
		return
	_register(_make_water())
	_register(_make_crystal(_CrystalSimConfig.create_default()))
	for stub_id in [&"lava", &"poison", &"oil"]:
		_register(_make_future_stub(stub_id))


static func get_def(id: StringName) -> _FluidTypeDef:
	ensure_builtins()
	return _defs.get(id, null)


static func all_ids() -> Array:
	ensure_builtins()
	return _defs.keys()


static func apply_crystal_config(cfg: _CrystalSimConfig) -> void:
	ensure_builtins()
	if cfg:
		_defs[&"crystal"] = _make_crystal(cfg)


static func _register(def: _FluidTypeDef) -> void:
	_defs[def.id] = def


static func _make_water() -> _FluidTypeDef:
	var d := _FluidTypeDef.new()
	d.id = &"water"
	d.display_name = "Water"
	d.flow_model = _FluidTypeDef.FlowModel.GRAVITY_CHANNEL
	d.gravity_preference = 1.0
	d.spread_speed = 2.4
	d.viscosity = 0.18
	d.max_flow_distance = 1.05
	d.uphill_capability = 0.0
	d.update_rate_hz = 10.0
	d.min_depth = 0.05
	d.max_depth = 1.0
	return d


static func _make_crystal(cfg: _CrystalSimConfig) -> _FluidTypeDef:
	var d := _FluidTypeDef.new()
	d.id = &"crystal"
	d.display_name = "Crystal"
	d.flow_model = _FluidTypeDef.FlowModel.PRESSURE_POOL
	d.gravity_preference = 0.35
	d.spread_speed = cfg.pressure_flow_rate
	d.viscosity = clampf(1.0 - cfg.uphill_flow_penalty, 0.05, 1.0)
	d.max_flow_distance = cfg.cliff_height
	d.uphill_capability = cfg.uphill_flow_penalty
	d.update_rate_hz = 20.0
	d.min_depth = cfg.min_depth
	d.max_depth = cfg.max_depth
	return d


static func _make_future_stub(id: StringName) -> _FluidTypeDef:
	var d := _FluidTypeDef.new()
	d.id = id
	d.display_name = str(id).capitalize()
	d.flow_model = _FluidTypeDef.FlowModel.GRAVITY_CHANNEL
	d.gravity_preference = 0.85
	d.spread_speed = 1.2
	d.viscosity = 0.6
	d.max_flow_distance = 1.2
	d.uphill_capability = 0.05
	d.update_rate_hz = 6.0
	d.min_depth = 0.05
	d.max_depth = 1.0
	return d