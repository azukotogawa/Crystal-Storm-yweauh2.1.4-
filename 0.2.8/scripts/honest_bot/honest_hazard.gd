extends RefCounted

const _Nav = preload("res://scripts/honest_bot/honest_nav.gd")
const _Move = preload("res://entities/entity_navigation.gd")
const _Enemy = preload("res://entities/crystal_enemy.gd")

const BURN_DEPTH := 0.25
const CLEAR_DEPTH := 0.12
const HIT_COLUMNS := 1.65
const SWORD_RANGE := 2.8
const PAD_MIN := 1.2
const BODY_CLEAR := 8.0
const TRAVEL_SKIRT := 16.0
const LEASH_CLEAR := 24.0
const LOW_RATIO := 0.55
const DASH_COLUMNS := 4.0


static func aggro_columns() -> float:
	return float(_Enemy.GUARDIAN_AGGRO_COLUMNS)


static func leash_columns() -> float:
	return float(_Enemy.GUARDIAN_LEASH_COLUMNS)


static func depth_at(tree: SceneTree, at: Vector2) -> float:
	var crystal = tree.get_first_node_in_group("crystal_manager") if tree != null else null
	if crystal == null or not crystal.has_method("get_depth_at"):
		return 0.0
	return float(crystal.get_depth_at(floori(at.x), floori(at.y)))


static func burning(tree: SceneTree, at: Vector2) -> bool:
	return depth_at(tree, at) >= BURN_DEPTH


static func pick_clear(samples: Array, pos: Vector2) -> Vector2:
	var best := pos
	var best_score := -1.0e9
	var found := false
	for row in samples:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var at: Vector2 = row.get("xz", pos)
		var depth := float(row.get("depth", 1.0))
		if depth >= BURN_DEPTH:
			continue
		var score := (BURN_DEPTH - depth) * 10.0 - at.distance_to(pos) * 0.2
		if depth < CLEAR_DEPTH:
			score += 5.0
		if score > best_score:
			best_score = score
			best = at
			found = true
	return best if found else Vector2.INF


static func leave_goal(tree: SceneTree, pos: Vector2, origin: Vector2) -> Vector2:
	var samples: Array = []
	var ox := floori(pos.x)
	var oz := floori(pos.y)
	for dx in range(-16, 17):
		for dz in range(-16, 17):
			if absi(dx) + absi(dz) > 22:
				continue
			var at := Vector2(float(ox + dx) + 0.5, float(oz + dz) + 0.5)
			samples.append({"xz": at, "depth": depth_at(tree, at)})
	var picked := pick_clear(samples, pos)
	if picked != Vector2.INF:
		return picked
	var away := pos - (origin + Vector2(0.5, 0.5))
	if away.length() < 0.2:
		away = Vector2(1.0, 0.0)
	else:
		away = away.normalized()
	return pos + away * 8.0


static func dodge_point(pos: Vector2, travel: Vector2, threats: Array) -> Vector2:
	var best := Vector2.INF
	var best_pen := 0.0
	var near_goal := travel.distance_to(pos) <= 8.0
	for row in threats:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var at: Vector2 = row.get("xz", pos)
		var radius := float(row.get("radius", BODY_CLEAR))
		var dist := pos.distance_to(at)
		var pen := radius - dist
		if pen <= 0.0:
			continue
		if near_goal and not bool(row.get("hard", false)):
			continue
		if pen <= best_pen:
			continue
		best_pen = pen
		var away := pos - at
		if away.length() < 0.05:
			var side := travel - pos
			away = Vector2(-side.y, side.x) if side.length() > 0.05 else Vector2(1.0, 0.0)
		else:
			away = _around(away, travel - pos)
		away = away.normalized()
		best = pos + away * (pen + 2.5)
	return best


static func _around(away: Vector2, to_goal: Vector2) -> Vector2:
	if to_goal.length_squared() < 0.04 or away.dot(to_goal) >= 0.0:
		return away
	var side := Vector2(-away.y, away.x)
	if side.dot(to_goal) < 0.0:
		side = -side
	var blended := side * 0.85 + to_goal.normalized() * 0.35
	if blended.length_squared() < 0.0001:
		return side
	return blended


