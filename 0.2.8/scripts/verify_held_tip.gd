extends SceneTree

const _HeldItemView = preload("res://systems/held_item_view.gd")
const _ItemAnim = preload("res://systems/item_anim.gd")

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	print("FAIL " + msg)


func _tip_local(item: Node3D) -> Vector3:
	var best := Vector3(0.0, -1.0e9, 0.0)
	var pending: Array[Node] = [item]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			pending.append(child)
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		var top := _mesh_tip(mi)
		if mi != item:
			top = mi.transform * top
		if top.y > best.y:
			best = top
	return best


func _mesh_tip(mi: MeshInstance3D) -> Vector3:
	var mesh := mi.mesh
	var max_y := -1.0e9
	var saw := false
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for p in verts:
			if not saw or p.y > max_y:
				max_y = p.y
				saw = true
	if not saw:
		var ab := mi.get_aabb()
		return ab.position + Vector3(ab.size.x * 0.5, ab.size.y, ab.size.z * 0.5)
	var sum := Vector3.ZERO
	var count := 0
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for p in verts:
			if p.y >= max_y - 0.0001:
				sum += p
				count += 1
	return sum / float(count)


func _run() -> void:
	var view = _HeldItemView.new()
	root.add_child(view)
	await process_frame
	var aim := Vector3(0.0, 0.0, -1.0)
	for id in ["wooden_sword", "spear", "stone_pick", "crystal_hammer"]:
		view.show_item(id)
		var item: Node3D = view.get_node("HeldItem")
		var pb = _ItemAnim.playback_for(id)
		for frac in [1.0, 1.4]:
			pb.elapsed = minf(pb.impact_time() * frac, pb.duration)
			view.apply_playback(pb)
			var grip: Vector3 = item.global_position
			var tip: Vector3 = item.global_transform * _tip_local(item)
			var out := tip - grip
			var flat := Vector3(out.x, 0.0, out.z)
			var d_tip := Vector2(tip.x, tip.z).length()
			var d_grip := Vector2(grip.x, grip.z).length()
			print("%s x%.1f tip %.2f grip %.2f toward aim %.2f" % [id, frac, d_tip, d_grip, flat.normalized().dot(aim) if flat.length() > 0.001 else 0.0])
			if d_tip <= d_grip:
				_fail("%s tip is not farther from the player than the grip at %.1f" % [id, frac])
			if flat.length() < 0.001 or flat.normalized().dot(aim) < 0.7:
				_fail("%s tip does not point toward the aim at %.1f" % [id, frac])
	if _failed == 0:
		print("All held tip checks OK")
		quit(0)
	else:
		quit(1)
