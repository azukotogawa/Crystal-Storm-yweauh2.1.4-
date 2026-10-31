extends SceneTree

const _Loader = preload("res://helpers/crystal_voxel_loader.gd")
const _Body = preload("res://player/player_body_mesh.gd")
const _Creatures = preload("res://helpers/voxel_creature_builder.gd")
const _WS = preload("res://config/world_settings.gd")

const _ANIMALS := [
	["res://assets/voxel/entities/deer.json", "deer", false],
	["res://assets/voxel/entities/crystal_stag.json", "crystal_stag", true],
	["res://assets/voxel/entities/boar.json", "boar", false],
	["res://assets/voxel/entities/corrupted_beast.json", "corrupted_beast", true],
	["res://assets/voxel/entities/rabbit.json", "rabbit", false],
	["res://assets/voxel/entities/bird.json", "bird", false],
	["res://assets/voxel/entities/crystal_wisp.json", "crystal_wisp", true],
]

const _MODELS := [
	["res://assets/voxel/entities/player.json", "player", 3000],
	["res://assets/voxel/entities/crystal_mite.json", "crystal_mite", 3000],
	["res://assets/voxel/entities/crystal_mite_spike.json", "crystal_mite_spike", 3000],
	["res://assets/voxel/entities/crystal_mite_shard.json", "crystal_mite_shard", 3000],
]

var _failed := 0
var _allowed := {}


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)


func _run() -> void:
	_load_palette()
	var quads := {}
	for spec in _MODELS:
		quads[str(spec[1])] = _check_model(str(spec[0]), str(spec[1]), int(spec[2]))
	_check_player_anim()
	_check_mites()
	var animal_quads := {}
	for spec in _ANIMALS:
		animal_quads[str(spec[1])] = _check_animal(str(spec[0]), str(spec[1]), bool(spec[2]))
	var boss_quads := {}
	for spec in [
		["res://assets/voxel/entities/shard_guard.json", "shard_guard", 3000, false],
		["res://assets/voxel/entities/origin_warden.json", "origin_warden", 8000, true],
		["res://assets/voxel/entities/shard_tyrant.json", "shard_tyrant", 8000, true],
	]:
		boss_quads[str(spec[1])] = _check_boss(str(spec[0]), str(spec[1]), int(spec[2]), bool(spec[3]))
	print(
		"BOSS QUADS before guard=55 warden=163 tyrant=55 after guard=%s warden=%s tyrant=%s"
		% [boss_quads.get("shard_guard", -1), boss_quads.get("origin_warden", -1), boss_quads.get("shard_tyrant", -1)]
	)
	print(
		"ANIMAL QUADS deer=%s stag=%s boar=%s beast=%s rabbit=%s bird=%s wisp=%s"
		% [
			animal_quads.get("deer", -1),
			animal_quads.get("crystal_stag", -1),
			animal_quads.get("boar", -1),
			animal_quads.get("corrupted_beast", -1),
			animal_quads.get("rabbit", -1),
			animal_quads.get("bird", -1),
			animal_quads.get("crystal_wisp", -1),
		]
	)
	print(
		"ENTITY QUADS before player=186 mite=140 after player=%s mite=%s spike=%s shard=%s"
		% [quads.get("player", -1), quads.get("crystal_mite", -1), quads.get("crystal_mite_spike", -1), quads.get("crystal_mite_shard", -1)]
	)
	if _failed == 0:
		print("VOXEL ENTITIES OK")
		quit(0)
	else:
		push_error("verify_voxel_entities: %d failure(s)" % _failed)
		quit(1)


func _load_palette() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/voxel/palette.json"))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("shared palette")
		return
	for entry in parsed.get("colors", []):
		var rgb = entry.get("rgb", [])
		_allowed["%d,%d,%d" % [int(rgb[0]), int(rgb[1]), int(rgb[2])]] = true


