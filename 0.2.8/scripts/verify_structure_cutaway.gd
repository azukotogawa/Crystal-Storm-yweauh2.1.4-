extends SceneTree
## Walls and authored structures use the cutaway shader. The cone cuts a wall
## between the camera and the player, and leaves a wall behind the player.

const _Cutaway = preload("res://helpers/camera_cutaway.gd")
const _StructureMat = preload("res://helpers/structure_cutaway_material.gd")
const _Registry = preload("res://systems/game_visual_registry.gd")
const _Settings = preload("res://systems/player_settings.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL %s" % msg)


func _ok(msg: String) -> void:
	print("OK %s" % msg)


func _run() -> void:
	var reg := _Registry.new()
	root.add_child(reg)
	var host := Node3D.new()
	root.add_child(host)

	var front := MeshInstance3D.new()
	host.add_child(front)
	reg.configure_building_mesh(front, null, Vector3(1.2, 2.4, 1.2), Color.WHITE, "ruin_pillar")
	_assert_structure_material(front, "ruin_pillar")

	var again := MeshInstance3D.new()
	host.add_child(again)
	reg.configure_building_mesh(again, null, Vector3(1.2, 2.4, 1.2), Color.WHITE, "ruin_pillar")
	if front.material_override == null or front.material_override != again.material_override:
		_fail("ruin materials were rebuilt instead of reused")
	else:
		_ok("same structure look reuses one cutaway material")

	var wood := MeshInstance3D.new()
	host.add_child(wood)
	reg.configure_building_mesh(wood, null, Vector3(1, 1.5, 1), Color.WHITE, "wood_wall")
	_assert_structure_material(wood, "wood_wall")
	if wood.material_override == front.material_override:
		_fail("wood_wall shared the ruin material")
	else:
		_ok("different structure looks do not share a material")

	var gate := MeshInstance3D.new()
	host.add_child(gate)
	reg.configure_building_mesh(gate, null, Vector3(1.15, 2.05, 0.55), Color.WHITE, "gate")
	_assert_structure_material(gate, "gate")

	var shader: Shader = (front.material_override as ShaderMaterial).shader
	var code := ""
	if shader != null:
		code = shader.code
	if "cutaway_enabled" not in code or "cutaway_feet_clear" not in code:
		_fail("structure shader is missing the cutaway globals")
	elif "cutaway_player.y + cutaway_feet_clear" not in code:
		_fail("structure shader does not keep the floor under the feet")
	elif "12.9898" not in code or "0.05" not in code:
		_fail("structure shader rim does not match the terrain screen-door")
	else:
		_ok("structure shader uses the same cone, rim, and feet rule")

	# Player in a hole. Pin the ruin's centre on the rim between the camera and the body.
	var feet := Vector3(0.0, 0.0, 0.0)
	var cam_pos := Vector3(0.0, 18.0, 28.0)
	var front_local := front.get_aabb().get_center()
	var front_want := Vector3(0.0, 6.0, 12.0)
	front.position = front_want - front.scale * front_local
	var front_pt := front.to_global(front_local)
	if front_pt.y <= feet.y + _Cutaway.FEET_CLEAR:
		_fail("front ruin sample %.2f is not above the feet clear" % front_pt.y)
	elif not _Cutaway.contains(front_pt, feet, cam_pos):
		_fail("front ruin %s was not classified as cut" % front_pt)
	else:
		_ok("ruin between camera and player is inside the cutaway (%s)" % front_pt)

	var floor_pt := Vector3(front_pt.x, feet.y + 0.35, front_pt.z)
	if _Cutaway.contains(floor_pt, feet, cam_pos):
		_fail("foot-level point on the wall column was cut")
	else:
		_ok("foot-level fragments stay (water lids use the same rule)")

	var back := MeshInstance3D.new()
	host.add_child(back)
	reg.configure_building_mesh(back, null, Vector3(1.2, 2.4, 1.2), Color.WHITE, "ruin_pillar")
	var back_local := back.get_aabb().get_center()
	var back_want := Vector3(0.0, 6.0, -30.0)
	back.position = back_want - back.scale * back_local
	var back_pt := back.to_global(back_local)
	if _Cutaway.contains(back_pt, feet, cam_pos):
		_fail("ruin behind the player was classified as cut (%s)" % back_pt)
	else:
		_ok("ruin behind the player is not cut (%s)" % back_pt)
	if back.material_override != front.material_override:
		_fail("back ruin did not reuse the front cutaway material")

	var cam: Camera3D = Camera3D.new()
	cam.set_script(load("res://player/camera.gd"))
	root.add_child(cam)
	await process_frame
	_Settings.camera_cutaway_enabled = false
	cam.update_cutaway_uniforms()
	if absf(_Cutaway.submitted_enabled) > 0.01:
		_fail("cutaway toggle did not clear the uniform structures read")
	else:
		_ok("camera cutaway toggle gates the uniform structures share")
	_Settings.camera_cutaway_enabled = true
	cam.update_cutaway_uniforms()

	if _failed > 0:
		quit(1)
		return
	print("All structure cutaway tests OK")
	quit(0)


func _assert_structure_material(mi: MeshInstance3D, id: String) -> void:
	if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_fail("%s casts shadows" % id)
		return
	var mat := mi.material_override
	if not _StructureMat.is_cutaway(mat):
		_fail("%s material is not the cutaway shader" % id)
		return
	if not _StructureMat.binds_albedo(mat):
		_fail("%s cutaway material missing albedo texture" % id)
		return
	if not _StructureMat.uses_nearest_filter(mat):
		_fail("%s cutaway material is not nearest filtered" % id)
		return
	_ok("%s uses the nearest cutaway material" % id)
