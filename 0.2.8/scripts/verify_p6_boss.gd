extends SceneTree

const _VC = preload("res://helpers/voxel_creature_builder.gd")
const _Spawns = preload("res://entities/enemy_spawn_registry.gd")


func _init() -> void:
	call_deferred("_run")


func _range(rig: Node3D, clip: String, bone: String) -> Vector2:
	var skel := rig.get_node("Skeleton") as Skeleton3D
	var bi := skel.find_bone(bone)
	var lo := 1e9
	var hi := -1e9
	var ylo := 1e9
	var yhi := -1e9
	for i in 32:
		_VC.play(rig, clip, TAU * float(i) / 32.0)
		var pose := skel.get_bone_pose(bi)
		var ang := pose.basis.get_euler()
		var a := ang.x + ang.z
		lo = minf(lo, a)
		hi = maxf(hi, a)
		ylo = minf(ylo, pose.origin.y)
		yhi = maxf(yhi, pose.origin.y)
	return Vector2(rad_to_deg(hi - lo), yhi - ylo)


func _run() -> void:
	var ok := true
	_Spawns.ensure_builtins()
	var def = _Spawns.get_def(&"origin_warden")
	var vid := str(def.resolved_visual_id()) if def else "none"
	var old_rig := _VC.build(&"crystal_mite")
	var rig := _VC.build(&"origin_warden")
	root.add_child(rig)
	root.add_child(old_rig)
	if rig == null or not _VC.uses_rig(&"origin_warden") or vid != "origin_warden":
		print("P6_BOSS FAIL rig=%s vid=%s" % [rig != null, vid])
		quit(1)
		return
	var h := float(rig.get_meta("model_height", 0.0))
	var oh := float(old_rig.get_meta("model_height", 0.0)) * old_rig.scale.y
	var meshes := rig.find_children("*", "MeshInstance3D", true, false).size()
	var body_slam := _range(rig, "attack", "Body")
	var head_slam := _range(rig, "attack", "Head")
	var leg_walk := _range(rig, "walk", "Leg_L")
	var body_walk := _range(rig, "walk", "Body")
	var tail_idle := _range(rig, "idle", "Tail")
	var body_idle := _range(rig, "idle", "Body")
	ok = ok and body_slam.x > 30.0 and leg_walk.x > 60.0 and tail_idle.x > 5.0 and body_idle.y > 0.0 and h > oh
	print("P6_BOSS vid=%s height=%.2f (mite_rig %.2f, x1.3 ingame %.2f) parts=%d slam_body_deg=%.1f slam_body_dy=%.2f slam_head_deg=%.1f walk_leg_deg=%.1f walk_body_deg=%.1f idle_tail_deg=%.1f idle_body_dy=%.3f %s" % [vid, h, oh, h * 1.3, meshes, body_slam.x, body_slam.y, head_slam.x, leg_walk.x, body_walk.x, tail_idle.x, body_idle.y, "OK" if ok else "FAIL"])
	quit(0 if ok else 1)