func _check_model(path: String, name: String, budget: int) -> int:
	var rig := _Loader.rig_for(path)
	if rig.is_empty():
		_fail("%s load" % name)
		return -1
	var model = rig.get("model", null)
	var quads := int(rig.get("quads", -1))
	var parts: Dictionary = rig.get("parts", {})
	var part_quads := 0
	for key in parts.keys():
		part_quads += int((parts[key] as Dictionary).get("quads", 0))
	print("VOXEL %s voxels=%d quads=%d part_quads=%d" % [name, int(rig.get("voxels", -1)), quads, part_quads])
	if model == null or model.model_name != name or model.vpb != 16 or model.base_cell != 2:
		_fail("%s fields" % name)
	if model != null and model.scale_mode != "terrain_block":
		_fail("%s scale" % name)
	if part_quads > budget or quads > budget:
		_fail("%s quads %d part %d over %d" % [name, quads, part_quads, budget])
	if model != null:
		for col in model.palette:
			var key := "%d,%d,%d" % [col.r8, col.g8, col.b8]
			if not _allowed.has(key):
				_fail("%s palette %s" % [name, key])
	if name == "player":
		for part_name in ["head", "torso", "upper_arm_l", "lower_arm_l", "upper_arm_r", "lower_arm_r", "leg_l", "leg_r"]:
			var pack: Dictionary = parts.get(part_name, {})
			if pack.get("mesh", null) == null:
				_fail("player missing %s" % part_name)
		if model != null and model.size.y != 34:
			_fail("player grid height %s" % model.size)
	else:
		for part_name in ["body", "head", "leg_l", "leg_r", "tail"]:
			var pack: Dictionary = parts.get(part_name, {})
			if pack.get("mesh", null) == null:
				_fail("%s missing %s" % [name, part_name])
		var dark := false
		if model != null:
			for cell in model.cells_for("head"):
				if (cell as Vector4i).w == 1:
					dark = true
		if not dark:
			_fail("%s head has no dark eye" % name)
	return part_quads


func _check_animal(path: String, name: String, crystal: bool) -> int:
	var rig := _Loader.rig_for(path)
	if rig.is_empty():
		_fail("%s load" % name)
		return -1
	var model = rig.get("model", null)
	var quads := int(rig.get("quads", -1))
	var parts: Dictionary = rig.get("parts", {})
	var part_quads := 0
	for key in parts.keys():
		part_quads += int((parts[key] as Dictionary).get("quads", 0))
	print("VOXEL %s voxels=%d quads=%d part_quads=%d" % [name, int(rig.get("voxels", -1)), quads, part_quads])
	if model == null or model.model_name != name or model.vpb != 16 or model.base_cell != 2 or model.scale_mode != "terrain_block":
		_fail("%s fields" % name)
	if part_quads > 3000 or quads > 3000:
		_fail("%s quads %d part %d over 3000" % [name, quads, part_quads])
	var need := ["body", "head", "leg_l", "leg_r"]
	if name != "crystal_wisp":
		need.append("tail")
	if name == "bird" or name == "crystal_wisp":
		need.append("wing_l")
		need.append("wing_r")
	for part_name in need:
		var pack: Dictionary = parts.get(part_name, {})
		if pack.get("mesh", null) == null:
			_fail("%s missing %s" % [name, part_name])
	if name != "bird" and name != "crystal_wisp" and parts.has("wing_l"):
		_fail("%s has a wing" % name)
	if name == "crystal_wisp" and parts.has("tail"):
		_fail("crystal_wisp has a tail part")
	var saw_eye := false
	var saw_crystal := false
	if model != null:
		for col in model.palette:
			var key := "%d,%d,%d" % [col.r8, col.g8, col.b8]
			if not _allowed.has(key):
				_fail("%s palette %s" % [name, key])
			if key == "184,71,255":
				saw_crystal = true
		for cell in model.cells_for("head"):
			var at := cell as Vector4i
			if at.w >= 0 and at.w < model.palette.size():
				var col: Color = model.palette[at.w]
				if col.r8 == 20 and col.g8 == 20 and col.b8 == 26:
					saw_eye = true
	if not saw_eye:
		_fail("%s head has no dark eye" % name)
	if crystal != saw_crystal:
		_fail("%s crystal colour present=%s" % [name, saw_crystal])
	return part_quads


