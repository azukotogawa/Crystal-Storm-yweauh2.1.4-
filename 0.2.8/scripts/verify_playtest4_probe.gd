extends SceneTree

const _Run = preload("res://scripts/honest_bot/honest_scenario.gd")
const _Exit = preload("res://scripts/probe_exit.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _ItemAnim = preload("res://systems/item_anim.gd")
const _Brains = preload("res://entities/entity_brain_registry.gd")
const _Pulse = preload("res://player/crystal_pulse_skill.gd")
const _Slam = preload("res://player/ground_slam_skill.gd")

var _boot_ms := 0
var _sections := PackedStringArray()


func _init() -> void:
	Engine.physics_jitter_fix = 0.0
	Engine.physics_ticks_per_second = 60
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sections="):
			_sections = a.substr(11).split(",")
	call_deferred("_go")


func _want(s: String) -> bool:
	return _sections.is_empty() or _sections.has(s)


func _go() -> void:
	var run = _Run.new()
	var seen := PackedStringArray()
	var player = await run._boot(self, "crystals", seen)
	if player == null:
		_Exit.finish_tree(self, 1, "PROBE FAIL boot")
		return
	_boot_ms = Time.get_ticks_msec()
	var crystal = get_first_node_in_group("crystal_manager")
	print("PROBE boot tier %d" % int(crystal.get("strength_tier")))
	_tough(player)
	if _want("rush"):
		await _rush(player, crystal)
	if _want("highlight"):
		await _highlight(player)
	if _want("held"):
		await _held(player)
	if _want("knock"):
		await _knock(player)
	_Exit.finish_tree(self, 0, "PROBE DONE")


func _tough(player) -> void:
	player.max_health = 1000000.0
	player.health = 1000000.0


func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await physics_frame
		t += 1.0 / 60.0


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _wc(player):
	return player.get_node_or_null("WeaponController")


func _equip(player, id: String) -> bool:
	var wc = _wc(player)
	var inv = player.inventory
	var at := -1
	for i in 48:
		var s = inv.get_slot(i) if i < 999 else null
		if s != null and str(s.id) == id:
			at = i
			break
	if at < 0:
		inv.add_item(id, 4 if _ItemTypes.is_stackable(id) else 1)
		for i in 48:
			var s = inv.get_slot(i)
			if s != null and str(s.id) == id:
				at = i
				break
	if at < 0:
		return false
	if at >= 9:
		inv.set_hotbar_index(at, 8)
		at = 8
	wc.select_hotbar(at)
	return true


func _vis_meshes(root: Node, out: Array) -> void:
	for c in root.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null and (c as MeshInstance3D).is_visible_in_tree():
			out.append(str(c.name))
		_vis_meshes(c, out)


func _highlight(player) -> void:
	var th = player.find_child("TargetHighlight", true, false)
	if th == null:
		for n in player.get_children():
			if n.get_script() != null and str(n.get_script().resource_path).ends_with("target_highlight.gd"):
				th = n
	if th == null:
		print("PROBE highlight FAIL no TargetHighlight")
		return
	for id in ["stone_pick", "stone", "wood", "wooden_sword", "crystal_hammer"]:
		if not _equip(player, id):
			print("PROBE highlight %s not equipped" % id)
			continue
		var worst := 0
		var names := []
		for i in 30:
			await process_frame
			var out := []
			_vis_meshes(th, out)
			if out.size() > worst:
				worst = out.size()
				names = out
		print("PROBE highlight %s max_visible %d %s" % [id, worst, str(names)])


func _socket(player) -> Node3D:
	var mesh = player.get("player_mesh")
	if mesh == null:
		return null
	return mesh.get_node_or_null("PlayerRig/held_item") as Node3D


func _held(player) -> void:
	var wc = _wc(player)
	var sock := _socket(player)
	print("PROBE held socket %s" % ("yes" if sock != null else "no"))
	var view = wc.get("_held")
	if view == null:
		print("PROBE held FAIL no view")
		return
	var item: Node3D = view.get("_item")
	var vs: float = _WorldSettings.get_active().voxel_scale
	var dirs := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)]
	for id in ["wooden_sword", "stone_pick", "crystal_hammer", "spear", "shortbow", "stone"]:
		if not _equip(player, id):
			print("PROBE held %s not equipped" % id)
			continue
		await _wait(0.1)
		var rest_max := 0.0
		for d in dirs:
			view.show_item(id)
			view.face(d)
			view.pose_rig(d)
			await process_frame
			if sock != null and item.is_visible_in_tree():
				rest_max = maxf(rest_max, item.global_position.distance_to(sock.global_position))
		var swing_max := 0.0
		var pb = _ItemAnim.playback_for(id)
		var dur: float = 0.5
		if pb != null and pb.has_method("unit"):
			pass
		for d in dirs:
			for u in [0.25, 0.5, 0.75]:
				view.set("_pose_unit", u)
				view.set("_pose_kind", int(_ItemAnim.spec_for(id).get("kind", 0)))
				view.call("_apply_unit", int(_ItemAnim.spec_for(id).get("kind", 0)), u, float(_ItemAnim.spec_for(id).get("impact_ratio", 0.42)))
				view.face(d)
				view.pose_rig(d)
				if sock != null and item.is_visible_in_tree():
					swing_max = maxf(swing_max, item.global_position.distance_to(sock.global_position))
		print("PROBE held %s visible %s rest_max_dist %.3f swing_max_dist %.3f (voxels %.2f / %.2f)" % [id, str(item.is_visible_in_tree()), rest_max, swing_max, rest_max / vs, swing_max / vs])


