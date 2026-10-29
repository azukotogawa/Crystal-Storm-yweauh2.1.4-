extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")


func _init() -> void:
	call_deferred("_run")


func _measure(tag: String) -> bool:
	var panel = RelicChoicePanel._open
	var vp: Rect2 = panel.get_viewport().get_visible_rect()
	var box: Control = null
	for ch in panel.get_children():
		if ch is PanelContainer:
			box = ch
	var r: Rect2 = box.get_global_rect()
	var off: Vector2 = r.get_center() - vp.get_center()
	var host = panel.get_parent()
	print("P7_RELICDBG %s vp=%s host=%s host_rect=%s self_rect=%s box=%s off=%s" % [tag, vp.size, host.name, host.get_global_rect() if host is Control else "-", panel.get_global_rect(), r, off])
	return off.length() < 4.0 and vp.encloses(r)


func _run() -> void:
	var p = await C.boot(self)
	var ids: Array = []
	for id in ["iron_heart", "swift_boots", "ember_core"]:
		ids.append(id)
	var reg = load("res://relics/relic_registry.gd")
	reg.ensure_builtins()
	ids = ["crystal_ward", "flow_anchor", "mason_glove"]
	RelicChoicePanel.open(self, null, ids, "probe")
	for _f in 10:
		await process_frame
	var ok: bool = await _measure("default")
	var other := Vector2i(1600, 900)
	root.content_scale_size = Vector2i.ZERO
	root.size = other
	DisplayServer.window_set_size(other)
	for _f in 10:
		await process_frame
	var ok2: bool = await _measure("resized")
	print("P7_RELIC tag=%s %s" % [OS.get_environment("P7_TAG"), "OK" if ok and ok2 else "FAIL"])
	quit()