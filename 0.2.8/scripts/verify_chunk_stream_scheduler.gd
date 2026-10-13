extends SceneTree
## Headless: distance-aware stream priority ordering.


const _Scheduler = preload("res://helpers/chunk_stream_scheduler.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var player := Vector2i(0, 0)
	var near := Vector2i(1, 0)
	var far := Vector2i(4, 4)
	var ahead := Vector2i(0, 2)

	var score_near := _Scheduler.priority_score(near, player, Vector2i(0, 1), Vector2i(0, 1))
	var score_far := _Scheduler.priority_score(far, player, Vector2i(0, 1), Vector2i(0, 1))
	var score_ahead := _Scheduler.priority_score(ahead, player, Vector2i(0, 1), Vector2i(0, 1))
	var score_behind := _Scheduler.priority_score(Vector2i(0, -2), player, Vector2i(0, 1), Vector2i(0, 1))

	if score_near <= score_far:
		push_error("near must beat far: %s vs %s" % [score_near, score_far])
		_ProbeExit.finish_tree(self, 1, "chunk stream scheduler FAILED")
		return
	if score_ahead <= score_behind:
		push_error("ahead must beat behind with velocity hint")
		_ProbeExit.finish_tree(self, 1, "chunk stream scheduler FAILED")
		return

	var pending := {
		far: {"score": score_far, "urgent": false},
		near: {"score": score_near, "urgent": false},
	}
	var sorted: Array = _Scheduler.sort_load_candidates(pending)
	if sorted.is_empty() or sorted[0].get("coord") != near:
		push_error("sorted queue must lead with nearest chunk")
		_ProbeExit.finish_tree(self, 1, "chunk stream scheduler FAILED")
		return
	var best: Dictionary = _Scheduler.pick_best_load_candidate(pending)
	if best.get("coord") != near:
		push_error("pick_best must match sort leader")
		_ProbeExit.finish_tree(self, 1, "chunk stream scheduler FAILED")
		return

	print("OK stream_priority near=%.1f far=%.1f ahead=%.1f" % [score_near, score_far, score_ahead])
	print("OK pick_best matches sort leader")
	_ProbeExit.finish_tree(self, 0, "chunk stream scheduler OK")