func _spawn(player, kind: String, at_col: Vector2i) -> Node3D:
	if kind.begins_with("we:"):
		var em = get_first_node_in_group("entity_manager")
		if em == null:
			return null
		var cfg = _Brains.get_def(StringName(kind.substr(3)))
		var before := []
		for e0 in em.get("_entities"):
			if is_instance_valid(e0):
				before.append(e0.get_instance_id())
		em._spawn_world_entity(at_col.x, at_col.y, cfg, at_col, Color.WHITE)
		for e in em.get("_entities"):
			if is_instance_valid(e) and not before.has(e.get_instance_id()):
				return e
		return null
	var spawner = get_first_node_in_group("crystal_enemy_spawner")
	var before2 := get_nodes_in_group("crystal_enemy")
	if not spawner.spawn_enemy_at_column(StringName(kind), at_col.x, at_col.y, Vector2i.ZERO, true):
		return null
	for e in get_nodes_in_group("crystal_enemy"):
		if not before2.has(e):
			return e
	return null


func _hit(player, weapon: String, target: Node3D, fwd: Vector3) -> void:
	var wc = _wc(player)
	var ws = _WorldSettings.get_active()
	var vs: float = ws.voxel_scale
	var def: Dictionary = _ItemTypes.get_def(weapon) if _ItemTypes.is_valid(weapon) else {}
	var cam: Camera3D = player.get("camera") as Camera3D
	if cam != null:
		var AT = load("res://player/action_targeting.gd")
		var aim: Vector3 = target.get_combat_center() if target.has_method("get_combat_center") else target.global_position + Vector3(0, vs * 0.5, 0)
		AT._event_pos = cam.unproject_position(aim)
		AT._event_ok = true
	match weapon:
		"wooden_sword":
			wc._do_melee_attack(weapon, def)
		"spear":
			wc._do_thrust_attack(weapon, def)
		"crystal_hammer":
			wc._do_hammer_attack(weapon, def)
		"stone_pick":
			wc.set("_feel_resolving", true)
			wc.set("_feel_hit_entities", true)
			wc._do_dig_attack(weapon, def)
			wc.set("_feel_resolving", false)
			wc.set("_feel_hit_entities", false)
		"shortbow", "sling", "crystal_bomb":
			var p = (load("res://weapons/projectile.gd") as GDScript).new()
			root.add_child(p)
			p.active = true
			p.top_level = true
			p.global_position = target.global_position - fwd * vs * 0.8
			p.damage = float(def.get("entity_damage", def.get("damage", 10.0)))
			p.knockback = float(def.get("knockback", 0.8)) * vs
			p.source_id = StringName(weapon)
			p.blast_radius = float(def.get("blast_radius", 0.0))
			if weapon == "crystal_bomb":
				p.kind = &"bomb"
				p.call("_explode", target.global_position - fwd * vs * 0.8)
			else:
				p.call("_damage_entity", target, target.global_position)
		"ground_slam":
			var c := Vector2i(floori(ws.world_to_column(player.global_position.x)), floori(ws.world_to_column(player.global_position.z)))
			_Slam.strike([target], c, ws, player)
		"crystal_pulse":
			var c2 := Vector2i(floori(ws.world_to_column(player.global_position.x)), floori(ws.world_to_column(player.global_position.z)))
			_Pulse.strike([target], c2, ws, player)


