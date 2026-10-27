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
	var best := Vector3.ZERO
	for child in item.get_children():
		var mi := child as MeshInstance3D
		if mi == null or not mi.visible:
			continue
		var top := mi.position + Vector3(0.0, (mi.mesh as BoxMesh).size.y * 0.5, 0.0)
		if top.y > best.y:
			best = top
	var own := item as MeshInstance3D
	var own_top := Vector3(0.0, (own.mesh as BoxMesh).size.y * 0.5, 0.0)
	return own_top if own_top.y > best.y else best


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
