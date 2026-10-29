extends SceneTree

const _HeldItemView = preload("res://systems/held_item_view.gd")
const _ItemAnim = preload("res://systems/item_anim.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var view = _HeldItemView.new()
	root.add_child(view)
	await process_frame
	for id in ["wooden_sword", "spear", "crystal_hammer"]:
		view.show_item(id)
		var spec: Dictionary = _ItemAnim.spec_for(id)
		var kind := int(spec.get("kind", 0))
		var imp := float(spec.get("impact_ratio", 0.42))
		var dur := float(spec.get("duration", 0.0))
		var best_u := -1.0
		var best := -1e9
		var mid_u := -1.0
		var mid := 1e9
		var x0 := 0.0
		var x1 := 0.0
		for i in 101:
			var u := i / 100.0
			view._apply_unit(kind, u, imp)
			var p: Vector3 = view._item.position
			if i == 0:
				x0 = p.x
			var score := -p.y if id == "crystal_hammer" else -p.z
			if score > best + 1e-5:
				best = score
				best_u = u
		var sweep_mid := -1.0
		if id == "wooden_sword":
			var lo := 1e9
			var hi := -1e9
			for i in 101:
				view._apply_unit(kind, i / 100.0, imp)
				lo = minf(lo, view._item.position.x)
				hi = maxf(hi, view._item.position.x)
			var c := (lo + hi) * 0.5
			for i in 101:
				view._apply_unit(kind, i / 100.0, imp)
				if absf(view._item.position.x - c) < mid:
					mid = absf(view._item.position.x - c)
					mid_u = i / 100.0
		print("P7_POSEFN id=%s impact_ratio=%.2f extreme_u=%.2f (%s) sweep_mid_u=%.2f dur=%.3f impact_frame60=%d" % [id, imp, best_u, "lowest head" if id == "crystal_hammer" else "farthest forward", mid_u, dur, int(round(imp * dur * 60.0))])
	quit(0)