extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")
const GI = preload("res://helpers/gameplay_input.gd")
const ACTS := ["move_right", "move_left", "move_back", "move_forward"]


func _init() -> void:
	call_deferred("_run")


func _ents() -> Array:
	var out: Array = []
	for g in ["crystal_enemy", "world_entity"]:
		for n in get_nodes_in_group(g):
			if n is Node3D and not out.has(n):
				out.append(n)
	return out


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _kind(n) -> String:
	var sc = n.get_script()
	var base: String = sc.resource_path.get_file() if sc else n.get_class()
	var eid = n.get("enemy_id")
	if eid == null:
		eid = n.get("species_id")
	if eid == null:
		eid = n.name
	return "%s/%s" % [base, str(eid)]


func _vis(n) -> Node3D:
	for c in n.get_children():
		if c is Node3D:
			return c
	return null


func _run() -> void:
	var tag := OS.get_environment("P7_TAG")
	var p = await C.boot(self)
	GI.world_loading = false
	GI.modal_open = false
	p.health = p.max_health
	var vs := C.vs()
	var w = C.weapon(p)
	for off in [Vector2i(6, 0), Vector2i(-6, 2), Vector2i(0, 7), Vector2i(3, -6), Vector2i(-5, -5), Vector2i(8, 8)]:
		var m = await C.spawn_mite(self, C.pcol(p) + off, false)
		if m:
			m.contact_damage = 0.0
	var last := {}
	var worst: Array = []
	var maxd := 0.0
	var big := 0
	var samples := 0
	var vlast := {}
	var start_p: Vector3 = p.global_position
	var vmax := 0.0
	var vworst := ""
	var pops := 0
	var pop_ev: Array = []
	var seen := {}
	var dirs := ["move_right", "move_back", "move_left", "move_forward"]
	for f in 2400:
		for a in ACTS:
			Input.action_release(a)
		if f < 300:
			Input.action_press(dirs[int(f / 75) % 4])
		elif f < 1500:
			Input.action_press("move_right")
		else:
			Input.action_press("move_left")
		p.health = p.max_health
		if f % 20 == 0:
			var ms: Array = get_nodes_in_group("crystal_enemy")
			if ms.size() > 0:
				C.point_at(p, ms[0].get_combat_center())
			w._cooldown_timer = 0.0
			w._try_attack()
		await physics_frame
		var now := {}
		for n in _ents():
			if not is_instance_valid(n):
				continue
			var iid: int = n.get_instance_id()
			now[iid] = n.global_position
			var dpl: float = _flat(n.global_position, p.global_position) / vs
			if not seen.has(iid) and f > 5 and dpl < 14.0:
				pops += 1
				if pop_ev.size() < 8:
					pop_ev.append("in f=%d %s at %.1f cols" % [f, _kind(n), dpl])
			var v := _vis(n)
			if v:
				if vlast.has(iid):
					var vd: float = (v.global_position - n.global_position).distance_to(vlast[iid]) / vs
					if vd > vmax:
						vmax = vd
						vworst = "%s f=%d vis=%s" % [_kind(n), f, v.name]
				vlast[iid] = v.global_position - n.global_position
			var id: int = n.get_instance_id()
			var pos: Vector3 = n.global_position
			if last.has(id):
				var d: float = pos.distance_to(last[id]) / vs
				samples += 1
				if d > 1.0:
					big += 1
				if d > maxd:
					maxd = d
				if d > 0.6:
					worst.append([d, f, _kind(n), last[id], pos, n.get("_knock_left"), n.get("_stagger_left"), n.get("_station_reach")])
			last[id] = pos
			seen[id] = true
	for a in ACTS:
		Input.action_release(a)
	print("P7_TELE_POP tag=%s popins_within_14=%d vis_offset_max_cols=%.3f worst=%s" % [tag, pops, vmax, vworst])
	for e in pop_ev:
		print("P7_TELE_POPEV tag=%s %s" % [tag, e])
	worst.sort_custom(func(a, b): return a[0] > b[0])
	print("P7_TELE tag=%s samples=%d max_disp_cols=%.3f frames_over_1col=%d events_over_0.6=%d" % [tag, samples, maxd, big, worst.size()])
	for i in mini(worst.size(), 12):
		var e = worst[i]
		print("P7_TELE_EV tag=%s d=%.2f f=%d kind=%s from=%s to=%s knock=%s stag=%s station=%s" % [tag, e[0], e[1], e[2], e[3], e[4], e[5], e[6], e[7]])
	var reg = get_first_node_in_group("game_visual_registry")
	var before_pos := {}
	var ptravel: float = _flat(p.global_position, start_p) / vs
	for n in get_nodes_in_group("world_entity"):
		n.global_position.x += 3.0 * vs
		before_pos[n.get_instance_id()] = n.global_position
	if reg and reg.has_method("_refresh_scene_visuals"):
		reg._refresh_scene_visuals()
	await physics_frame
	var rmax := 0.0
	var rmoved := 0
	for n in get_nodes_in_group("world_entity"):
		var iid2: int = n.get_instance_id()
		if before_pos.has(iid2):
			var dd: float = n.global_position.distance_to(before_pos[iid2]) / vs
			rmax = maxf(rmax, dd)
			if dd > 1.0:
				rmoved += 1
	print("P7_TELE_REFRESH tag=%s animals=%d max_jump_cols=%.2f jumped_over_1col=%d player_travel_cols=%.1f (animals shifted 3 cols then visual refresh)" % [tag, before_pos.size(), rmax, rmoved, ptravel])
	quit(0)