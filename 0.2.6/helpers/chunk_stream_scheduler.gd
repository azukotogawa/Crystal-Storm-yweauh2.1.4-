class_name ChunkStreamScheduler
extends RefCounted
## Distance/velocity/camera-aware stream priority (higher score = higher priority).
## Sorting is amortized by callers via dirty flags; this module stays pure.


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


## Build a fresh high→low priority row list from pending dict.
## Call only when the pending set/scores changed (dirty flag).
static func sort_load_candidates(load_pending: Dictionary) -> Array:
	var rows: Array = []
	rows.resize(load_pending.size())
	var i := 0
	for coord_variant in load_pending.keys():
		var coord: Vector2i = coord_variant
		var entry: Dictionary = load_pending[coord]
		rows[i] = {
			"coord": coord,
			"score": float(entry.get("score", 0.0)),
			"urgent": bool(entry.get("urgent", false)),
		}
		i += 1
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if is_equal_approx(float(a.get("score", 0.0)), float(b.get("score", 0.0))):
			return str(a.get("coord")) < str(b.get("coord"))
		return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
	)
	return rows


## O(n) pick of the single highest-score pending load (no full sort).
## Deterministic: ties broken by coord string order (same as sort_load_candidates).
static func pick_best_load_candidate(load_pending: Dictionary) -> Dictionary:
	if load_pending.is_empty():
		return {}
	var best_coord := Vector2i.ZERO
	var best_score := -1.0e30
	var best_urgent := false
	var have := false
	for coord_variant in load_pending.keys():
		var coord: Vector2i = coord_variant
		var entry: Dictionary = load_pending[coord]
		var score: float = float(entry.get("score", 0.0))
		var urgent: bool = bool(entry.get("urgent", false))
		if not have or score > best_score or (
			is_equal_approx(score, best_score) and str(coord) < str(best_coord)
		):
			have = true
			best_coord = coord
			best_score = score
			best_urgent = urgent
	if not have:
		return {}
	return {"coord": best_coord, "score": best_score, "urgent": best_urgent}


## Sort unload coords far→near (low priority first = unload distant first).
static func sort_unload_candidates(
	unload_pending: Array,
	player_chunk: Vector2i,
	camera_hint: Vector2i
) -> void:
	if unload_pending.size() <= 1:
		return
	unload_pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var sa := priority_score(a, player_chunk, Vector2i.ZERO, camera_hint)
		var sb := priority_score(b, player_chunk, Vector2i.ZERO, camera_hint)
		return sa < sb
	)
