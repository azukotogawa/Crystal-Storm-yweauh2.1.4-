extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")
const GIb = preload("res://helpers/gameplay_input.gd")


func _init() -> void:
	call_deferred("_run")


func _slot(w, id: String) -> int:
	for i in 9:
		var it = w.inventory.get_hotbar_item(i)
		if it != null and it.id == id:
			return i
	w.inventory.add_item(id, 1)
	for i in 9:
		var it = w.inventory.get_hotbar_item(i)
		if it != null and it.id == id:
			return i
	return -1


func _dir(p, dist: int) -> Vector2i:
	var cam: Camera3D = p.camera
	var vsz: Vector2 = p.get_viewport().get_visible_rect().size
	var best := -1.0
	var out := Vector2i(1, 0)
	for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var sp: Vector2 = cam.unproject_position(C.col_center(C.pcol(p) + dv * dist, p.global_position.y))
		var margin: float = minf(minf(sp.x, vsz.x - sp.x), minf(sp.y, vsz.y - sp.y))
		if margin > best:
			best = margin
			out = dv
	return out


func _ground(p, col: Vector2i) -> Vector3:
	var ws = WorldSettings.get_active()
	var y: float = float(p.get("world").get_surface_height(float(col.x) + 0.5, float(col.y) + 0.5)) if p.get("world") else p.global_position.y
	return Vector3(ws.column_to_world(float(col.x) + 0.5), y, ws.column_to_world(float(col.y) + 0.5))


func _swing(p, w, id: String, mite_cols: float, cursor_cols: int, side: bool = false) -> Dictionary:
	w.set_active_hotbar_index(_slot(w, id))
	var dv := _dir(p, cursor_cols)
	var mdir: Vector2i = Vector2i(-dv.y, dv.x) if side else dv
	var m = await C.spawn_mite(self, C.pcol(p) + mdir * int(round(mite_cols)))
	for _f in 30:
		await physics_frame
	var cur := C.pcol(p) + dv * cursor_cols
	C.point_at(p, m.get_combat_center() if cur == C.pcol(m) else C.col_center(cur, m.get_combat_center().y))
	for _f in 6:
		await process_frame
	w._cooldown_timer = 0.0
	var h0: int = m.hits_taken
	var r0: int = w.refused_count
	w._try_attack()
	for _f in 90:
		await physics_frame
	var md: float = Vector2(m.global_position.x - p.global_position.x, m.global_position.z - p.global_position.z).length() / C.vs()
	var out := {"hits": m.hits_taken - h0, "refused": w.refused_count - r0}
	await C.clear_mites(self)
	for _f in 10:
		await physics_frame
	return out


func _run() -> void:
	var tag := OS.get_environment("P7_TAG")
	var p = await C.boot(self)
	p.camera.zoom_level = 48.0
	p.camera.size = 48.0
	for _f in 5:
		await process_frame
	var GI = preload("res://helpers/gameplay_input.gd")
	GI.modal_open = false
	GI.pause_open = false
	GI.world_loading = false
	p.health = 100000.0
	var w = C.weapon(p)
	var line := ""
	var bad := 0
	for id in ["wooden_sword", "spear", "crystal_hammer"]:
		var rng: float = float(ItemTypes.get_def(id).get("range", 2.0))
		var cur := int(round(rng * 2.0))
		var near: Dictionary = await _swing(p, w, id, rng * 0.8, cur)
		var far: Dictionary = await _swing(p, w, id, rng * 1.2, cur)
		var inr: Dictionary = await _swing(p, w, id, rng * 0.8, int(round(rng * 0.8)))
		var sd: Dictionary = await _swing(p, w, id, rng * 0.5, cur, true)
		line += " %s range=%.0f cursor2x: mite0.8x hits=%d refused=%d, mite1.2x hits=%d refused=%d; side_mite0.5x hits=%d; cursor_at_mite0.8x hits=%d;" % [id, rng, near.hits, near.refused, far.hits, far.refused, sd.hits, inr.hits]
		if id == "wooden_sword" and (near.hits <= 0 or far.hits != 0 or far.refused != 0 or sd.hits != 0 or inr.hits <= 0):
			bad += 1
	var pick := _slot(w, "stone_pick")
	w.set_active_hotbar_index(pick)
	var te = w._terrain_editor
	var reach: float = preload("res://player/action_targeting.gd").reach()
	var dv := _dir(p, int(reach * 2.0))
	C.point_at(p, _ground(p, C.pcol(p) + dv * int(reach * 2.0)))
	await physics_frame
	w._cooldown_timer = 0.0
	var r0: int = w.refused_count
	var h0: float = float(p.get("world").get_surface_height(float(C.pcol(p).x + dv.x * int(reach * 2.0)) + 0.5, float(C.pcol(p).y + dv.y * int(reach * 2.0)) + 0.5))
	w._try_attack()
	for _f in 60:
		await physics_frame
	var fail: String = str(te.last_fail_reason) if te else "?"
	line += " pickaxe reach=%.1f cursor2x refused=%d fail_reason='%s'" % [reach, w.refused_count - r0, fail]
	print("P7_L tag=%s%s %s" % [tag, line, "OK" if bad == 0 else "FAIL bad=%d" % bad])
	quit(0)