extends RefCounted

const BURN_DEPTH := 0.25
const CLEAR_DEPTH := 0.12
const HIT_COLUMNS := 1.65
const SWORD_RANGE := 2.8
const PAD_MIN := 1.2


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
