extends Node3D
## Root scene script for scenes/main.tscn.
##
## Boot is owned by CompositionRoot (child node):
##   CONFIGURED → QUALITY_APPLIED → FEATURES_SEEDED → CHUNKS_CREATED
##   → INITIAL_STREAM_READY → VISUALS_COMMITTED → RUNNING
## Critical services are registered and handed off explicitly; groups remain
## compatibility adapters for UI/debug discovery.
##
## LoadingScreen presents actual start-region bake/stream occupancy and fades
## out at INITIAL_STREAM_READY (required nearby chunks resident). Gameplay
## input stays blocked until that gate. Background fill may continue after.


const _StartupTotal = preload("res://systems/startup_total_profiler.gd")
const _WorldManager = preload("res://systems/world_manager.gd")
const _PlayerSettings = preload("res://systems/player_settings.gd")


func _ready() -> void:
	add_to_group("game")
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
		push_warning("[Main] CompositionRoot missing — legacy child _ready boot only")


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
	_ensure_dev_input_actions()


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


func _apply_catalog_launch() -> void:
	_PlayerSettings.apply_to_tree(get_tree())
	var launch: Dictionary = _WorldManager.take_pending_launch()
	if launch.is_empty():
		return
	var world = get_node_or_null("World")
	if world and world.has_method("apply_seed"):
		world.apply_seed(int(launch.get("seed", world.world_seed if "world_seed" in world else 12349)))
	print("[Main] Catalog launch world=%s seed=%s" % [str(launch.get("name", "")), str(launch.get("seed", ""))])


func return_to_world_select() -> void:
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
