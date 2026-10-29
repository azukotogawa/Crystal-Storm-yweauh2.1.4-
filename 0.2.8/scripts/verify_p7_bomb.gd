extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var p = await C.boot(self)
	p.health = 100000.0
	var w = C.weapon(p)
	var cam: Camera3D = p.camera
	var vsz: Vector2 = p.get_viewport().get_visible_rect().size
	var line := ""
	var worst := 0.0
	var n := 0
	var tag := OS.get_environment("P7_TAG")
	for dist in [2, 4, 6, 7, 8]:
		var dirv := Vector2i(1, 0)
		var best := -INF
		for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var sp: Vector2 = cam.unproject_position(C.col_center(C.pcol(p) + dv * dist, p.global_position.y))
			var margin: float = minf(minf(sp.x, vsz.x - sp.x), minf(sp.y, vsz.y - sp.y))
			if margin > best:
				best = margin
				dirv = dv
		var col: Vector2i = C.pcol(p) + dirv * dist
		var ws = WorldSettings.get_active()
		var gy: float = p.world.get_surface_height(float(col.x) + 0.5, float(col.y) + 0.5) if p.world else p.global_position.y
		var target: Vector3 = C.col_center(col, gy + ws.layer_height())
		C.point_at(p, target)
		await physics_frame
		w.inventory.add_item("crystal_bomb", 1)
		w._cooldown_timer = 0.0
		var thrown: bool = w._throw_bomb("crystal_bomb", ItemTypes.get_def("crystal_bomb"))
		var shots: Array = []
		for c in w.get_children():
			if c is Projectile and c.active:
				shots.append(c)
		var last := Vector3.ZERO
		for _f in 150:
			for s in shots:
				if is_instance_valid(s) and s.active:
					last = s.global_position
			await physics_frame
		var err: float = Vector2(last.x - target.x, last.z - target.z).length() / C.vs()
		n += 1
		worst = maxf(worst, err)
		line += " d%d=%.2f" % [dist, err]
		print("DBG bomb d%d thrown=%s shots=%d margin=%.0f target=%s land=%s" % [dist, thrown, shots.size(), best, target, last])
		for _f in 30:
			await physics_frame
	print("P7_BOMB tag=%s range=%.1f err_cols%s worst=%.2f %s" % [tag, float(ItemTypes.get_def("crystal_bomb").get("range", 6.0)), line, worst, "OK" if worst <= 1.0 else "FAIL"])
	quit()
