extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const SIZES := [Vector2i(1152, 648), Vector2i(1024, 768), Vector2i(864, 648), Vector2i(1280, 720)]


func _init() -> void:
	call_deferred("_run")


func _text_of(c: Control) -> String:
	if c is Label:
		return (c as Label).text
	if c is RichTextLabel:
		return (c as RichTextLabel).get_parsed_text()
	if c is Button:
		return (c as Button).text
	return ""


func _text_width(c: Control, t: String) -> float:
	var font: Font = c.get_theme_font("font") if not (c is RichTextLabel) else c.get_theme_font("normal_font")
	var fs: int = c.get_theme_font_size("font_size") if not (c is RichTextLabel) else c.get_theme_font_size("normal_font_size")
	var w := 0.0
	for line in t.split("\n"):
		w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return w


func _visible_in_tree(n: Node) -> bool:
	var p: Node = n
	while p != null:
		if p is CanvasItem and not (p as CanvasItem).visible:
			return false
		if p is CanvasLayer and not (p as CanvasLayer).visible:
			return false
		p = p.get_parent()
	return true


func _collect(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is CanvasLayer and not (n as CanvasLayer).visible:
		return
	if n is Control and _text_of(n).strip_edges() != "":
		out.append(n)
	for ch in n.get_children():
		_collect(ch, out)


func _run() -> void:
	var game: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
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
		_collect(root, items)
		var bad := 0
		for c in items:
			var ctl := c as Control
			var r := ctl.get_global_rect()
			var t := _text_of(ctl).strip_edges()
			var tw := _text_width(ctl, t) * ctl.get_global_transform().get_scale().x
			var x0 := r.position.x
			var x1 := r.end.x
			if ctl is Label:
				var al := (ctl as Label).horizontal_alignment
				if al == HORIZONTAL_ALIGNMENT_RIGHT:
					x0 = minf(x0, r.end.x - tw)
				elif al == HORIZONTAL_ALIGNMENT_CENTER:
					x0 = minf(x0, r.get_center().x - tw * 0.5)
					x1 = maxf(x1, r.get_center().x + tw * 0.5)
				else:
					x1 = maxf(x1, r.position.x + tw)
				if (ctl as Label).clip_text or (ctl as Label).autowrap_mode != TextServer.AUTOWRAP_OFF or (ctl as Label).text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING:
					x0 = r.position.x
					x1 = r.end.x
				if (ctl as Label).autowrap_mode != TextServer.AUTOWRAP_OFF and float((ctl as Label).get_line_count()) * float((ctl as Label).get_line_height()) > r.size.y + 2.0:
					bad += 1
					print("CLIP %s %s wrapped lines=%d rect_h=%.0f" % [s, ctl.get_path(), (ctl as Label).get_line_count(), r.size.y])
				if (ctl as Label).autowrap_mode == TextServer.AUTOWRAP_OFF and tw > r.size.x + 1.0 and ((ctl as Label).clip_text or (ctl as Label).text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING):
					bad += 1
					print("CLIP %s %s text_w=%.0f rect_w=%.0f text=%s" % [s, ctl.get_path(), tw, r.size.x, t.left(60).replace("\n", " | ")])
			var out := x0 < -1.0 or x1 > view.x + 1.0 or r.position.y < -1.0 or r.end.y > view.y + 1.0
			if out:
				bad += 1
				print("CUT %s %s text_x=[%.0f,%.0f] rect=%s text=%s" % [s, ctl.get_path(), x0, x1, r, t.left(40).replace("\n", " | ")])
		print("SIZE %s view=%s texts=%d cut=%d" % [s, view, items.size(), bad])
		total += bad
	print("P6_HUD cut=%d %s" % [total, "OK" if total == 0 else "FAIL"])
	quit(0 if total == 0 else 1)
