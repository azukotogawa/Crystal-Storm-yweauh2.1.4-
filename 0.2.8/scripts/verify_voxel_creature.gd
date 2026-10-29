extends SceneTree

const _Builder = preload("res://helpers/voxel_creature_builder.gd")
const _Model = preload("res://helpers/voxel_model_builder.gd")
const _Pose = preload("res://entities/creature_pose.gd")
const _Entity = preload("res://entities/world_entity.gd")
const _Palette = preload("res://ui/crystal_palette.gd")
const _Enemy = preload("res://entities/crystal_enemy.gd")
const _MiteLook = preload("res://config/crystal_mite_look.gd")
const _Spawns = preload("res://entities/enemy_spawn_registry.gd")
const _Settings = preload("res://config/world_settings.gd")

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)


func _run() -> void:
	var builder_src := FileAccess.get_file_as_string("res://helpers/voxel_creature_builder.gd")
	if builder_src.find("CANVAS") >= 0 or builder_src.find("Sprite3D") >= 0 or builder_src.find("DEPTH_STEPS") >= 0:
		_fail("creature builder still cuts a sprite canvas")
	if builder_src.find("if not USE_PART_RIG") < 0:
		_fail("part rig flag no longer gates the voxel creatures")
	var entity_src := FileAccess.get_file_as_string("res://entities/world_entity.gd")
	if entity_src.find("uses_rig") < 0 or entity_src.find("_ensure_voxel_model") < 0 or entity_src.find("_ensure_sprite") < 0:
		_fail("world entity must keep the sprite and voxel-prop fallback")
	if not _Builder.USE_PART_RIG:
		_fail("USE_PART_RIG is off, so boar and deer stay on the old visual")
	if _Builder.uses_rig(&"town_villager") or not _Builder.uses_rig(&"origin_warden"):
		_fail("villager has no authored voxel creature and warden has one")
	for kind in [&"boar", &"deer", &"rabbit", &"bird", &"town_militia", &"crystal_mite", &"crystal_stag", &"crystal_wisp", &"corrupted_beast", &"farm_bomber", &"thornling", &"shard_guard"]:
		if not _Builder.uses_rig(kind):
			_fail("%s must use the part rig" % kind)
	_check_kind(&"boar")
	_check_kind(&"deer")
	_check_kind(&"rabbit")
	_check_kind(&"bird", true, true, false)
	_check_kind(&"town_militia")
	_check_kind(&"crystal_mite", true, false, true)
	_check_kind(&"crystal_stag", true, false, true)
	_check_kind(&"corrupted_beast", true, false, true)
	_check_kind(&"crystal_wisp", false, true, true)
	_check_kind(&"farm_bomber", true, false, true)
	_check_kind(&"thornling", true, false, true)
	_check_kind(&"shard_guard", true, false, true)
	_check_optional_wing()
	_check_entities()
	_check_enemy()
	_check_mite_readability()
	_finish()


