extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")
const _Hits = preload("res://systems/combat_hit_resolver.gd")


func _init() -> void:
	call_deferred("_run")


func _one(p, kb: float, dir: Vector2i, resist: float) -> float:
	var m = await C.spawn_mite(self, C.pcol(p) + dir * 2, true)
	m.contact_damage = 0.0
	if resist > 0.0:
		m.set("knock_resist", resist)
	for _f in 20:
		await physics_frame
	var k0: float = m.knock_moved
	var from: Vector3 = m.global_position - Vector3(dir.x, 0, dir.y) * 2.0
	_Hits.apply_damage(m, 0.01, &"probe", "", from, kb)
	for _f in 90:
		await physics_frame
	var out: float = (m.knock_moved - k0) / C.vs()
	await C.clear_mites(self)
	for _f in 10:
		await physics_frame
	return out


func _best(p, kb: float, resist: float = 0.0) -> float:
	var best := 0.0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		best = maxf(best, await _one(p, kb, d, resist))
	return best


func _run() -> void:
	var p = await C.boot(self)
	p.health = 100000.0
	var feel = GameFeelConfig.active()
	var line := ""
	var bad := 0
	for item in ["wooden_sword", "crystal_hammer", "spear", "shortbow", "sling", "crystal_bomb"]:
		var kb := float(ItemTypes.get_def(item).knockback)
		feel.knockback_bonus_voxels = 0.0
		var b: float = await _best(p, kb)
		feel.knockback_bonus_voxels = 2.0
		var a: float = await _best(p, kb)
		var want: float = kb * feel.knockback_scale + 2.0
		if absf(a - want) > 0.3:
			bad += 1
		line += " %s kb=%.1f before=%.2f after=%.2f want=%.2f;" % [item, kb, b, a, want]
	var r: float = await _best(p, 1.0, 0.6)
	line += " sword_resist0.6=%.2f want=%.2f;" % [r, 4.0 * 0.4]
	print("P7_KNOCK2%s %s" % [line, "OK" if bad == 0 else "FAIL bad=%d" % bad])
	quit()