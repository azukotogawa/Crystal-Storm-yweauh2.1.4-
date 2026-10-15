extends SceneTree


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
	if not _bow_arrow_visible(parent):
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


func _bow_arrow_visible(parent: Node3D) -> bool:
	var ws = load("res://config/world_settings.gd").get_active()
	var vs: float = float(ws.voxel_scale)
	var rig := Node3D.new()
	rig.name = "BowRig"
	rig.position = Vector3(40, 6, 40)
	parent.add_child(rig)
	var weapon = load("res://weapons/weapon_controller.gd").new()
	weapon.name = "WeaponController"
	rig.add_child(weapon)
	var def: Dictionary = load("res://helpers/item_types.gd").get_def("shortbow")
	var origin := Vector3(3, 8, 1)
	var forward := Vector3(0, 0, 1)
	if not weapon._fire_projectile("shortbow", def, origin, forward, false):
		push_error("shortbow did not launch an arrow")
		rig.free()
		return false
	var arrow: Projectile = null
	for child in weapon.get_children():
		if child is Projectile and (child as Projectile).active:
			arrow = child
			break
	if arrow == null or arrow.kind != &"arrow" or arrow.source_id != &"shortbow":
		push_error("shortbow shot is not an arrow projectile")
		rig.free()
		return false
	var muzzle := origin + forward * (vs * 0.65)
	if arrow.global_position.distance_to(muzzle) > 0.05:
		push_error("arrow left the muzzle, at %s expected %s" % [arrow.global_position, muzzle])
		rig.free()
		return false
	if not arrow.top_level:
		push_error("arrow must stay in world space")
		rig.free()
		return false
	var mesh := arrow.get_node_or_null("ProjectileMesh") as MeshInstance3D
	if mesh == null or mesh.mesh == null or not mesh.visible or not mesh.is_visible_in_tree():
		push_error("bow arrow mesh is not visible")
		rig.free()
		return false
	if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		push_error("bow arrow casts a shadow")
		rig.free()
		return false
	if not _arrow_has_body(mesh.mesh, vs):
		push_error("bow arrow mesh is still a flat cross")
		rig.free()
		return false
	var aim := -arrow.global_transform.basis.z
	if aim.length_squared() < 0.01 or aim.normalized().dot(forward) < 0.9:
		push_error("arrow tip does not point along the shot (%s)" % aim)
		rig.free()
		return false
	arrow.ttl = 0.0
	arrow.integrate(0.05, [])
	rig.free()
	print("OK shortbow arrow is a visible projectile")
	return true


func _arrow_has_body(mesh: Mesh, vs: float) -> bool:
	if mesh.get_surface_count() < 1:
		return false
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	if verts.size() < 12 or colors.size() != verts.size():
		return false
	var index_data := PackedInt32Array()
	var raw_index = arrays[Mesh.ARRAY_INDEX]
	if raw_index is PackedInt32Array:
		index_data = raw_index
	var thick := 0
	var tri_count := index_data.size() / 3 if index_data.size() >= 3 else verts.size() / 3
	for t in tri_count:
		var i0: int
		var i1: int
		var i2: int
		if index_data.size() >= 3:
			i0 = index_data[t * 3]
			i1 = index_data[t * 3 + 1]
			i2 = index_data[t * 3 + 2]
		else:
			i0 = t * 3
			i1 = t * 3 + 1
			i2 = t * 3 + 2
		var span := _tri_span(verts[i0], verts[i1], verts[i2])
		if span.x >= vs * 0.15 and span.y >= vs * 0.15:
			thick += 1
	if thick < 2:
		return false
	var bounds := mesh.get_aabb().size
	if bounds.z < vs * 1.15 or bounds.z <= bounds.x or bounds.z <= bounds.y:
		return false
	var min_z := INF
	for v in verts:
		min_z = minf(min_z, v.z)
	var pale := false
	var red := false
	for n in verts.size():
		var c: Color = colors[n]
		if verts[n].z <= min_z + vs * 0.05 and c.r > 0.9 and c.g > 0.9 and c.b > 0.85:
			pale = true
		if c.r > 0.75 and c.g < 0.3 and c.b < 0.3:
			red = true
	return pale and red


func _tri_span(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var max_v := Vector3(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)), maxf(a.z, maxf(b.z, c.z)))
	var min_v := Vector3(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)), minf(a.z, minf(b.z, c.z)))
	return max_v - min_v