func _check_kind(kind: StringName, want_tail: bool = true, want_wing: bool = false, crystal: bool = false) -> void:
	var parts: Array = _Builder.parts_for(kind)
	if not _has_kinds(parts, want_tail, want_wing):
		_fail("%s spec is not head, body, two legs, tail=%s wing=%s" % [kind, want_tail, want_wing])
		return
	for part in parts:
		var spec: Dictionary = part
		if spec.has("w") or spec.has("h"):
			_fail("%s part %s still has a sprite rectangle" % [kind, spec.get("id", "")])
		var cells: Array = spec.get("cells", [])
		if cells.is_empty() or not (cells[0] is Vector4i):
			_fail("%s part %s is not a voxel grid" % [kind, spec.get("id", "")])
	var rig := _Builder.build(kind)
	if rig == null:
		_fail("%s did not build" % kind)
		return
	root.add_child(rig)
	var skel := rig.get_node_or_null("Skeleton") as Skeleton3D
	var player := rig.get_node_or_null("CreatureAnim") as AnimationPlayer
	if skel == null or player == null:
		_fail("%s rig is missing the skeleton or the animation player" % kind)
		rig.free()
		return
	for clip in ["idle", "walk", "attack"]:
		if not player.has_animation(clip):
			_fail("%s missing clip %s" % [kind, clip])
	for bone_name in ["Body", "Head", "Leg_L", "Leg_R"]:
		if skel.find_bone(bone_name) < 0:
			_fail("%s missing bone %s" % [kind, bone_name])
	if want_tail and skel.find_bone("Tail") < 0:
		_fail("%s missing bone Tail" % kind)
	if want_wing:
		if skel.find_bone("Wing_L") < 0:
			_fail("%s missing a wing" % kind)
	elif skel.find_bone("Wing_L") >= 0:
		_fail("%s built a wing it does not have" % kind)
	var cube := _Builder.cube_edge()
	var body_mi := _part_mi(skel, "body")
	var body: ArrayMesh = body_mi.mesh as ArrayMesh if body_mi != null else null
	if body == null:
		_fail("%s body has no mesh" % kind)
	else:
		var box := body.get_aabb()
		if box.size.x <= cube * 1.5 or box.size.y <= cube * 1.5 or box.size.z <= cube * 1.5:
			_fail("%s body is a slab %s" % [kind, box.size])
		elif _Model.face_count(body) < 6:
			_fail("%s body faces %d" % [kind, _Model.face_count(body)])
		elif body_mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			_fail("%s body does not cast a shadow" % kind)
		elif _blocks_shadows(body_mi):
			_fail("%s body does not receive shadows" % kind)
		else:
			print("OK %s body %s faces %d" % [kind, box.size, _Model.face_count(body)])
			_check_crystal_body(kind, rig, body_mi, crystal)
	_Builder.play(rig, "idle", 1.2)
	var head_y := skel.get_bone_pose_position(skel.find_bone("Head")).y
	var idle_lift := sin(1.2) * _Pose.IDLE_LIFT
	if absf(head_y - idle_lift) > 0.04:
		_fail("%s idle head y %.3f want %.3f" % [kind, head_y, idle_lift])
	else:
		print("OK %s idle head %.3f" % [kind, head_y])
	_Builder.play(rig, "walk", 1.2)
	var leg_q := skel.get_bone_pose_rotation(skel.find_bone("Leg_L"))
	var leg_z := skel.get_bone_pose_position(skel.find_bone("Leg_L")).z
	var walk_z := sin(1.2) * -1.0 * _Pose.WALK_STEP
	if leg_q.is_equal_approx(Quaternion.IDENTITY):
		_fail("%s walk left the leg at rest" % kind)
	elif absf(leg_z - walk_z) > 0.05:
		_fail("%s walk leg z %.3f want %.3f" % [kind, leg_z, walk_z])
	else:
		print("OK %s walk leg %s" % [kind, leg_q])
	_Builder.play(rig, "attack", 0.4)
	var lunge := skel.get_bone_pose_position(skel.find_bone("Body")).z
	var leg_attack := skel.get_bone_pose_rotation(skel.find_bone("Leg_R"))
	if absf(lunge - (-_Pose.ATTACK_LUNGE)) > 0.04:
		_fail("%s attack lunge %.3f" % [kind, lunge])
	elif leg_attack.is_equal_approx(Quaternion.IDENTITY):
		_fail("%s attack left the leg at rest" % kind)
	else:
		print("OK %s attack lunge %.3f" % [kind, lunge])
	if kind == &"crystal_mite":
		_check_mite_rig(rig)
	rig.free()


func _has_kinds(parts: Array, want_tail: bool, want_wing: bool) -> bool:
	var head := 0
	var body := 0
	var legs := 0
	var tail := 0
	var wing := 0
	for part in parts:
		var kind := str((part as Dictionary).get("kind", ""))
		if kind == "head":
			head += 1
		elif kind == "body":
			body += 1
		elif kind == "leg":
			legs += 1
		elif kind == "tail":
			tail += 1
		elif kind == "wing":
			wing += 1
	if head != 1 or body != 1 or legs != 2:
		return false
	if want_tail != (tail == 1):
		return false
	if want_wing != (wing >= 1):
		return false
	return true


