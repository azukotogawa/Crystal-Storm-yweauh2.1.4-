class_name CrystalFluidSim
extends VoxelFluidEngine

const _FluidRegistry = preload("res://helpers/fluid_registry.gd")

var spawn_id_by_cell: Dictionary = {}


func _init(p_config, p_terrain) -> void:
	_FluidRegistry.ensure_builtins()
	_FluidRegistry.apply_crystal_config(p_config)
	super._init(p_config, p_terrain, _FluidRegistry.get_def(&"crystal"))


func clear() -> void:
	super.clear()
	spawn_id_by_cell.clear()


func has_crystal_at(wx: int, wz: int) -> bool:
	return has_fluid_at(wx, wz)


func set_depth(pos: Vector2i, new_depth: float, spawn_id: int = -1, emit: bool = true) -> void:
	new_depth = clampf(new_depth, 0.0, _max_depth())
	if new_depth < _min_depth():
		if depth.has(pos):
			depth.erase(pos)
			spawn_id_by_cell.erase(pos)
			if emit:
				depth_cleared.emit(pos)
				depth_changed.emit(pos)
		return
	var changed: bool = not depth.has(pos) or absf(float(depth[pos]) - new_depth) > 0.02
	depth[pos] = new_depth
	if spawn_id >= 0:
		spawn_id_by_cell[pos] = spawn_id
	if changed and emit:
		depth_changed.emit(pos)


func tick_emitters(spawn_points: Array, delta: float, emit_weaken_mult: float = 1.0) -> void:
	var mult: float = maxf(emit_weaken_mult, 0.05) * _spread_pressure_mult()
	for spawn in spawn_points:
		if not spawn.active:
			continue
		var pos: Vector2i = spawn.world_pos
		if not _cell_active(pos):
			continue
		var current: float = float(depth.get(pos, 0.0))
		var added: float = spawn.emit_rate * mult * delta
		var room := _max_depth() - current
		if room <= 0.0:
			continue
		set_depth(pos, current + minf(added, room), spawn.id)


func _on_fluid_transfer(from: Vector2i, to: Vector2i) -> void:
	if spawn_id_by_cell.has(to):
		return
	if spawn_id_by_cell.has(from):
		spawn_id_by_cell[to] = spawn_id_by_cell[from]