func _knock(player) -> void:
	var wc = _wc(player)
	var ws = _WorldSettings.get_active()
	var vs: float = ws.voxel_scale
	var weapons := ["wooden_sword", "spear", "crystal_hammer", "stone_pick", "shortbow", "sling", "crystal_bomb", "ground_slam", "crystal_pulse"]
	var kinds := ["crystal_mite", "crystal_stag", "shard_guard", "thornling", "spawn_elite", "origin_warden", "we:boar", "we:rabbit", "we:town_militia"]
	print("PROBE knock table voxels (peak displacement away from player within 0.8 s)")
	for w in weapons:
		var row := []
		for k in kinds:
			_tough(player)
			if w == "stone_pick":
				_equip(player, "stone_pick")
			else:
				_equip(player, "wooden_sword")
			await _wait(0.05)
			var fwd: Vector3 = _flat(wc._aim_forward(2.0)).normalized()
			if fwd.length_squared() < 0.5:
				fwd = Vector3(0, 0, -1)
			var pc := Vector2(ws.world_to_column(player.global_position.x), ws.world_to_column(player.global_position.z))
			var tc := pc + Vector2(fwd.x, fwd.z) * 1.0
			var col := Vector2i(floori(tc.x), floori(tc.y))
			var e := _spawn(player, k, col)
			if e == null:
				row.append("nospawn")
				continue
			await _wait(0.05)
			var off: Vector3 = _flat(e.global_position - player.global_position)
			var want: Vector3 = player.global_position + fwd * vs * 1.0
			e.global_position = Vector3(want.x, e.global_position.y, want.z)
			if "max_health" in e:
				e.max_health = 100000.0
			e.health = 100000.0
			if "_hurt_player" in e:
				e.set("_hurt_player", 0.0)
			var dir := _flat(e.global_position - player.global_position).normalized()
			var p0: Vector3 = e.global_position
			var hp0: float = e.health
			_hit(player, w, e, fwd)
			var kl0 = e.get("_knock_left")
			await physics_frame
			if k == "crystal_mite" or k == "we:boar":
				print("PROBE kdiag %s %s knock_left0 %s after1 %s target %s pos_moved %.3f" % [w, k, str(kl0), str(e.get("_knock_left")) if is_instance_valid(e) else "freed", str(e.get("_target")) if is_instance_valid(e) else "-", (e.global_position - p0).length() if is_instance_valid(e) else -1.0])
			var peak := 0.0
			var t := 0.0
			while t < 0.8 and is_instance_valid(e):
				await physics_frame
				t += 1.0 / 60.0
				peak = maxf(peak, (e.global_position - p0).dot(dir))
			var dmg := hp0 - float(e.health) if is_instance_valid(e) else -1.0
			row.append("%.2f%s" % [peak / vs, "" if dmg > 0.0 else "(nohit)"])
			if is_instance_valid(e):
				e.queue_free()
			await _wait(0.05)
		print("PROBE knock %s | %s" % [w, " ".join(row)])
	print("PROBE knock cols %s" % " ".join(kinds))


func _rush(player, crystal) -> void:
	var ws = _WorldSettings.get_active()
	var wc = _wc(player)
	var origin: Vector2i = crystal.get_origin_cell()
	var def: Dictionary = _ItemTypes.get_def("wooden_sword")
	var dmg: float = wc._crystal_hit_damage(def)
	var hdef: Dictionary = _ItemTypes.get_def("crystal_hammer")
	var hdmg: float = wc._crystal_hit_damage(hdef)
	while (Time.get_ticks_msec() - _boot_ms) < 10000:
		await process_frame
	var prog: Dictionary = crystal.get_spawn_progress()
	print("PROBE rush start t=%.1f s tier %d hp %.1f sword_hit %.2f hammer_hit %.2f" % [(Time.get_ticks_msec() - _boot_ms) / 1000.0, int(crystal.get("strength_tier")), float(prog.get("crystal_health", -1.0)), dmg, hdmg])
	var t := 0.0
	var destroyed := false
	var swings := 0
	var cd := 0.0
	while t < 60.0:
		await physics_frame
		t += 1.0 / 60.0
		cd -= 1.0 / 60.0
		if cd <= 0.0:
			cd = 0.32
			swings += 1
			if crystal.damage_spawn_at_world(origin, maxf(dmg, hdmg), 2.8):
				destroyed = true
				break
		_tough(player)
	prog = crystal.get_spawn_progress()
	print("PROBE rush swings %d destroyed %s hp %.1f tier %d" % [swings, str(destroyed), float(prog.get("crystal_health", -1.0)), int(crystal.get("strength_tier"))])
