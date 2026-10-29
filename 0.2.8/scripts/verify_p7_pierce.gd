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


func _pair(p, w, id: String) -> Array:
	w.set_active_hotbar_index(_slot(w, id))
	var dv := _dir(p, 4)
	var a = await C.spawn_mite(self, C.pcol(p) + dv * 2)
	var b = await C.spawn_mite(self, C.pcol(p) + dv * 3)
	for _f in 30:
		await physics_frame
	C.point_at(p, a.get_combat_center())
	for _f in 6:
		await process_frame
	w._cooldown_timer = 0.0
	var ha: float = a.health
	var hb: float = b.health
	w._try_attack()
	for _f in 90:
		await physics_frame
	var out := [1 if a.health < ha else 0, 1 if b.health < hb else 0]
	await C.clear_mites(self)
	for _f in 10:
		await physics_frame
	return out


func _run() -> void:
	var tag := OS.get_environment("P7_TAG")
	var p = await C.boot(self)
	p.camera.zoom_level = 48.0
	p.camera.size = 48.0
	var GI = preload("res://helpers/gameplay_input.gd")
	GI.modal_open = false
	GI.pause_open = false
	GI.world_loading = false
	p.health = 100000.0
	var w = C.weapon(p)
	var line := ""
	var res := {}
	for id in ["wooden_sword", "spear", "crystal_hammer"]:
		var r: Array = await _pair(p, w, id)
		res[id] = r
		line += " %s near=%d far=%d;" % [id, r[0], r[1]]
	var ok: bool = res["wooden_sword"] == [1, 0] and res["crystal_hammer"] == [1, 1]
	print("P7_M tag=%s%s %s" % [tag, line, "OK" if ok else "FAIL"])
	quit(0)