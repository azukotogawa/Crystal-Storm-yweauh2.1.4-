extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")
const FR = preload("res://world/feature_registry.gd")
const WSet = preload("res://config/world_settings.gd")


func _run() -> void:
	var tag := OS.get_environment("P7_TAG")
	var p = await C.boot(self)
	var world = get_first_node_in_group("world")
	var lh: float = WSet.get_active().layer_height()
	var towns := FR.get_towns()
	var total := 0
	var good := 0
	for t in towns:
		var hs: Array = t.get("houses", [])
		print("P7_F town=%s center=%s radius=%s houses=%d" % [t.get("name", "?"), str(t.get("center")), str(t.get("radius")), hs.size()])
		for h in hs:
			total += 1
			var o: Vector2i = h.origin
			var w: int = h.w
			var d: int = h.d
			var ground: float = world.get_surface_height(float(o.x + 1), float(o.y + 1))
			var wall_cols := 0
			var wall_hmin := 999.0
			for x in range(o.x, o.x + w):
				for z in [o.y, o.y + d - 1]:
					var c := Vector2i(x, z)
					if c == h.door:
						continue
					wall_cols += 1
					wall_hmin = minf(wall_hmin, (world.get_surface_height(float(x), float(z)) - world.get_surface_height_uncached(float(x), float(z)) + float(h.h) * lh) / lh)
			var dr: Vector2i = h.door
			var door_rise: float = (world.get_surface_height(float(dr.x), float(dr.y)) - ground) / lh
			var part_rise: float = (world.get_surface_height(float(h.partition_x), float(o.y + 1)) - ground) / lh
			var inner_l: float = (world.get_surface_height(float(o.x + 1), float(o.y + d / 2)) - ground) / lh
			var inner_r: float = (world.get_surface_height(float(o.x + w - 2), float(o.y + d / 2)) - ground) / lh
			var corner_rise: float = (world.get_surface_height(float(o.x), float(o.y)) - ground) / lh
			var ok: bool = w >= 5 and d >= 5 and corner_rise >= 3.0 and part_rise >= 3.0 and absf(door_rise) < 1.5 and absf(inner_l) < 1.5 and absf(inner_r) < 1.5
			if ok:
				good += 1
			print("P7_F house w=%d d=%d h=%d corner_rise=%.1f partition_rise=%.1f door_rise=%.1f roomL_rise=%.1f roomR_rise=%.1f ok=%s" % [w, d, int(h.h), corner_rise, part_rise, door_rise, inner_l, inner_r, str(ok)])
	print("P7_F tag=%s towns=%d houses=%d houses_ok=%d" % [tag, towns.size(), total, good])
	quit()


func _init() -> void:
	call_deferred("_run")