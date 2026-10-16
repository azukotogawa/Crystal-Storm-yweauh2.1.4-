extends RefCounted

const BURN_DEPTH := 0.25
const CLEAR_DEPTH := 0.12
const HIT_COLUMNS := 2.05


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


static func strike_stand(tree: SceneTree, pos: Vector2, foe: Vector2) -> Vector2:
	var reach := HIT_COLUMNS
	if not burning(tree, pos) and pos.distance_to(foe) <= reach and pos.distance_to(foe) >= 1.15:
		return pos
	var best := Vector2.INF
	var best_d := 1.0e9
	var cx := floori(foe.x)
	var cz := floori(foe.y)
	for dx in range(-4, 5):
		for dz in range(-4, 5):
			var at := Vector2(float(cx + dx) + 0.5, float(cz + dz) + 0.5)
			var dist := at.distance_to(foe)
			if dist > reach or dist < 1.15:
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
