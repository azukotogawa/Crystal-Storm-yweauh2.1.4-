extends Node3D


const _StartupTotal = preload("res://systems/startup_total_profiler.gd")
const _WorldManager = preload("res://systems/world_manager.gd")
const _PlayerSettings = preload("res://systems/player_settings.gd")

var _quit_save_started: bool = false


func _ready() -> void:
	add_to_group("game")
	_ensure_day_night()
	_bind_alive_quit_save()
	_ensure_live_inspector()
	if _StartupTotal.is_enabled():
		if _StartupTotal.now_us() <= 0:
			_StartupTotal.begin_session("main_scene")
		_StartupTotal.event("main._ready", {}, "scene_load")
	_apply_catalog_launch()
	var root = get_node_or_null("CompositionRoot")
	var loading = get_node_or_null("LoadingLayer/LoadingScreen")
	if loading == null:
		loading = get_node_or_null("CanvasLayer/LoadingScreen")
	if loading and root and loading.has_method("bind_composition_root"):
		loading.bind_composition_root(root)
	if root and root.has_method("boot_async"):
		if _StartupTotal.is_enabled():
			_StartupTotal.begin("boot_async", "synchronous_main")
		await root.boot_async()
		if _StartupTotal.is_enabled():
			_StartupTotal.end("boot_async")
			_StartupTotal.event("main.boot_async_returned", {}, "first_playable_frame")
	else:
		push_warning("[Main] CompositionRoot missing Ã¢â‚¬â€ legacy child _ready boot only")
	# After services register against direct Game children, move 3D into the low-res SubViewport.
	call_deferred("_pixel_look_install")
	_ensure_day_night()


func _ensure_day_night() -> void:
	var world_parent: Node = self
	var pixel = get_node_or_null("PixelLookController")
	if pixel != null and pixel.has_method("get_content_parent"):
		world_parent = pixel.get_content_parent()
	if get_node_or_null("DayNightClock") == null and (world_parent == self or world_parent.get_node_or_null("DayNightClock") == null):
		var clock := Node.new()
		clock.name = "DayNightClock"
		clock.set_script(load("res://world/day_night_clock.gd"))
		world_parent.add_child(clock)
	if get_node_or_null("TorchField") == null and (world_parent == self or world_parent.get_node_or_null("TorchField") == null):
		var field := Node3D.new()
		field.name = "TorchField"
		field.set_script(load("res://world/torch_field.gd"))
		world_parent.add_child(field)


func _ensure_live_inspector() -> void:
	if get_node_or_null("LiveWorldInspector") != null:
		return
	var insp := CanvasLayer.new()
	insp.name = "LiveWorldInspector"
	insp.set_script(load("res://ui/live_world_inspector.gd"))
	add_child(insp)
	if get_node_or_null("DevToolsCoordinator") == null:
		var coord := Node.new()
		coord.name = "DevToolsCoordinator"
		coord.set_script(load("res://systems/dev_tools_coordinator.gd"))
		add_child(coord)
	if get_node_or_null("PauseMenu") == null:
		var pause := CanvasLayer.new()
		pause.name = "PauseMenu"
		pause.set_script(load("res://ui/pause_menu.gd"))
		add_child(pause)
	if get_node_or_null("SkillTree") == null:
		var tree := CanvasLayer.new()
		tree.name = "SkillTree"
		tree.set_script(load("res://ui/skill_tree_panel.gd"))
		add_child(tree)
	_ensure_f3_overlay()
	_ensure_debug_view_layer()
	_ensure_dev_input_actions()


func _ensure_f3_overlay() -> void:
	if get_node_or_null("F3Overlay") != null:
		return
	var packed := load("res://scenes/f3_overlay.tscn") as PackedScene
	if packed == null:
		return
	var overlay := packed.instantiate()
	overlay.name = "F3Overlay"
	add_child(overlay)


