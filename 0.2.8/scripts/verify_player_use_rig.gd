extends SceneTree

const _Body = preload("res://player/player_body_mesh.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

var _failed: int = 0


class _Host extends Player:
	func _ready() -> void:
		pass


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)
	print("FAIL " + msg)


func _run() -> void:
	var ws = _WorldSettings.get_active()
	var player := _Host.new()
	player.name = "Player"
	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	player.add_child(mesh)
	player.player_mesh = mesh
	_Body.apply_to(mesh, ws.player_height(), ws.player_radius())
	root.add_child(player)
	var anim := mesh.get_node_or_null("PlayerAnim") as AnimationPlayer
	if anim == null:
		_fail("rig has no AnimationPlayer")
		_finish()
		return
	for clip_name in ["swing_sword", "swing_pick", "swing_hammer", "bow_draw", "bow_aim"]:
		if not anim.has_animation(clip_name):
			_fail("missing %s" % clip_name)
	var hammer := anim.get_animation("swing_hammer")
	if hammer == null or not is_equal_approx(hammer.length, 1.0):
		_fail("hammer swing is not the 1.0 unit cycle")
	else:
		var track := -1
		for i in hammer.get_track_count():
			if str(hammer.track_get_path(i)) == "PlayerRig:UpperArm_R":
				track = i
		if track < 0:
			_fail("hammer swing does not pose the right arm")
		else:
			var at_raise := -1.0
			var at_hit := -1.0
			for k in hammer.track_get_key_count(track):
				var when := hammer.track_get_key_time(track, k)
				if is_equal_approx(when, 0.403):
					at_raise = when
				if is_equal_approx(when, 0.62):
					at_hit = when
			if at_raise < 0.0 or at_hit < 0.0:
				_fail("hammer wind-up keys are not 0.65 of 0.62 and the 0.62 hit")
			else:
				print("OK hammer keys raise %.3f hit %.3f" % [at_raise, at_hit])
	var aim := Vector3(1.0, 0.0, -2.0).normalized()
	if not _Body.play_use(mesh, "bow_aim", 0.0, aim):
		_fail("bow aim did not play on the rig")
	else:
		var arm := _arm_flat(mesh)
		var dot := arm.dot(aim)
		var twin := Vector3(2.0, 0.0, -1.0).normalized()
		if dot < 0.85:
			_fail("right arm missed the cursor (aim %.2f twin %.2f)" % [dot, arm.dot(twin)])
		else:
			print("OK bow arm aim %.2f" % dot)
	var raised := _arm_height(mesh, "swing_hammer", 0.40, aim)
	var hit := _arm_height(mesh, "swing_hammer", 0.62, aim)
	if raised < hit + 0.15:
		_fail("hammer arm did not rise before the 0.62 hit (raise %.2f hit %.2f)" % [raised, hit])
	else:
		print("OK hammer arm raise %.2f hit %.2f" % [raised, hit])
	_Body.play_use(mesh, "swing_sword", 0.0, aim)
	var sword_rest := _arm_tip(mesh)
	_Body.play_use(mesh, "swing_sword", 0.42, aim)
	var sword_swung := _arm_tip(mesh).distance_to(sword_rest)
	if sword_swung < 0.15:
		_fail("sword swing did not move the right arm (%.3f)" % sword_swung)
	else:
		print("OK sword arm swing %.3f" % sword_swung)
	_Body.play_use(mesh, "swing_pick", 0.0, aim)
	var pick_rest := _arm_tip(mesh)
	_Body.play_use(mesh, "swing_pick", 0.45, aim)
	var chopped := _arm_tip(mesh).distance_to(pick_rest)
	if chopped < 0.15:
		_fail("pick swing did not move the right arm (%.3f)" % chopped)
	else:
		print("OK pick arm swing %.3f" % chopped)
	_Body.play_use(mesh, "bow_draw", 0.0, aim)
	var draw_rest := _hand(mesh)
	_Body.play_use(mesh, "bow_draw", 0.7, aim)
	var drawn := _hand(mesh).distance_to(draw_rest)
	if drawn < 0.08:
		_fail("bow draw did not pull the right arm (%.3f)" % drawn)
	else:
		print("OK bow draw %.3f" % drawn)
	_finish()


func _arm_flat(mesh: MeshInstance3D) -> Vector3:
	var dir := _arm_dir(mesh)
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return Vector3.ZERO
	return dir.normalized()


func _arm_dir(mesh: MeshInstance3D) -> Vector3:
	var skel := mesh.get_node("PlayerRig") as Skeleton3D
	var upper := skel.find_bone("UpperArm_R")
	if skel.has_method("force_update_all_bone_transforms"):
		skel.force_update_all_bone_transforms()
	var basis := skel.get_bone_global_pose(upper).basis
	return basis * Vector3.DOWN


func _arm_tip(mesh: MeshInstance3D) -> Vector3:
	var skel := mesh.get_node("PlayerRig") as Skeleton3D
	var lower := skel.find_bone("LowerArm_R")
	if skel.has_method("force_update_all_bone_transforms"):
		skel.force_update_all_bone_transforms()
	return skel.get_bone_global_pose(lower).origin


func _hand(mesh: MeshInstance3D) -> Vector3:
	var skel := mesh.get_node("PlayerRig") as Skeleton3D
	var lower := skel.find_bone("LowerArm_R")
	if skel.has_method("force_update_all_bone_transforms"):
		skel.force_update_all_bone_transforms()
	var pose := skel.get_bone_global_pose(lower)
	return pose.origin + pose.basis * Vector3.DOWN * 0.45


func _arm_height(mesh: MeshInstance3D, clip: String, unit: float, aim: Vector3) -> float:
	_Body.play_use(mesh, clip, unit, aim)
	return _arm_tip(mesh).y


func _finish() -> void:
	if _failed == 0:
		print("All player use rig tests OK")
		quit(0)
	else:
		quit(1)
