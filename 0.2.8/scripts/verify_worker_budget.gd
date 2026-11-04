extends SceneTree

const _PQ = preload("res://config/performance_quality_config.gd")

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("OK %s" % msg)
	else:
		_failed += 1
		print("FAIL: %s" % msg)


func _run() -> void:
	var path := "res://config/worker_budget.gd"
	if not ResourceLoader.exists(path):
		_check(false, "config/worker_budget.gd missing")
		_finish()
		return
	var WB = load(path)
	OS.set_environment("CRYSTALSTORM_WORKER_SCALE", "1")
	_check(WB.pool_workers(8) == 7 and WB.pool_workers(1) == 1, "pool keeps one core for the main thread")
	_check(WB.stream_inflight(2, 4) == 2, "4 cores: stream tasks stay at preset 2")
	_check(WB.stream_inflight(2, 8) == 3, "8 cores: stream tasks 3")
	_check(WB.stream_inflight(2, 16) == 7, "16 cores: stream tasks 7")
	_check(WB.stream_inflight(6, 8) == 6, "HIGH preset floor 6 kept")
	_check(WB.stream_inflight(2, 64) == 8, "stream tasks capped at 8")
	_check(WB.bake_jobs_inflight(4) == 2 and WB.bake_jobs_inflight(8) == 3 and WB.bake_jobs_inflight(32) == 6, "bake job cap 2/3/6")
	_check(WB.bake_fill_cap(8, 0) == 7 and WB.bake_fill_cap(8, 3) == 4 and WB.bake_fill_cap(2, 5) == 1, "bake fill cap leaves room for stream tasks")
	OS.set_environment("CRYSTALSTORM_CORES", "8")
	_check(WB.cores() == 8, "CRYSTALSTORM_CORES override")
	var cm = load("res://chunks/chunk_manager.gd").new()
	cm.apply_performance_config(_PQ.apply_preset(_PQ.Preset.MEDIUM))
	_check(int(cm.MAX_INFLIGHT_CHUNKS) == 3, "MEDIUM on 8 cores streams 3 chunks (got %d)" % int(cm.MAX_INFLIGHT_CHUNKS))
	cm.apply_performance_config(_PQ.apply_safe_mode())
	_check(int(cm.MAX_INFLIGHT_CHUNKS) == 2, "SAFE stays 2 (got %d)" % int(cm.MAX_INFLIGHT_CHUNKS))
	var BK = load("res://world/world_bake_service.gd")
	_check(BK.budget_cap_workers(3) == 4, "bake fill cap with 3 stream tasks on 8 cores is 4")
	_check(BK.bake_job_cap() == 3, "bake priority jobs on 8 cores is 3")
	OS.set_environment("CRYSTALSTORM_WORKER_SCALE", "0")
	cm.apply_performance_config(_PQ.apply_preset(_PQ.Preset.MEDIUM))
	_check(int(cm.MAX_INFLIGHT_CHUNKS) == 2 and BK.bake_job_cap() == 2 and BK.budget_cap_workers(3) == 7, "WORKER_SCALE=0 gives the old fixed numbers")
	cm.free()
	_finish()


func _finish() -> void:
	print("WORKER_BUDGET %s" % ("OK" if _failed == 0 else "FAIL n=%d" % _failed))
	quit(1 if _failed > 0 else 0)
