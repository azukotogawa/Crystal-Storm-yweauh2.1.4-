class_name ChunkStreamScheduler
extends RefCounted
## Distance/velocity/camera-aware stream priority (lower score = lower priority).


static func priority_score(
	coord: Vector2i,
	player_chunk: Vector2i,
	velocity_hint: Vector2i,
	camera_hint: Vector2i
) -> float:
	var dx := coord.x - player_chunk.x
	var dz := coord.y - player_chunk.y
	var manhattan := absi(dx) + absi(dz)
	var chebyshev := maxi(absi(dx), absi(dz))
	var score := 100000.0 - float(chebyshev) * 10000.0 - float(manhattan) * 1000.0

	if velocity_hint != Vector2i.ZERO:
		var vdot := dx * velocity_hint.x + dz * velocity_hint.y
		if vdot > 0:
			score += 600.0 / float(maxi(chebyshev, 1))
		elif vdot < 0:
			score -= 250.0 / float(manhattan + 1)

	if camera_hint != Vector2i.ZERO:
		var cdot := dx * camera_hint.x + dz * camera_hint.y
		if cdot > 0:
			score += 300.0 / float(maxi(chebyshev, 1))

	return score


static func sort_load_candidates(load_pending: Dictionary) -> Array:
	var rows: Array = []
	for coord_variant in load_pending.keys():
		var coord: Vector2i = coord_variant
		var entry: Dictionary = load_pending[coord]
		rows.append({
			"coord": coord,
			"score": float(entry.get("score", 0.0)),
			"urgent": bool(entry.get("urgent", false)),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if is_equal_approx(float(a.get("score", 0.0)), float(b.get("score", 0.0))):
			return str(a.get("coord")) < str(b.get("coord"))
		return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
	)
	return rows