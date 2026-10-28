extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1366, 768)]


func _init() -> void:
	call_deferred("_run")


func _full(c: Control, view: Vector2) -> bool:
	var r := c.get_global_rect()
	return r.size.x * r.size.y > view.x * view.y * 0.4


func _widget_root(c: Control, view: Vector2) -> Control:
	var best := c
	var n: Node = c.get_parent()
	while n != null and n is Control:
		if not _full(n, view):
			best = n
		n = n.get_parent()
	return best


func _draws(c: Control) -> bool:
	if c is Label:
		return (c as Label).text.strip_edges() != ""
	return c is Button or c is Panel or c is PanelContainer or c is TextureRect or c is ProgressBar or c is ColorRect or c is RichTextLabel


func _collect(n: Node, out: Array, view: Vector2) -> void:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is CanvasLayer and not (n as CanvasLayer).visible:
		return
	if n is Control:
		var c := n as Control
		if _draws(c) and not _full(c, view) and Rect2(Vector2.ZERO, view).encloses(c.get_global_rect().grow(-1.0)) and c.get_global_rect().size.x > 1.0 and c.get_global_rect().size.y > 1.0:
			out.append(c)
	for ch in n.get_children():
		_collect(ch, out, view)


func _run() -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	var game: Node = packed.instantiate()
	root.add_child(game)
	var player = null
	for _i in 1800:
		player = get_first_node_in_group("player")
		if player and bool(player.get("world_ready")):
			break
		await process_frame
	for _i in 240:
		await process_frame
	var total := 0
	for s in SIZES:
		root.content_scale_size = s
		for _i in 30:
			await process_frame
		var view := Vector2(root.get_visible_rect().size)
		var items: Array = []
		_collect(root, items, view)
		var roots := {}
		for c in items:
			var w: Control = _widget_root(c, view)
			if not roots.has(w):
				roots[w] = []
			roots[w].append(c)
		var keys: Array = roots.keys()
		var bad := 0
		for i in keys.size():
			for j in range(i + 1, keys.size()):
				var a: Control = keys[i]
				var b: Control = keys[j]
				if a.is_ancestor_of(b) or b.is_ancestor_of(a):
					continue
				if a.get_global_rect().grow(1.0).encloses(b.get_global_rect()) or b.get_global_rect().grow(1.0).encloses(a.get_global_rect()):
					continue
				var hit := false
				for ca in roots[a]:
					for cb in roots[b]:
						if (ca as Control).get_global_rect().grow(-1.0).intersects((cb as Control).get_global_rect().grow(-1.0)):
							if not hit:
								print("  pair %s %s / %s %s" % [(ca as Control).name, (ca as Control).get_global_rect(), (cb as Control).name, (cb as Control).get_global_rect()])
							hit = true
				if hit:
					bad += 1
					print("OVERLAP %s %s %s <-> %s %s" % [s, a.get_path(), a.get_global_rect(), b.get_path(), b.get_global_rect()])
		print("SIZE %s view=%s widgets=%d overlaps=%d" % [s, view, keys.size(), bad])
		for k in keys:
			print("  W %s %s" % [(k as Control).get_path(), (k as Control).get_global_rect()])
		total += bad
	print("P5 HUD " + ("OK" if total == 0 else "FAIL") + " overlaps=%d" % total)
	quit(0 if total == 0 else 1)
