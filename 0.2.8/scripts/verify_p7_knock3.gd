extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")
const _Hits = preload("res://systems/combat_hit_resolver.gd")


func _init() -> void:
	call_deferred("_run")


func _one(p, kb: float, dir: Vector2i) -> Array:
	var m = await C.spawn_mite(self, C.pcol(p) + dir * 2, true)
	for _f in 20:
		await physics_frame
	var k0: float = m.knock_moved
	var from: Vector3 = m.global_position - Vector3(dir.x, 0, dir.y) * 2.0
	_Hits.apply_damage(m, 0.01, &"probe", "", from, kb)
	var stun := 0
	for _f in 90:
		await physics_frame
		if "_knock_left" in m and float(m.get("_knock_left")) > 0.0:
			stun += 1
	var out: float = (m.knock_moved - k0) / C.vs()
	await C.clear_mites(self)
	for _f in 10:
		await physics_frame
	return [out, stun]


func _run() -> void:
	var p = await C.boot(self)
	p.health = 100000.0
	var line := ""
	var bad := 0
	for item in ["wooden_sword", "spear", "crystal_hammer", "shortbow", "sling", "crystal_bomb"]:
		var kb := float(ItemTypes.get_def(item).knockback)
		var best := [0.0, 0]
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var r: Array = await _one(p, kb, d)
			if r[0] > best[0]:
				best = r
		if item in ["wooden_sword", "spear", "crystal_hammer"] and (best[0] < 1.7 or best[0] > 2.1):
			bad += 1
		line += " %s kb=%.1f moved=%.2f knock_frames=%d;" % [item, kb, best[0], best[1]]
	print("P7_K tag=%s%s %s" % [OS.get_environment("P7TAG"), line, "OK" if bad == 0 else "FAIL bad=%d" % bad])
	quit()