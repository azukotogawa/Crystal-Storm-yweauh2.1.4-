extends Node3D
## Headless combat stub for spatial query consumer verifies only.

func get_combat_center() -> Vector3:
	return global_position if is_inside_tree() else position


func get_combat_radius() -> float:
	if has_meta("combat_radius"):
		return float(get_meta("combat_radius"))
	return 0.35


func is_combat_alive() -> bool:
	return is_inside_tree()


func get_combat_defense() -> float:
	return 0.0


func take_damage(_amount: float, _source: StringName = &"") -> void:
	pass