static func flee_toward(from_xz: Vector2, goal: Vector2, yaw_degrees: float) -> String:
	return flee_action(from_xz, from_xz * 2.0 - goal, yaw_degrees)


static func bubble_center(pos: Vector2, threats: Array) -> Vector2:
	var best := pos
	var best_pen := -1.0
	for row in threats:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var at: Vector2 = row.get("xz", pos)
		var radius := float(row.get("radius", BODY_CLEAR))
		var pen := radius - pos.distance_to(at)
		if pen > best_pen:
			best_pen = pen
			best = at
	return best


static func flee_action(from_xz: Vector2, threat: Vector2, yaw_degrees: float) -> String:
	var away := from_xz - threat
	if away.length_squared() < 0.0001:
		away = Vector2(1.0, 0.0)
	away = away.normalized()
	var best := "move_forward"
	var best_dot := -2.0
	var options := {
		"move_forward": Vector2(0.0, -1.0),
		"move_back": Vector2(0.0, 1.0),
		"move_left": Vector2(-1.0, 0.0),
		"move_right": Vector2(1.0, 0.0),
	}
	for name in options.keys():
		var dir: Vector2 = _Nav.world_delta(options[name], yaw_degrees)
		if dir.length_squared() < 0.0001:
			continue
		var score := dir.normalized().dot(away)
		if score > best_dot:
			best_dot = score
			best = str(name)
	return best


static func ring_hot(tree: SceneTree, pos: Vector2) -> bool:
	for row in guardian_bubbles(tree):
		if typeof(row) != TYPE_DICTIONARY or not bool(row.get("hard", false)):
			continue
		var at: Vector2 = row.get("xz", pos)
		if pos.distance_to(at) < float(row.get("radius", 0.0)):
			return true
	return false


static func den_center(node: Node) -> Vector2:
	if node == null:
		return Vector2.INF
	if node.has_method("_heart_cell"):
		var cell: Vector2i = node.call("_heart_cell")
		return Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5)
	var brain = node.get("brain")
	if brain != null and "home_pos" in brain:
		var home: Vector2i = brain.home_pos
		return Vector2(float(home.x) + 0.5, float(home.y) + 0.5)
	if node is Node3D:
		return _column_center(node as Node3D)
	return Vector2.INF


static func slam_exit(pos: Vector2, away: Vector2, reach: float, center: Vector2) -> Vector2:
	var dir := away
	if dir.length_squared() < 0.0025:
		dir = Vector2(1.0, 0.0)
	dir = dir.normalized()
	var step := maxf(reach + 0.8, 3.2)
	var goal := pos + dir * step
	var leash := leash_columns()
	if goal.distance_to(center) <= leash:
		return goal
	var clamped := center + (goal - center).normalized() * leash
	if clamped.distance_to(pos) >= reach + 0.35:
		return clamped
	return goal


static func _column_center(body: Node3D) -> Vector2:
	var col := _Move.column_pos(body.global_position)
	return Vector2(float(col.x) + 0.5, float(col.y) + 0.5)


static func _guardian_nodes(tree: SceneTree) -> Array:
	var out: Array = []
	if tree == null:
		return out
	for node in tree.get_nodes_in_group("crystal_enemy"):
		if not is_instance_valid(node) or float(node.get("health")) <= 0.0:
			continue
		var kind := str(node.get("enemy_id"))
		if kind != "spawn_elite" and kind != "origin_warden":
			continue
		if node as Node3D == null:
			continue
		out.append(node)
	return out


static func guardian_bubbles(tree: SceneTree) -> Array:
	var out: Array = []
	if tree == null:
		return out
	var vs := 1.0
	var settings = WorldSettings.get_active()
	if settings != null:
		vs = maxf(float(settings.voxel_scale), 0.001)
	for node in _guardian_nodes(tree):
		var den := den_center(node)
		if den != Vector2.INF:
			out.append({
				"xz": den,
				"radius": aggro_columns(),
				"hard": false,
			})
		var ring := node.get_node_or_null("TelegraphRing") as Node3D
		if ring == null or not ring.visible:
			continue
		out.append({
			"xz": _column_center(ring),
			"radius": ring.scale.x / vs + 1.1,
			"hard": true,
		})
	return out