func _ensure_debug_view_layer() -> void:
	var world_parent: Node = self
	var pixel = get_node_or_null("PixelLookController")
	if pixel != null and pixel.has_method("get_content_parent"):
		world_parent = pixel.get_content_parent()
	if get_node_or_null("DebugViewLayer") != null:
		return
	if world_parent != self and world_parent.get_node_or_null("DebugViewLayer") != null:
		return
	var views := Node3D.new()
	views.name = "DebugViewLayer"
	views.set_script(load("res://helpers/debug_view_layer.gd"))
	world_parent.add_child(views)


func _ensure_dev_input_actions() -> void:
	if not InputMap.has_action("debug_overlay_toggle"):
		InputMap.add_action("debug_overlay_toggle")
		var f3 := InputEventKey.new()
		f3.physical_keycode = KEY_F3
		InputMap.action_add_event("debug_overlay_toggle", f3)
	if not InputMap.has_action("bug_report"):
		InputMap.add_action("bug_report")
		var f11 := InputEventKey.new()
		f11.physical_keycode = KEY_F11
		InputMap.action_add_event("bug_report", f11)
	if not InputMap.has_action("debug_panel_toggle"):
		InputMap.add_action("debug_panel_toggle")
		var f7 := InputEventKey.new()
		f7.physical_keycode = KEY_F7
		InputMap.action_add_event("debug_panel_toggle", f7)


func _apply_catalog_launch() -> void:
	_PlayerSettings.apply_to_tree(get_tree())
	var launch: Dictionary = _WorldManager.take_pending_launch()
	if launch.is_empty():
		return
	var world = get_node_or_null("World")
	if world and world.has_method("apply_seed"):
		world.apply_seed(int(launch.get("seed", world.world_seed if "world_seed" in world else 12349)))
	print("[Main] Catalog launch world=%s seed=%s" % [str(launch.get("name", "")), str(launch.get("seed", ""))])


## Godot 4.7 does not pass NOTIFICATION_WM_CLOSE_REQUEST on to nodes.
## The root window emits close_requested. With auto-accept off, that signal
## is the only chance to write the alive snapshot before the process ends.
func _bind_alive_quit_save() -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.set_auto_accept_quit(false)
	var win := tree.root
	if win and not win.close_requested.is_connected(_on_close_requested):
		win.close_requested.connect(_on_close_requested)


func _on_close_requested() -> void:
	if _quit_save_started:
		return
	_quit_save_started = true
	_save_quit_while_alive()
	var tree := get_tree()
	if tree:
		tree.quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_on_close_requested()


func _exit_tree() -> void:
	var tree := get_tree()
	if tree:
		tree.set_auto_accept_quit(true)


func _save_quit_while_alive() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var save = tree.get_first_node_in_group("save_game_service")
	if save and save.has_method("save_or_drop_continue"):
		save.save_or_drop_continue()


func return_to_world_select() -> void:
	var save = get_tree().get_first_node_in_group("save_game_service")
	var world_id := str(_WorldManager.active_world_id)
	if save and save.has_method("save_or_drop_continue"):
		save.save_or_drop_continue()
	elif save and world_id != "" and save.has_method("save_world_id"):
		save.save_world_id(world_id, true)
	_WorldManager.request_return_to_select()
	var bake = load("res://world/world_bake_service.gd").get_active()
	if bake != null and bake.has_method("_clear_job_queue"):
		bake._clear_job_queue()
		bake.bake_in_progress = false
		bake.forbid_session_replace = false
	var cm = get_tree().get_first_node_in_group("chunk_manager")
	if cm and cm.has_method("release_all_chunks_for_teardown"):
		cm.release_all_chunks_for_teardown()
	var tree := get_tree()
	if tree.current_scene == self:
		tree.change_scene_to_file("res://scenes/frontend.tscn")
		return
	var packed: PackedScene = load("res://scenes/frontend.tscn") as PackedScene
	if packed:
		tree.root.add_child(packed.instantiate())
	queue_free()