func _check_boss(path: String, name: String, budget: int, boss: bool) -> int:
	var rig := _Loader.rig_for(path)
	if rig.is_empty():
		_fail("%s load" % name)
		return -1
	var model = rig.get("model", null)
	var quads := int(rig.get("quads", -1))
	var parts: Dictionary = rig.get("parts", {})
	var part_quads := 0
	for key in parts.keys():
		part_quads += int((parts[key] as Dictionary).get("quads", 0))
	var blocks := 0.0
	if model != null:
		blocks = float(model.size.y) / 16.0
	print("VOXEL %s voxels=%d quads=%d part_quads=%d blocks=%.3f" % [name, int(rig.get("voxels", -1)), quads, part_quads, blocks])
	if model == null or model.model_name != name or model.vpb != 16 or model.base_cell != 2 or model.scale_mode != "terrain_block":
		_fail("%s fields" % name)
	if name == "shard_guard" and (part_quads > 3000 or quads > 3000):
		_fail("%s quads %d part %d over 3000" % [name, quads, part_quads, 3000])
	elif part_quads > budget or quads > budget:
		_fail("%s quads %d part %d over %d" % [name, quads, part_quads, budget])
	if boss and (blocks < 4.0 or blocks > 6.0):
		_fail("%s height %.3f blocks" % [name, blocks])
	var scale := 1.3 if name == "origin_warden" else (1.35 if name == "shard_tyrant" else 1.0)
	if blocks * scale > 6.05:
		_fail("%s visual height %.3f" % [name, blocks * scale])
	for part_name in ["body", "head", "leg_l", "leg_r", "tail"]:
		var pack: Dictionary = parts.get(part_name, {})
		if pack.get("mesh", null) == null:
			_fail("%s missing %s" % [name, part_name])
	var saw_eye := false
	var saw_crystal := false
	if model != null:
		for col in model.palette:
			var key := "%d,%d,%d" % [col.r8, col.g8, col.b8]
			if not _allowed.has(key):
				_fail("%s palette %s" % [name, key])
			if key == "184,71,255":
				saw_crystal = true
		for cell in model.cells_for("head"):
			var at := cell as Vector4i
			if at.w >= 0 and at.w < model.palette.size():
				var col: Color = model.palette[at.w]
				if col.r8 == 20 and col.g8 == 20 and col.b8 == 26:
					saw_eye = true
		if model.palette.size() > 16:
			_fail("%s palette size %d" % [name, model.palette.size()])
	if not saw_eye:
		_fail("%s head has no dark eye" % name)
	if not saw_crystal:
		_fail("%s missing crystal" % name)
	var built := _Creatures.build(StringName(name))
	if built == null:
		_fail("%s rig did not build" % name)
	else:
		root.add_child(built)
		var anim := built.get_node_or_null("CreatureAnim") as AnimationPlayer
		var skel := built.get_node_or_null("Skeleton") as Skeleton3D
		if anim == null or skel == null or not anim.has_animation("idle") or not anim.has_animation("walk") or not anim.has_animation("attack"):
			_fail("%s anim" % name)
		elif name == "origin_warden" and not bool(built.get_meta("boss_rig", false)):
			_fail("warden boss rig")
		elif name != "origin_warden":
			_Creatures.play(built, "walk", 1.2)
			var leg_q: Quaternion = skel.get_bone_pose_rotation(skel.find_bone("Leg_L"))
			if leg_q.is_equal_approx(Quaternion.IDENTITY):
				_fail("%s walk leg" % name)
			else:
				print("OK %s walk" % name)
		else:
			print("OK %s boss rig" % name)
		built.free()
	return part_quads


func _check_player_anim() -> void:
	var ws = _WS.get_active()
	var mi := MeshInstance3D.new()
	root.add_child(mi)
	_Body.apply_to(mi, ws.player_height(), ws.player_radius())
	var anim := mi.get_node_or_null("PlayerAnim") as AnimationPlayer
	var skel := mi.get_node_or_null("PlayerRig") as Skeleton3D
	if anim == null or skel == null:
		_fail("player rig missing")
		mi.free()
		return
	_Body.play_pose(mi, "idle", 1.2)
	if skel.has_method("force_update_all_bone_transforms"):
		skel.force_update_all_bone_transforms()
	var head_i := skel.find_bone("Head")
	var rest_y: float = skel.get_bone_rest(skel.find_bone("Torso")).origin.y
	var pose_y: float = skel.get_bone_pose_position(skel.find_bone("Torso")).y
	if absf(pose_y - rest_y) < 0.02:
		_fail("player idle torso did not lift")
	else:
		print("OK player idle torso %.3f" % pose_y)
	_Body.play_pose(mi, "walk", 1.2)
	if skel.has_method("force_update_all_bone_transforms"):
		skel.force_update_all_bone_transforms()
	var leg_q: Quaternion = skel.get_bone_pose_rotation(skel.find_bone("Leg_L"))
	if leg_q.is_equal_approx(Quaternion.IDENTITY):
		_fail("player walk left the leg at rest")
	elif head_i < 0:
		_fail("player head bone")
	else:
		print("OK player walk leg")
	mi.free()


func _check_mites() -> void:
	for kind in [&"crystal_mite", &"crystal_mite_spike", &"crystal_mite_shard"]:
		var rig := _Creatures.build(kind)
		if rig == null:
			_fail("%s did not build" % kind)
			continue
		root.add_child(rig)
		var anim := rig.get_node_or_null("CreatureAnim") as AnimationPlayer
		var skel := rig.get_node_or_null("Skeleton") as Skeleton3D
		if anim == null or skel == null or not anim.has_animation("idle") or not anim.has_animation("walk"):
			_fail("%s anim" % kind)
		else:
			_Creatures.play(rig, "walk", 1.2)
			var leg_q: Quaternion = skel.get_bone_pose_rotation(skel.find_bone("Leg_L"))
			if leg_q.is_equal_approx(Quaternion.IDENTITY):
				_fail("%s walk leg" % kind)
			else:
				print("OK %s walk" % kind)
		rig.free()