static func leash_bubbles(tree: SceneTree) -> Array:
	var out: Array = []
	for node in _guardian_nodes(tree):
		var den := den_center(node)
		if den == Vector2.INF:
			continue
		out.append({
			"xz": den,
			"radius": leash_columns(),
			"hard": true,
		})
	return out


static func leash_step(pos: Vector2, travel: Vector2, tree: SceneTree) -> Vector2:
	return dodge_point(pos, travel, leash_bubbles(tree))


static func boss_off_heart(boss: Vector2, origin: Vector2) -> bool:
	var cell := Vector2(float(floori(boss.x)), float(floori(boss.y)))
	var heart := Vector2(float(floori(origin.x)), float(floori(origin.y)))
	return cell.distance_to(heart) > SWORD_RANGE


static func keep_stand(tree: SceneTree, pos: Vector2, foe: Vector2, previous: Vector2) -> Vector2:
	var next := strike_stand(tree, pos, foe)
	if not stand_ok(tree, foe, previous):
		return next
	if next == Vector2.INF:
		return previous
	if pos.distance_to(previous) <= pos.distance_to(next) + 0.35:
		return previous
	return next


static func keep_dodge(pos: Vector2, previous: Vector2, proposed: Vector2) -> Vector2:
	if proposed == Vector2.INF:
		return previous
	if previous == Vector2.INF:
		return proposed
	if pos.distance_to(previous) <= 1.25:
		return proposed
	if pos.distance_to(proposed) + 1.5 < pos.distance_to(previous):
		return proposed
	return previous


static func stand_ok(tree: SceneTree, foe: Vector2, stand: Vector2, reach: float = -1.0, near: float = 1.15) -> bool:
	if stand == Vector2.INF:
		return false
	if reach < 0.0:
		reach = HIT_COLUMNS
	var dist := stand.distance_to(foe)
	if dist > reach or dist < near:
		return false
	return not burning(tree, stand)


static func strike_stand(tree: SceneTree, pos: Vector2, foe: Vector2, reach: float = -1.0, near: float = 1.15) -> Vector2:
	if reach < 0.0:
		reach = HIT_COLUMNS
	if not burning(tree, pos) and pos.distance_to(foe) <= reach and pos.distance_to(foe) >= near:
		return pos
	var best := Vector2.INF
	var best_d := 1.0e9
	var cx := floori(foe.x)
	var cz := floori(foe.y)
	var span := maxi(ceili(reach) + 1, 4)
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var at := Vector2(float(cx + dx) + 0.5, float(cz + dz) + 0.5)
			var dist := at.distance_to(foe)
			if dist > reach or dist < near:
				continue
			if burning(tree, at):
				continue
			var walk := at.distance_to(pos)
			if walk < best_d:
				best_d = walk
				best = at
	return best


static func accepts_kill(kind: String, player_killed: bool) -> bool:
	return player_killed and kind != "" and kind != "origin_warden"


static func sword_pad(tree: SceneTree, origin: Vector2) -> Vector2:
	var center := origin + Vector2(0.5, 0.5)
	var best := Vector2.INF
	var best_score := -1.0e9
	for dx in range(-5, 6):
		for dz in range(-5, 6):
			var at := Vector2(origin.x + float(dx) + 0.5, origin.y + float(dz) + 0.5)
			var dist := at.distance_to(center)
			if dist > SWORD_RANGE or dist < PAD_MIN:
				continue
			if burning(tree, at):
				continue
			var depth := depth_at(tree, at)
			var score := (BURN_DEPTH - depth) * 8.0 - absf(dist - 2.05) * 0.6
			if score > best_score:
				best_score = score
				best = at
	return best


static func rim_carve(tree: SceneTree, origin: Vector2) -> Vector2:
	var center := origin + Vector2(0.5, 0.5)
	var best := Vector2.INF
	var best_d := 1.0e9
	for dx in range(-5, 6):
		for dz in range(-5, 6):
			var at := Vector2(origin.x + float(dx) + 0.5, origin.y + float(dz) + 0.5)
			var dist := at.distance_to(center)
			if dist > SWORD_RANGE or dist < PAD_MIN:
				continue
			if not burning(tree, at):
				continue
			if dist < best_d:
				best_d = dist
				best = at
	return best


