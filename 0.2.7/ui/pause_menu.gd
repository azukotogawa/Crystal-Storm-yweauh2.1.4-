extends CanvasLayer
## ESC pause: Resume, Settings (real PlayerSettings only), World Select, Quit.

const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _PlayerSettings = preload("res://systems/player_settings.gd")
const _PerformanceQualityConfig = preload("res://config/performance_quality_config.gd")

var _root: Control
var _settings_box: VBoxContainer
var _preset: OptionButton
var _rd: HSlider
var _veg: HSlider
var _fx: CheckBox
var _shake: CheckBox
var _hit_stop: CheckBox
var _flash: CheckBox
var _vol_master: HSlider
var _vol_music: HSlider
var _vol_sfx: HSlider
var _vol_ui: HSlider


func _ready() -> void:
	add_to_group("pause_menu")
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if _GameplayInput.dev_chat_open:
			return
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	visible = true
	_GameplayInput.pause_open = true
	get_tree().paused = true
	_sync_settings_widgets()
	_refresh_debug_overlay()
	_ui("ui_open")


func close() -> void:
	visible = false
	_GameplayInput.pause_open = false
	get_tree().paused = false
	_refresh_debug_overlay()
	_ui("ui_close")


func _refresh_debug_overlay() -> void:
	var panel = get_tree().get_first_node_in_group("debug_panel") if get_tree() else null
	if panel and panel.has_method("refresh_now"):
		panel.refresh_now()


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.06, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_root = CenterContainer.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.14, 0.96)
	sb.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(320, 460)
	_root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	v.add_child(title)
	_btn(v, "Resume", close)
	_btn(v, "Settings", _toggle_settings)
	_settings_box = VBoxContainer.new()
	_settings_box.visible = false
	_settings_box.add_theme_constant_override("separation", 4)
	v.add_child(_settings_box)
	_preset = OptionButton.new()
	_preset.add_item("Low", _PerformanceQualityConfig.Preset.LOW)
	_preset.add_item("Medium", _PerformanceQualityConfig.Preset.MEDIUM)
	_preset.add_item("High", _PerformanceQualityConfig.Preset.HIGH)
	_preset.item_selected.connect(_on_preset_selected)
	_settings_box.add_child(_preset)
	_rd = HSlider.new()
	_rd.min_value = 1
	_rd.max_value = 6
	_rd.step = 1
	_rd.value_changed.connect(func(_v): _on_settings_changed(0))
	_settings_box.add_child(_rd)
	_veg = HSlider.new()
	_veg.min_value = 0
	_veg.max_value = 1
	_veg.step = 0.05
	_veg.value_changed.connect(func(_v): _on_settings_changed(0))
	_settings_box.add_child(_veg)
	_fx = CheckBox.new()
	_fx.text = "Combat visuals"
	_fx.toggled.connect(func(_v): _on_settings_changed(0))
	_settings_box.add_child(_fx)
	_shake = _check("Screen shake")
	_hit_stop = _check("Hit stop")
	_flash = _check("Hit flash")
	_settings_box.add_child(_shake)
	_settings_box.add_child(_hit_stop)
	_settings_box.add_child(_flash)
	_vol_master = _volume_slider("Master volume")
	_vol_music = _volume_slider("Music volume")
	_vol_sfx = _volume_slider("SFX volume")
	_vol_ui = _volume_slider("UI volume")
	_btn(v, "Return to World Select", _leave)
	_btn(v, "Quit", _quit)


func _btn(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 32)
	b.pressed.connect(func(): _ui("ui_click"))
	b.pressed.connect(cb)
	b.mouse_entered.connect(func(): _ui("ui_hover"))
	parent.add_child(b)


func _check(text: String) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.toggled.connect(func(_v): _on_settings_changed(0))
	return box


func _volume_slider(text: String) -> HSlider:
	var label := Label.new()
	label.text = text
	_settings_box.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value_changed.connect(func(_v): _on_settings_changed(0))
	_settings_box.add_child(slider)
	return slider


func _ui(id: String) -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_ui"):
		audio.play_ui(id)


func _toggle_settings() -> void:
	_settings_box.visible = not _settings_box.visible
	_sync_settings_widgets()


