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
		var align := _alignment(kind, skel)
		if float(align.get("pivot", 0.0)) > 0.02:
			bad += 1
			print("FAIL pivot kind=%s err=%.4f" % [kind, float(align.get("pivot", 0.0))])
		elif int(align.get("gap", 0)) > 1:
			bad += 1
			print("FAIL gap kind=%s cells=%d at=%s" % [kind, int(align.get("gap", 0)), str(align.get("where", ""))])
		else:
			print("P7_G_ALIGN kind=%s pivot_err=%.4f gap_cells=%d parts=%s" % [kind, float(align.get("pivot", 0.0)), int(align.get("gap", 0)), str(align.get("where", ""))])
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
	bad += _spawn_new_kinds()
	print("P7_G_PARTS tag=%s kinds=%d animal_types=%d worst=%.2f bad=%d %s" % [OS.get_environment("P7_TAG"), kinds.size(), _Types.ANIMAL_DISPLAY.size(), worst_all, bad, "OK" if bad == 0 else "FAIL"])
	quit(1 if bad > 0 else 0)


func _alignment(kind: StringName, skel: Skeleton3D) -> Dictionary:
	if skel.has_method("force_update_all_bone_transforms"):
		skel.force_update_all_bone_transforms()
	var pivot_err := 0.0
	for child in skel.get_children():
		if not (child is BoneAttachment3D):
			continue
		var att := child as BoneAttachment3D
		var mi := att.get_node_or_null("Mesh") as MeshInstance3D
		if mi == null:
			continue
		var bone_i := skel.find_bone(att.bone_name)
		if bone_i < 0:
			continue
		var origin := skel.get_bone_global_pose(bone_i).origin
		pivot_err = maxf(pivot_err, (origin + mi.position).length())
	var parts: Array = _Builder.parts_for(kind)
	var body: Array[Vector3i] = []
	var others: Array = []
	for part in parts:
		var spec: Dictionary = part
		var id := str(spec.get("id", ""))
		var cells := _cell_set(spec)
		if str(spec.get("kind", "")) == "body":
			body = cells
		else:
			others.append({"id": id, "cells": cells})
	var gap := 0
	var where := ""
	for item in others:
		var row: Dictionary = item
		var dist := _nearest(body, row.get("cells", []))
		if dist > gap:
			gap = dist
			where = str(row.get("id", ""))
	return {"pivot": pivot_err, "gap": gap, "where": where}


func _cell_set(spec: Dictionary) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for cell in spec.get("cells", []):
		if cell is Vector4i:
			var packed: Vector4i = cell
			out.append(Vector3i(packed.x, packed.y, packed.z))
	return out


func _nearest(a: Array[Vector3i], b: Array) -> int:
	if a.is_empty() or b.is_empty():
		return 99
	var best := 99
	for p in a:
		for q in b:
			var at: Vector3i = q
			var d := maxi(absi(p.x - at.x), maxi(absi(p.y - at.y), absi(p.z - at.z)))
			if d < best:
				best = d
			if best <= 1:
				return best
	return best


func _spawn_new_kinds() -> int:
	var world_scr = load("res://world/InfiniteNoiseWorld.gd")
	var wildlife = load("res://world/wildlife_density.gd")
	var features = load("res://world/feature_registry.gd")
	var brains = load("res://entities/entity_brain_registry.gd")
	var rewards = load("res://helpers/combat_rewards.gd")
	var entity_scr = load("res://entities/world_entity.gd")
	var voxels = load("res://helpers/voxel_types.gd")
	brains.reset()
	brains.ensure_builtins()
	var home := {
		"sheep": "plains",
		"wolf": "forest",
		"heron": "marsh",
	}
	var bad_n := 0
	for seed_value in [44021, 918337, 12349, 7]:
		var world = world_scr.new(seed_value)
		var plan: Array = wildlife.plan(world, 900, 512)
		for spot in plan:
			var key := str(_Types.ANIMAL_DISPLAY.get(int(spot.get("animal_kind", -1)), "")).to_lower()
			if not home.has(key):
				continue
			if str(spot.get("biome", "")) != str(home[key]):
				bad_n += 1
				print("FAIL spawn biome kind=%s got=%s want=%s" % [key, str(spot.get("biome", "")), home[key]])
	var seen := {}
	var world = world_scr.new(44021)
	var cells: Dictionary = _biome_cells(world, wildlife, voxels)
	for key in home.keys():
		var want: String = home[key]
		var cell: Vector2i = cells.get(want, Vector2i(9999, 9999))
		if cell.x > 4000:
			bad_n += 1
			print("FAIL no %s cell" % want)
			continue
		features.reset()
		features.register_entity_spawn(cell.x, cell.y, _Types.FeatureKind.ANIMAL_SPAWN, _Types.AnimalKind[key.to_upper()])
		var spawns: Array = features.get_entity_spawns()
		var biome: String = wildlife.canonical_biome(str(world.get_biome(float(cell.x), 0.0, float(cell.y)).get("name", "")))
		var cfg = brains.get_def(StringName(key))
		var loot: Dictionary = rewards._loot_for_kind(StringName(key))
		var entity = entity_scr.new()
		entity.entity_kind = StringName(key)
		root.add_child(entity)
		if cfg != null:
			entity.setup(cfg, cell, world, null, null, cell, Color.WHITE)
		var rig: Node = entity.get_node_or_null("CreatureRig")
		var passive: bool = cfg != null and int(cfg.behavior_profile) == 0 and float(cfg.flee_distance) > 0.0 and float(cfg.contact_damage) <= 0.0
		if spawns.size() != 1 or biome != want or rig == null or not passive or str(loot.get("item_id", "")) != "herb" or int(loot.get("count", 0)) != 1:
			bad_n += 1
			print("FAIL spawn kind=%s biome=%s spawns=%d rig=%s passive=%s loot=%s" % [key, biome, spawns.size(), rig != null, passive, str(loot)])
		else:
			seen[key] = "%s@%s,%s nodes=%d" % [biome, cell.x, cell.y, _node_count(rig)]
			print("P7_G_SPAWN kind=%s biome=%s cell=%s,%s nodes=%d flee=%.1f loot=herb" % [key, biome, cell.x, cell.y, _node_count(rig), float(cfg.flee_distance)])
		entity.free()
	if seen.size() != 3:
		bad_n += 1
		print("FAIL spawn missing %s" % str(seen))
	return bad_n


func _biome_cells(world, wildlife, voxels) -> Dictionary:
	var found := {
		"plains": Vector2i(9999, 9999),
		"forest": Vector2i(9999, 9999),
		"marsh": Vector2i(9999, 9999),
	}
	var left := 3
	for x in range(-512, 513, 8):
		if left == 0:
			break
		for z in range(-512, 513, 8):
			var biome: String = wildlife.canonical_biome(str(world.get_biome(float(x), 0.0, float(z)).get("name", "")))
			if not found.has(biome):
				continue
			var have: Vector2i = found[biome]
			if have.x < 4000:
				continue
			var tile := int(world.get_tile_type(float(x), float(z)))
			if tile == int(voxels.RIVER) or tile == int(voxels.WATER):
				continue
			found[biome] = Vector2i(x, z)
			left -= 1
			if left == 0:
				break
	return found


func _node_count(node: Node) -> int:
	var n := 1
	for child in node.get_children():
		n += _node_count(child)
	return n