static func low_hp(ratio: float) -> bool:
	return ratio <= LOW_RATIO


static func crosses_burn(tree: SceneTree, fro: Vector2, to: Vector2) -> bool:
	if tree == null:
		return false
	var span := fro.distance_to(to)
	var steps := maxi(ceili(span), 1)
	for i in range(steps + 1):
		var at := fro.lerp(to, float(i) / float(steps))
		if burning(tree, at):
			return true
	return false


static func warn_showing(tree: SceneTree) -> bool:
	if tree == null:
		return false
	var host: Node = tree.get_first_node_in_group("game_manager")
	if host == null:
		host = tree.root
	if host == null:
		return false
	var burn := host.find_child("BurnWarn", true, false)
	return burn != null and bool(burn.visible)


static func must_leave(tree: SceneTree, pos: Vector2) -> bool:
	return burning(tree, pos) or warn_showing(tree)


static func sprint_allowed(tree: SceneTree, pos: Vector2, goal: Vector2, ratio: float) -> bool:
	if tree == null or goal == Vector2.INF:
		return true
	var crosses := crosses_burn(tree, pos, goal) or burning(tree, goal)
	if not crosses:
		return true
	if not burning(tree, pos):
		return false
	if depth_at(tree, goal) > depth_at(tree, pos) + 0.02:
		return false
	return not low_hp(ratio)


static func with_sprint(tree: SceneTree, pos: Vector2, goal: Vector2, ratio: float, held: PackedStringArray, want: bool) -> PackedStringArray:
	var out := PackedStringArray()
	for name in held:
		var action := String(name)
		if action == "" or action == "sprint":
			continue
		out.append(action)
	if want and sprint_allowed(tree, pos, goal, ratio):
		out.append("sprint")
	return out


static func skirt_goal(tree: SceneTree, pos: Vector2, goal: Vector2) -> Vector2:
	if tree == null or goal == Vector2.INF:
		return goal
	if burning(tree, pos):
		return leave_goal(tree, pos, goal)
	if not burning(tree, goal) and not crosses_burn(tree, pos, goal):
		return goal
	var step := goal - pos
	if step.length() < 0.2:
		return pos
	var dir := step.normalized()
	var best := pos
	var walked := 0.5
	var span := pos.distance_to(goal)
	while walked < span:
		var at := pos + dir * walked
		if burning(tree, at):
			break
		best = at
		walked += 0.5
	if best.distance_to(pos) >= 1.3:
		return best
	var side := Vector2(-dir.y, dir.x)
	var signs: Array[float] = [1.0, -1.0]
	for sign in signs:
		var cand := pos + side * float(sign) * 3.0
		if not burning(tree, cand) and not crosses_burn(tree, pos, cand):
			return cand
	return best


static func mite_rim(tree: SceneTree, pos: Vector2, foe: Vector2) -> Vector2:
	var melee := strike_stand(tree, pos, foe)
	if melee != Vector2.INF and not crosses_burn(tree, pos, melee):
		return melee
	var best := Vector2.INF
	var best_d := 1.0e9
	var cx := floori(foe.x)
	var cz := floori(foe.y)
	for dx in range(-10, 11):
		for dz in range(-10, 11):
			var at := Vector2(float(cx + dx) + 0.5, float(cz + dz) + 0.5)
			if burning(tree, at):
				continue
			if not burning(tree, pos) and crosses_burn(tree, pos, at):
				continue
			var score := at.distance_to(pos) + at.distance_to(foe) * 0.25
			if score < best_d:
				best_d = score
				best = at
	return best


static func dash_lands_in_burn(tree: SceneTree, pos: Vector2, yaw_degrees: float) -> bool:
	if tree == null:
		return false
	var facing := _Nav.world_delta(Vector2(0.0, -1.0), yaw_degrees)
	if facing.length_squared() < 0.0001:
		return false
	var land := pos + facing.normalized() * DASH_COLUMNS
	return burning(tree, land) or crosses_burn(tree, pos, land)