func _part_mi(skel: Skeleton3D, part_name: String) -> MeshInstance3D:
	var att := skel.get_node_or_null(part_name)
	if att == null:
		return null
	return att.get_node_or_null("Mesh") as MeshInstance3D


func _check_optional_wing() -> void:
	var parts: Array = _Builder.parts_for(&"deer").duplicate(true)
	parts.append({
		"id": "wing_l",
		"kind": "wing",
		"bone": "Wing_L",
		"parent": "Body",
		"pivot": "center",
		"cells": [Vector4i(0, 6, 7, 1), Vector4i(1, 6, 7, 1), Vector4i(0, 7, 7, 1)],
	})
	var rig := _Builder.build_parts(parts, _Builder.palette_for(&"deer"), _Builder.cube_edge())
	if rig == null:
		_fail("a spec with a wing did not build")
	else:
		var skel := rig.get_node("Skeleton") as Skeleton3D
		if skel.find_bone("Wing_L") < 0:
			_fail("wing part did not add a bone")
		else:
			print("OK optional wing")
		rig.free()
	var broken: Array = []
	for part in _Builder.parts_for(&"boar"):
		if str((part as Dictionary).get("kind", "")) == "body":
			continue
		broken.append(part)
	if _Builder.build_parts(broken, _Builder.palette_for(&"boar"), _Builder.cube_edge()) != null:
		_fail("a spec with no body still built")
	else:
		print("OK missing body refused")


func _check_entities() -> void:
	var holder := Node.new()
	root.add_child(holder)
	for kind in [&"rabbit", &"bird", &"town_militia", &"boar", &"deer", &"crystal_mite", &"crystal_stag", &"crystal_wisp", &"corrupted_beast", &"farm_bomber", &"thornling", &"shard_guard"]:
		var entity := _Entity.new()
		entity.entity_kind = kind
		holder.add_child(entity)
		entity._ensure_visual(Color.WHITE)
		var rig := entity.get_node_or_null("CreatureRig")
		var anim := entity.get_node_or_null("CreatureRig/CreatureAnim") as AnimationPlayer
		if rig == null or not rig.visible:
			_fail("%s did not spawn a visible part rig" % kind)
		elif anim == null or not anim.has_animation("walk"):
			_fail("%s rig has no walk clip" % kind)
		elif (entity.get_node_or_null("MeshInstance3D") as MeshInstance3D) != null and (entity.get_node("MeshInstance3D") as MeshInstance3D).visible:
			_fail("%s kept the capsule beside the rig" % kind)
		else:
			print("OK %s entity rig" % kind)
	holder.free()


func _check_crystal_body(kind: StringName, rig: Node3D, body_mi: MeshInstance3D, crystal: bool) -> void:
	var body_glows := bool(body_mi.get_meta("crystal_glow", false))
	var glow_n := _glow_count(rig)
	if not crystal:
		if body_glows or glow_n > 0:
			_fail("%s crystal cubes glow" % kind)
		return
	var mostly := kind == &"crystal_mite" or kind == &"crystal_wisp" or kind == &"farm_bomber" or kind == &"shard_guard"
	if mostly and not body_glows:
		_fail("%s body is not crystal" % kind)
	elif not mostly and body_glows:
		_fail("%s hide body is emissive" % kind)
	elif glow_n < 1:
		_fail("%s has no crystal cubes" % kind)
	else:
		var glow_mi := _first_glow(rig)
		var mat: StandardMaterial3D = null
		if glow_mi != null:
			mat = glow_mi.material_override as StandardMaterial3D
		var want_em := _Palette.mass_emission(_Palette.is_active())
		var want_al := _Palette.mass_albedo(_Palette.is_active())
		if kind == &"crystal_mite":
			var look = _MiteLook.load_active()
			want_em = look.emission_color(_Palette.is_active())
			want_al = look.albedo_color(_Palette.is_active())
		var got := Color(0, 0, 0) if mat == null else mat.emission
		if mat == null or not mat.emission_enabled or not _rgb_near(got, want_em):
			_fail("%s emission %s want %s" % [kind, got, want_em])
		elif not _mesh_near(glow_mi, want_al):
			_fail("%s crystal tint is not the palette albedo" % kind)
		else:
			print("OK %s crystal glow %d" % [kind, glow_n])


