extends SceneTree
## Arrow travel, gravity drop, a hit on the line, and a miss off the line.


const _Projectile = preload("res://weapons/projectile.gd")


class _Dummy extends Node3D:
	var hits: int = 0

	func take_damage(_amount: float, _source: StringName = &"") -> void:
		hits += 1

	func is_combat_alive() -> bool:
		return true

	func get_combat_center() -> Vector3:
		return global_position

	func get_combat_radius() -> float:
		return 0.35


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var parent := Node3D.new()
	parent.name = "ProjectileProbe"
	root.add_child(parent)

	if not _fly_and_drop(parent):
		failed = true
	if not _hit_on_line(parent):
		failed = true
	if not _miss_off_line(parent):
		failed = true
	if not _fade_material_reused():
		failed = true
	if not _pool_after_parent_freed():
		failed = true

	if failed:
		push_error("Projectile tests FAILED")
		quit(1)
		return
	print("All projectile OK")
	quit(0)


func _launch(parent: Node3D, spec: Dictionary) -> Projectile:
	if not _Projectile.launch(parent, spec):
		return null
	return parent.get_child(parent.get_child_count() - 1) as Projectile


func _fly_and_drop(parent: Node3D) -> bool:
	var arrow := _launch(parent, {
		"origin": Vector3(0, 10, 0),
		"velocity": Vector3(0, 0, 16),
		"gravity": 20.0,
		"kind": "arrow",
		"ttl": 3.0,
		"damage": 10.0,
	})
	if arrow == null:
		push_error("arrow launch failed")
		return false
	var mesh := arrow.get_node_or_null("ProjectileMesh") as MeshInstance3D
	if mesh == null or not mesh.visible:
		push_error("arrow mesh is not visible in flight")
		return false
	if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		push_error("arrow mesh must not cast shadows")
		return false
	var mat := mesh.material_override as StandardMaterial3D
	if mat == null or mat.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
		push_error("arrow material must be unshaded")
		return false
	var y0 := arrow.global_position.y
	var z0 := arrow.global_position.z
	for _i in 8:
		var state := arrow.integrate(0.1, [])
		if state != "fly":
			push_error("open-air arrow should keep flying, got %s" % state)
			return false
	if arrow.global_position.z <= z0 + 1.0:
		push_error("arrow did not travel forward (z %.2f -> %.2f)" % [z0, arrow.global_position.z])
		return false
	if arrow.global_position.y >= y0 - 0.4:
		push_error("gravity did not drop the arrow (y %.2f -> %.2f)" % [y0, arrow.global_position.y])
		return false
	arrow.ttl = 0.0
	arrow.integrate(0.05, [])
	print("OK arrow travels and gravity drops it")
	return true


func _hit_on_line(parent: Node3D) -> bool:
	var dummy := _Dummy.new()
	parent.add_child(dummy)
	dummy.position = Vector3(0, 6, 4)
	var arrow := _launch(parent, {
		"origin": Vector3(0, 6, 0),
		"velocity": Vector3(0, 0, 30),
		"gravity": 0.0,
		"kind": "arrow",
		"ttl": 2.0,
		"damage": 10.0,
		"hit_radius": 0.4,
	})
	if arrow == null:
		push_error("hit-test launch failed")
		return false
	var state := "fly"
	for _i in 12:
		state = arrow.integrate(0.05, [dummy])
		if state != "fly":
			break
	if dummy.hits != 1 or state != "entity":
		push_error("in-line target should be hit once, hits=%d state=%s" % [dummy.hits, state])
		dummy.queue_free()
		return false
	dummy.queue_free()
	print("OK arrow hits the target on its line")
	return true


func _miss_off_line(parent: Node3D) -> bool:
	var dummy := _Dummy.new()
	parent.add_child(dummy)
	dummy.position = Vector3(4, 6, 4)
	var arrow := _launch(parent, {
		"origin": Vector3(0, 6, 0),
		"velocity": Vector3(0, 0, 30),
		"gravity": 0.0,
		"kind": "arrow",
		"ttl": 2.0,
		"damage": 10.0,
		"hit_radius": 0.4,
	})
	if arrow == null:
		push_error("miss-test launch failed")
		return false
	var state := "fly"
	for _i in 16:
		state = arrow.integrate(0.05, [dummy])
		if state != "fly":
			break
		if arrow.global_position.z > 8.0:
			break
	if dummy.hits != 0:
		push_error("off-line target was hit")
		dummy.queue_free()
		return false
	if arrow.global_position.z < 6.0 and state == "entity":
		push_error("off-line shot resolved as an entity hit")
		dummy.queue_free()
		return false
	dummy.queue_free()
	if state == "fly":
		arrow.ttl = 0.0
		arrow.integrate(0.05, [])
	print("OK arrow misses the target off its line")
	return true


func _fade_material_reused() -> bool:
	var holder := Node3D.new()
	root.add_child(holder)
	var arrow := _launch(holder, {
		"origin": Vector3(0, 4, 0),
		"velocity": Vector3(0, 0, 10),
		"gravity": 0.0,
		"kind": "arrow",
		"ttl": 3.0,
	})
	if arrow == null:
		push_error("fade-material launch failed")
		holder.free()
		return false
	if arrow.get("_fade_mat") == null:
		push_error("fade material should exist when the projectile is created")
		holder.free()
		return false
	arrow._stick_at(arrow.global_position)
	var mesh := arrow.get_node_or_null("ProjectileMesh") as MeshInstance3D
	var first := mesh.material_override if mesh else null
	arrow.stuck = false
	arrow.active = true
	arrow._stick_at(arrow.global_position)
	var second := mesh.material_override if mesh else null
	if first == null or first != second:
		push_error("impact allocated a new fade material")
		holder.free()
		return false
	if first == _Projectile._shared_arrow_mat():
		push_error("stuck arrow is still using the shared material")
		holder.free()
		return false
	arrow.stuck = false
	arrow.active = true
	arrow.ttl = 0.0
	arrow.integrate(0.05, [])
	holder.free()
	print("OK projectile reuses its fade material")
	return true


func _pool_after_parent_freed() -> bool:
	var holder := Node3D.new()
	root.add_child(holder)
	var spec := {
		"origin": Vector3(2, 4, 0),
		"velocity": Vector3(0, 0, 8),
		"gravity": 0.0,
		"kind": "arrow",
		"ttl": 30.0,
	}
	var filled := 0
	for _i in _Projectile.MAX_LIVE:
		if _launch(holder, spec) == null:
			break
		filled += 1
	if filled < _Projectile.MAX_LIVE:
		push_error("could not fill the projectile pool, got %d" % filled)
		holder.free()
		return false
	var ghost: Projectile = (load("res://weapons/projectile.gd") as GDScript).new()
	_Projectile._pool.append(ghost)
	var dead: Object = ghost
	ghost.free()
	if not is_instance_valid(dead):
		_Projectile._pool.append(dead)
	holder.free()
	var next := Node3D.new()
	root.add_child(next)
	var again := _launch(next, spec)
	if again == null or not is_instance_valid(again):
		push_error("launch after parent free failed")
		next.free()
		return false
	again.ttl = 0.0
	again.integrate(0.05, [])
	next.free()
	print("OK projectile pool survives a freed parent")
	return true
