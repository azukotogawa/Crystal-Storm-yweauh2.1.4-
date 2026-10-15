extends SceneTree


const _MapScript = preload("res://ui/topographical_map.gd")
const _Builder = preload("res://systems/topographical_map_builder.gd")
const _MapConfig = preload("res://config/topographical_map_config.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _Quality = preload("res://config/performance_quality_config.gd")

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	push_error("FAIL " + msg)
	_failed = true


func _run() -> void:
	_GameplayInput.map_open = false
	_GameplayInput.pause_open = false
	_GameplayInput.dev_chat_open = false
	_GameplayInput.world_loading = false
	_check_binding()
	_check_builder_extent()
	await _check_ui()
	_GameplayInput.map_open = false
	_GameplayInput.pause_open = false
	_GameplayInput.dev_chat_open = false
	_GameplayInput.world_loading = false
	if _failed:
		quit(1)
		return
	print("All full map toggle tests OK")
	quit(0)


func _check_binding() -> void:
	var owners := _plain_key_actions(KEY_M)
	if owners.size() != 1 or owners[0] != "toggle_map":
		_fail("plain M must belong only to toggle_map, got %s" % str(owners))
	else:
		print("OK M is toggle_map")
	if _action_has_key("toggle_map", KEY_U):
		_fail("toggle_map must no longer be U")
	else:
		print("OK toggle_map is not U")
	if not _action_has_key("jump", KEY_SPACE):
		_fail("jump must stay Space")
	elif _action_has_key("jump", KEY_M):
		_fail("jump must not be M")
	else:
		print("OK jump stays Space")
	var src := (_MapScript as GDScript).source_code
	if 'Input.is_action_just_pressed("toggle_map")' not in src:
		_fail("map process must read toggle_map")
	else:
		print("OK map reads toggle_map")


func _check_builder_extent() -> void:
	var cfg := _MapConfig.create_default()
	var mini: Dictionary = _Builder.begin_job(null, null, Vector2i.ZERO, cfg, false, true, 2)
	var full: Dictionary = _Builder.begin_job(null, null, Vector2i.ZERO, cfg, true, true, 2)
	var mini_span := int(mini.size) * int(mini.stride)
	var full_span := int(full.size) * int(full.stride)
	if bool(mini.get("fullscreen", false)) or not bool(full.get("fullscreen", false)):
		_fail("fullscreen flag missing on the full job")
	elif int(full.display_size) <= int(mini.display_size):
		_fail("full map display should be larger than the minimap")
	elif full_span <= mini_span:
		_fail("full map should cover more columns than the minimap")
	elif int(full.display_size) != cfg.fullscreen_size:
		_fail("full map display size changed")
	else:
		print("OK full map covers more than the minimap")


func _check_ui() -> void:
	var map = _MapScript.new()
	root.add_child(map)
	await process_frame
	map.set_process(false)
	var panel: Control = map._fullscreen_panel
	var hint: Label = map._map_key_hint
	if panel == null or hint == null:
		_fail("fullscreen panel or M hint missing")
		map.queue_free()
		await process_frame
		return
	if hint.text != "M":
		_fail("minimap hint should say M")
	if panel.visible or map.is_fullscreen_open() or _GameplayInput.map_open:
		_fail("map should start closed")
	else:
		print("OK map starts closed")

	var world := InfiniteNoiseWorld.new(7)
	map._world = world
	if not map.toggle_fullscreen_map():
		_fail("first toggle should open the map")
	elif not panel.visible or not map.is_fullscreen_open():
		_fail("open toggle should show the panel")
	elif panel.mouse_filter != Control.MOUSE_FILTER_STOP:
		_fail("open map should catch clicks")
	elif map.z_index < 1:
		_fail("open map should draw above the HUD")
	elif not _GameplayInput.blocks_actions() or not _GameplayInput.map_open:
		_fail("open map should block movement and digging")
	elif not _queue_has_fullscreen(map):
		_fail("opening should queue a fullscreen sample")
	else:
		var full_job := _fullscreen_job(map)
		var cfg = map._map_cfg()
		if int(full_job.get("display_size", 0)) != int(cfg.fullscreen_size):
			_fail("queued full map is not the fullscreen size")
		else:
			print("OK M opens the full map and blocks actions")

	if map.toggle_fullscreen_map():
		_fail("second toggle should close the map")
	elif panel.visible or map.is_fullscreen_open() or _GameplayInput.map_open or _GameplayInput.blocks_actions():
		_fail("closed map should hide and release actions")
	elif panel.mouse_filter != Control.MOUSE_FILTER_IGNORE or map.z_index != 0:
		_fail("closed map should release the mouse and z order")
	else:
		print("OK second toggle closes the map")

	map.toggle_fullscreen_map()
	_GameplayInput.pause_open = true
	map.handle_toggle_action(true)
	if map.is_fullscreen_open() or _GameplayInput.map_open:
		_fail("pause should close the map and ignore M")
	else:
		print("OK pause closes the map")
	_GameplayInput.pause_open = false

	map.toggle_fullscreen_map()
	_GameplayInput.dev_chat_open = true
	map.handle_toggle_action(false)
	if map.is_fullscreen_open():
		_fail("dev chat should close the map")
	else:
		print("OK dev chat closes the map")
	_GameplayInput.dev_chat_open = false

	map.toggle_fullscreen_map()
	_GameplayInput.world_loading = true
	map.handle_toggle_action(true)
	if map.is_fullscreen_open():
		_fail("world loading should close the map")
	else:
		print("OK loading closes the map")
	_GameplayInput.world_loading = false

	var safe = _Quality.apply_safe_mode()
	map.toggle_fullscreen_map()
	map.apply_performance_config(safe)
	if map.is_fullscreen_open() or safe.map_fullscreen_enabled:
		_fail("safe mode should keep the full map closed")
	else:
		print("OK safe mode closes the full map")

	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_M
	ev.keycode = KEY_M
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	var saw := Input.is_action_just_pressed("toggle_map")
	map._fullscreen_map_enabled = true
	map.handle_toggle_action(saw)
	if not saw:
		_fail("flushed M should press toggle_map")
	elif not map.is_fullscreen_open():
		_fail("flushed M should open the map")
	else:
		print("OK flushed M opens the map")
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()

	map.queue_free()
	world.free()
	await process_frame
	if _GameplayInput.map_open:
		_fail("freeing the map should clear map_open")
	else:
		print("OK freeing the map clears map_open")


func _plain_key_actions(code: Key) -> PackedStringArray:
	var found := PackedStringArray()
	for action in InputMap.get_actions():
		for event in InputMap.action_get_events(action):
			if not event is InputEventKey:
				continue
			var key := event as InputEventKey
			var bound := key.physical_keycode if key.physical_keycode != 0 else key.keycode
			if bound != code:
				continue
			if key.shift_pressed or key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
				continue
			found.append(String(action))
	return found


func _action_has_key(action: String, code: Key) -> bool:
	if not InputMap.has_action(action):
		return false
	for event in InputMap.action_get_events(action):
		if not event is InputEventKey:
			continue
		var key := event as InputEventKey
		var bound := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		if bound == code:
			return true
	return false


func _queue_has_fullscreen(map) -> bool:
	return not _fullscreen_job(map).is_empty()


func _fullscreen_job(map) -> Dictionary:
	var active: Dictionary = map._active_map_job
	if bool(active.get("fullscreen", false)):
		return active
	for job in map._map_job_queue:
		if bool(job.get("fullscreen", false)):
			return job
	return {}