func _glow_count(node: Node) -> int:
	var n := 0
	if node is MeshInstance3D and bool(node.get_meta("crystal_glow", false)):
		n = 1
	for child in node.get_children():
		n += _glow_count(child)
	return n


func _first_glow(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and bool(node.get_meta("crystal_glow", false)):
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _first_glow(child)
		if found != null:
			return found
	return null


func _mesh_near(mi: MeshInstance3D, want: Color) -> bool:
	if mi == null or mi.mesh == null:
		return false
	var arrays: Array = mi.mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	if colors.is_empty():
		return false
	return _rgb_near(colors[0], want)


func _blocks_shadows(mi: MeshInstance3D) -> bool:
	var mat := mi.material_override as StandardMaterial3D
	if mat == null:
		return true
	if mat.disable_receive_shadows:
		return true
	return mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED


func _rgb_near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.04 and absf(a.g - b.g) < 0.04 and absf(a.b - b.b) < 0.04


func _check_enemy() -> void:
	var holder := Node.new()
	root.add_child(holder)
	for kind in [&"crystal_stag", &"farm_bomber", &"thornling", &"shard_guard"]:
		var enemy := _Enemy.new()
		enemy.enemy_id = kind
		holder.add_child(enemy)
		enemy.setup(kind, null, null)
		var rig := enemy.get_node_or_null("CreatureRig")
		var anim := enemy.get_node_or_null("CreatureRig/CreatureAnim") as AnimationPlayer
		if rig == null or not rig.visible:
			_fail("%s enemy did not spawn a rig" % kind)
		elif anim == null or not anim.has_animation("attack"):
			_fail("%s enemy rig has no attack clip" % kind)
		elif _glow_count(rig) < 1:
			_fail("%s enemy rig has no crystal cubes" % kind)
		elif enemy.get_node_or_null("VoxelProp") != null:
			_fail("%s enemy kept a voxel prop beside the rig" % kind)
		else:
			print("OK %s enemy rig" % kind)
	holder.free()


func _check_mite_rig(rig: Node3D) -> void:
	var look = _MiteLook.load_active()
	if look.visual_scale < 1.9 or look.visual_scale > 2.1:
		_fail("mite visual scale %.2f is not about 2" % look.visual_scale)
	elif not rig.scale.is_equal_approx(Vector3(look.visual_scale, look.visual_scale, look.visual_scale)):
		_fail("mite rig scale %s != look %.2f" % [rig.scale, look.visual_scale])
	elif not bool(rig.get_meta("mite_look", false)):
		_fail("mite rig is missing its look mark")
	else:
		var mat := _first_glow(rig).material_override as StandardMaterial3D
		var energy := 0.0 if mat == null else mat.emission_energy_multiplier
		if mat == null or absf(energy - look.energy(_Palette.is_active())) > 0.02:
			_fail("mite emission energy %.2f" % energy)
		elif not _mite_has_spikes():
			_fail("mite silhouette has no spikes")
		else:
			var purple := _Palette.mass_albedo(false)
			var bush := Color(0.18, 0.42, 0.16)
			if _rgb_near(look.albedo, purple) or _rgb_near(look.albedo, bush):
				_fail("mite albedo still matches the ground or the bushes")
			else:
				_Builder.repaint(rig)
				var again := _first_glow(rig).material_override as StandardMaterial3D
				if again == null or not _rgb_near(again.emission, look.emission_color(_Palette.is_active())):
					_fail("repaint replaced the mite color")
				else:
					print("OK mite scale %.2f energy %.2f" % [look.visual_scale, energy])


func _mite_has_spikes() -> bool:
	var tall := false
	var side := false
	var point := false
	for part in _Builder.parts_for(&"crystal_mite"):
		for cell in (part as Dictionary).get("cells", []):
			if not (cell is Vector4i):
				continue
			var at := cell as Vector4i
			if at.y >= 6:
				tall = true
			if at.x <= 0 or at.x >= 5:
				side = true
			if at.z >= 11:
				point = true
	return tall and side and point


func _check_mite_readability() -> void:
	_Spawns.reset()
	_Spawns.ensure_builtins()
	var def = _Spawns.get_def(&"crystal_mite")
	if def == null:
		_fail("crystal mite spawn def missing")
		return
	if not is_equal_approx(def.hit_radius, 0.32) or not is_equal_approx(def.max_health, 24.0):
		_fail("mite hit radius %.3f or health %.1f changed" % [def.hit_radius, def.max_health])
		return
	if not is_equal_approx(def.contact_damage, 22.0) or not is_equal_approx(def.move_speed, 10.0):
		_fail("mite damage or speed changed")
		return
	if not is_equal_approx(def.mesh_radius, 0.22) or not is_equal_approx(def.mesh_height, 0.70):
		_fail("mite mesh hit size changed")
		return
	var holder := Node.new()
	root.add_child(holder)
	var enemy := _Enemy.new()
	enemy.enemy_id = &"crystal_mite"
	holder.add_child(enemy)
	enemy.setup(&"crystal_mite", null, def)
	var look = _MiteLook.load_active()
	var rig := enemy.get_node_or_null("CreatureRig") as Node3D
	var want_r: float = float(def.hit_radius) * float(_Settings.get_active().voxel_scale)
	if rig == null or not enemy.scale.is_equal_approx(Vector3.ONE):
		_fail("mite combat body was scaled")
	elif not rig.scale.is_equal_approx(Vector3(look.visual_scale, look.visual_scale, look.visual_scale)):
		_fail("spawned mite visual scale %s" % rig.scale)
	elif not is_equal_approx(enemy.get_combat_radius(), want_r):
		_fail("mite combat radius %.3f want %.3f" % [enemy.get_combat_radius(), want_r])
	elif not is_equal_approx(enemy.max_health, 24.0) or not is_equal_approx(enemy.contact_damage, 22.0):
		_fail("spawned mite stats changed")
	else:
		print("OK mite hitbox %.3f health %.0f" % [enemy.get_combat_radius(), enemy.max_health])
	var warden_def = _Spawns.get_def(&"origin_warden")
	var warden := _Enemy.new()
	warden.enemy_id = &"origin_warden"
	holder.add_child(warden)
	warden.setup(&"origin_warden", null, warden_def)
	var warden_rig := warden.get_node_or_null("CreatureRig") as Node3D
	var warden_r: float = float(warden_def.hit_radius) * float(_Settings.get_active().voxel_scale)
	if warden_rig == null or not warden.scale.is_equal_approx(Vector3.ONE):
		_fail("warden body scale changed")
	elif not is_equal_approx(warden_rig.scale.x, 1.3) or not bool(warden_rig.get_meta("boss_rig", false)):
		_fail("warden visual scale %.2f" % warden_rig.scale.x)
	elif not is_equal_approx(warden.get_combat_radius(), warden_r):
		_fail("warden combat radius changed")
	else:
		print("OK warden visual stays %.2f" % warden_rig.scale.x)
	holder.free()


func _finish() -> void:
	if _failed == 0:
		print("All voxel creature tests OK")
		quit(0)
	else:
		push_error("verify_voxel_creature: %d failure(s)" % _failed)
		quit(1)
