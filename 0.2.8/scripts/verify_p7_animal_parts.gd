extends SceneTree

const _Builder = preload("res://helpers/voxel_creature_builder.gd")
const _Types = preload("res://helpers/world_feature_types.gd")


func _init() -> void:
	call_deferred("_run")


func _origins(skel: Skeleton3D) -> Dictionary:
	var out := {}
	for child in skel.get_children():
		if child is BoneAttachment3D:
			var att := child as BoneAttachment3D
			var i := skel.find_bone(att.bone_name)
			if i >= 0:
				out[att.bone_name] = skel.get_bone_global_pose(i).origin
	return out


func _locals(skel: Skeleton3D) -> Dictionary:
	var out := {}
	for i in skel.get_bone_count():
		if skel.get_bone_parent(i) <= 0:
			continue
		out[skel.get_bone_name(i)] = skel.get_bone_pose_position(i)
	return out


func _run() -> void:
	await process_frame
	var kinds: Array = []
	for k in _Types.ANIMAL_DISPLAY.keys():
		kinds.append(StringName(str(_Types.ANIMAL_DISPLAY[k]).to_lower()))
	kinds.append_array([&"crystal_mite", &"town_militia", &"origin_warden"])
	var worst_all := 0.0
	var bad := 0
	for kind in kinds:
		var rig := _Builder.build(kind)
		if rig == null:
			print("P7_G_PART kind=%s rig=null" % kind)
			bad += 1
			continue
		root.add_child(rig)
		var skel := rig.get_node("Skeleton") as Skeleton3D
		var cube := _Builder.cube_edge()
		skel.reset_bone_poses()
		var rest := _origins(skel)
		var rest_l := _locals(skel)
		var local_worst := 0.0
		var worst := 0.0
		var worst_at := ""
		for pose in ["idle", "walk", "attack"]:
			for step in 8:
				var phase := TAU * float(step) / 8.0
				_Builder.play(rig, pose, phase)
				var now := _origins(skel)
				var now_l := _locals(skel)
				for bone in rest_l.keys():
					local_worst = maxf(local_worst, (now_l[bone] - rest_l[bone]).length() / cube)
				for bone in rest.keys():
					var d: float = (now.get(bone, Vector3.ZERO) - rest[bone]).length() / cube
					if d > worst:
						worst = d
						worst_at = "%s/%s" % [pose, bone]
		var ok := local_worst <= 1.5
		if not ok:
			bad += 1
		worst_all = maxf(worst_all, local_worst)
		print("P7_G_PART kind=%s parts=%d detach_local_cubes=%.2f global_cubes=%.2f at=%s %s" % [kind, rest.size(), local_worst, worst, worst_at, "ok" if ok else "BAD"])
		rig.queue_free()
	print("P7_G_PARTS tag=%s kinds=%d animal_types=%d worst=%.2f bad=%d %s" % [OS.get_environment("P7_TAG"), kinds.size(), _Types.ANIMAL_DISPLAY.size(), worst_all, bad, "OK" if bad == 0 else "FAIL"])
	quit()