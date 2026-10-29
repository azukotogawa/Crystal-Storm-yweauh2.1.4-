extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var p = await C.boot(self)
	var svc = get_first_node_in_group("progression_service")
	var lv0: int = svc.level
	var max0: float = p.max_health
	p.health = 7.0
	var need := 0
	for _i in 200:
		if svc.level > lv0:
			break
		svc.add_xp(5)
		need += 5
	for _i in 5:
		await physics_frame
	var ok: bool = svc.level > lv0 and absf(p.health - p.max_health) < 0.01
	print("P7_LEVELHEAL tag=%s level %d->%d xp_added=%d max_hp %.1f->%.1f hp_after=%.1f %s" % [OS.get_environment("P7_TAG"), lv0, svc.level, need, max0, p.max_health, p.health, "OK" if ok else "FAIL"])
	quit()
