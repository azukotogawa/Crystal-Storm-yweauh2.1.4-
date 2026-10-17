extends SceneTree

const _Probe = preload("res://helpers/probe_capture.gd")
const _OverlayScene = preload("res://ui/game_overlay.tscn")
const _Hotbar = preload("res://ui/hotbar.gd")
const _Hud = preload("res://scripts/honest_bot/honest_showcase_hud.gd")
const _F3Scene = preload("res://scenes/f3_overlay.tscn")
const _Inventory = preload("res://inventory/inventory.gd")
const _Tutorial = preload("res://ui/tutorial_overlay.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("cs-art-07 shot needs a window")
		quit(1)
		return
	var phase := OS.get_environment("CRYSTALSTORM_ART_PHASE").strip_edges()
	if phase.is_empty():
		phase = "before"
	DisplayServer.window_set_title("Crystal Storm cs-art-07")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	_backdrop()
	var progress = load("res://systems/progression_service.gd").new()
	root.add_child(progress)
	progress.xp = 40
	progress.level = 2
	var player := _player()
	root.add_child(player)
	var overlay: Control = _OverlayScene.instantiate()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)
	var bar := _Hotbar.new()
	bar.name = "Hotbar"
	root.add_child(bar)
	var hud = _Hud.new()
	root.add_child(hud)
	hud.set_readout("1:24.50", "poi:crystal_grove")
	var f3 := _F3Scene.instantiate()
	root.add_child(f3)
	var show_debug := phase != "after"
	if show_debug:
		f3.set_overlay_visible(true)
	for _i in 8:
		await process_frame
	_Tutorial.dismiss()
	for _j in 4:
		await process_frame
	await _Probe.capture_step("cs-art-07-%s-hud" % phase)
	if phase == "after":
		f3.set_overlay_visible(true)
		for _k in 3:
			await process_frame
		await _Probe.capture_step("cs-art-07-after-f3-hud")
	print("CS ART 07 SHOTS %s" % phase)
	quit(0)


func _backdrop() -> void:
	var sky := ColorRect.new()
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.color = Color(0.45, 0.62, 0.28)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(sky)


func _player() -> Node:
	var scr := GDScript.new()
	scr.source_code = """extends Node
signal health_changed(current: float, maximum: float)
var health: float = 72.0
var max_health: float = 100.0
var inventory = null
"""
	scr.reload()
	var player := Node.new()
	player.set_script(scr)
	player.name = "Scout"
	player.add_to_group("player")
	player.inventory = _Inventory.new()
	player.inventory.set_slot(0, "stone_pick", 1)
	player.inventory.set_slot(1, "wooden_sword", 1)
	return player
