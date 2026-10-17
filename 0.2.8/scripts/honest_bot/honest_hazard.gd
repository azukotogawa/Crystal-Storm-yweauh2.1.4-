extends RefCounted

const _Nav = preload("res://scripts/honest_bot/honest_nav.gd")
const _Move = preload("res://entities/entity_navigation.gd")

const BURN_DEPTH := 0.25
const CLEAR_DEPTH := 0.12
const HIT_COLUMNS := 1.65
const SWORD_RANGE := 2.8
const PAD_MIN := 1.2
const BODY_CLEAR := 8.0
const TRAVEL_SKIRT := 16.0
const LEASH_CLEAR := 24.0


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


static func guardian_bubbles(tree: SceneTree) -> Array:
	var out: Array = []
	if tree == null:
		return out
	var vs := 1.0
	var settings = WorldSettings.get_active()
	if settings != null:
		vs = maxf(float(settings.voxel_scale), 0.001)
	for node in tree.get_nodes_in_group("crystal_enemy"):
		if not is_instance_valid(node) or float(node.get("health")) <= 0.0:
			continue
		var kind := str(node.get("enemy_id"))
		if kind != "spawn_elite" and kind != "origin_warden":
			continue
		var body := node as Node3D
		if body == null:
			continue
		var col := _Move.column_pos(body.global_position)
		out.append({
			"xz": Vector2(float(col.x) + 0.5, float(col.y) + 0.5),
			"radius": TRAVEL_SKIRT,
			"hard": false,
		})
		var ring := node.get_node_or_null("TelegraphRing") as Node3D
		if ring == null or not ring.visible:
			continue
		var ring_col := _Move.column_pos(ring.global_position)
		out.append({
			"xz": Vector2(float(ring_col.x) + 0.5, float(ring_col.y) + 0.5),
			"radius": ring.scale.x / vs + 1.1,
			"hard": true,
		})
	return out


static func leash_bubbles(tree: SceneTree) -> Array:
	var out: Array = []
	if tree == null:
		return out
	for node in tree.get_nodes_in_group("crystal_enemy"):
		if not is_instance_valid(node) or float(node.get("health")) <= 0.0:
			continue
		var kind := str(node.get("enemy_id"))
		if kind != "spawn_elite" and kind != "origin_warden":
			continue
		var body := node as Node3D
		if body == null:
			continue
		var col := _Move.column_pos(body.global_position)
		out.append({
			"xz": Vector2(float(col.x) + 0.5, float(col.y) + 0.5),
			"radius": LEASH_CLEAR,
			"hard": true,
		})
	return out


static func leash_step(pos: Vector2, travel: Vector2, tree: SceneTree) -> Vector2:
	return dodge_point(pos, travel, leash_bubbles(tree))


static func boss_off_heart(boss: Vector2, origin: Vector2) -> bool:
	var cell := Vector2(float(floori(boss.x)), float(floori(boss.y)))
	var heart := Vector2(float(floori(origin.x)), float(floori(origin.y)))
	return cell.distance_to(heart) > SWORD_RANGE


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