func _sync_settings_widgets() -> void:
	var data: Dictionary = _PlayerSettings.load_settings()
	if _preset:
		var p: int = int(data.get("quality_preset", _PerformanceQualityConfig.Preset.MEDIUM))
		_preset.set_block_signals(true)
		for i in _preset.item_count:
			if _preset.get_item_id(i) == p:
				_preset.select(i)
				break
		_preset.set_block_signals(false)
	_set_slider(_rd, float(data.get("render_distance", 2)))
	_set_slider(_veg, float(data.get("vegetation_scatter_multiplier", 1.0)))
	if _fx:
		_set_check(_fx, bool(data.get("combat_visuals_enabled", true)))
	_set_check(_shake, bool(data.get("screen_shake_enabled", true)))
	_set_check(_hit_stop, bool(data.get("hit_stop_enabled", true)))
	_set_check(_flash, bool(data.get("flash_effects_enabled", true)))
	_set_slider(_vol_master, float(data.get("volume_master", 1.0)))
	_set_slider(_vol_music, float(data.get("volume_music", 1.0)))
	_set_slider(_vol_sfx, float(data.get("volume_sfx", 1.0)))
	_set_slider(_vol_ui, float(data.get("volume_ui", 1.0)))


func _on_preset_selected(idx: int) -> void:
	if _preset == null or _rd == null:
		_on_settings_changed(idx)
		return
	var pid: int = _preset.get_item_id(_preset.selected)
	var cfg: _PerformanceQualityConfig
	if pid == _PerformanceQualityConfig.Preset.SAFE:
		cfg = _PerformanceQualityConfig.apply_safe_mode()
	else:
		cfg = _PerformanceQualityConfig.apply_preset(pid)
	_rd.value = int(cfg.render_distance)
	_veg.value = float(cfg.vegetation_scatter_multiplier)
	_on_settings_changed(idx)


func _set_check(box: CheckBox, pressed: bool) -> void:
	if box == null:
		return
	box.set_block_signals(true)
	box.button_pressed = pressed
	box.set_block_signals(false)


func _set_slider(slider: HSlider, value: float) -> void:
	if slider == null:
		return
	slider.set_block_signals(true)
	slider.value = value
	slider.set_block_signals(false)


func _on_settings_changed(_idx: int) -> void:
	var data := _PlayerSettings.load_settings()
	data["quality_preset"] = _preset.get_item_id(_preset.selected) if _preset else int(data.get("quality_preset", _PerformanceQualityConfig.Preset.MEDIUM))
	data["render_distance"] = int(_rd.value) if _rd else int(data.get("render_distance", 2))
	data["vegetation_scatter_multiplier"] = float(_veg.value) if _veg else float(data.get("vegetation_scatter_multiplier", 1.0))
	data["combat_visuals_enabled"] = bool(_fx.button_pressed) if _fx else bool(data.get("combat_visuals_enabled", true))
	data["screen_shake_enabled"] = bool(_shake.button_pressed) if _shake else bool(data.get("screen_shake_enabled", true))
	data["hit_stop_enabled"] = bool(_hit_stop.button_pressed) if _hit_stop else bool(data.get("hit_stop_enabled", true))
	data["flash_effects_enabled"] = bool(_flash.button_pressed) if _flash else bool(data.get("flash_effects_enabled", true))
	data["volume_master"] = float(_vol_master.value) if _vol_master else float(data.get("volume_master", 1.0))
	data["volume_music"] = float(_vol_music.value) if _vol_music else float(data.get("volume_music", 1.0))
	data["volume_sfx"] = float(_vol_sfx.value) if _vol_sfx else float(data.get("volume_sfx", 1.0))
	data["volume_ui"] = float(_vol_ui.value) if _vol_ui else float(data.get("volume_ui", 1.0))
	_PlayerSettings.save_settings(data)
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("apply_saved_volumes"):
		audio.apply_saved_volumes()
	var perf = get_tree().get_first_node_in_group("performance_service")
	var root = get_tree().get_first_node_in_group("composition_root")
	var registry = root.get("registry") if root and "registry" in root else null
	_PlayerSettings.apply_to_performance(perf)
	if perf and registry and perf.has_method("apply_to_registered"):
		perf.apply_to_registered(registry, {})


func _leave() -> void:
	close()
	var game = get_tree().get_first_node_in_group("game")
	if game and game.has_method("return_to_world_select"):
		game.return_to_world_select()
	else:
		get_tree().change_scene_to_file("res://scenes/frontend.tscn")


func _quit() -> void:
	get_tree().quit()
