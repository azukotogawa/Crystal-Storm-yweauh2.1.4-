class_name SettingsMenu
extends ScrollContainer
## Shared settings body for the frontend and the pause menu.
## Writes through PlayerSettings. Opening syncs with signals blocked, so it does not save.

const _PlayerSettings = preload("res://systems/player_settings.gd")
const _InputBindings = preload("res://systems/input_bindings.gd")
const _PerformanceQualityConfig = preload("res://config/performance_quality_config.gd")
const _ThemeBuilder = preload("res://ui/theme/theme_builder.gd")
const _Tutorial = preload("res://ui/tutorial_overlay.gd")

const RESOLUTIONS: PackedStringArray = ["1280x720", "1366x768", "1600x900", "1920x1080", "2560x1440"]

var _preset: OptionButton
var _rd: HSlider
var _veg: HSlider
var _fx: CheckBox
var _shake: CheckBox
var _hit_stop: CheckBox
var _flash: CheckBox
var _reduce: CheckBox
var _colorblind: CheckBox
var _vol_master: HSlider
var _vol_music: HSlider
var _vol_sfx: HSlider
var _vol_ui: HSlider
var _fullscreen: CheckBox
var _vsync: CheckBox
var _resolution: OptionButton
var _ui_scale: HSlider
var _ui_scale_label: Label
var _conflict: Label
var _bind_rows: Dictionary = {}
var _listen_action: String = ""
var _listen_after_msec: int = 0
var _status: Label


func _ready() -> void:
	_ThemeBuilder.apply(self)
	custom_minimum_size = Vector2(300, 280)
	horizontal_scroll_mode = SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_section(box, "Graphics")
	_preset = OptionButton.new()
	_preset.name = "QualityPreset"
	_preset.add_item("Low", int(_PerformanceQualityConfig.Preset.LOW))
	_preset.add_item("Medium", int(_PerformanceQualityConfig.Preset.MEDIUM))
	_preset.add_item("High", int(_PerformanceQualityConfig.Preset.HIGH))
	_preset.add_item("Safe", int(_PerformanceQualityConfig.Preset.SAFE))
	_preset.item_selected.connect(_on_preset_selected)
	box.add_child(_preset)
	_rd = _slider(box, "Render distance", 1, 8, 1, "RenderDistance")
	_veg = _slider(box, "Vegetation density", 0, 1, 0.05, "Vegetation")
	_fx = _check(box, "Combat visuals", "CombatVisuals")
	_section(box, "Audio")
	_vol_master = _slider(box, "Master volume", 0, 1, 0.05, "VolumeMaster")
	_vol_music = _slider(box, "Music volume", 0, 1, 0.05, "VolumeMusic")
	_vol_sfx = _slider(box, "SFX volume", 0, 1, 0.05, "VolumeSFX")
	_vol_ui = _slider(box, "UI volume", 0, 1, 0.05, "VolumeUI")
	_section(box, "Display")
	_fullscreen = _check(box, "Fullscreen", "Fullscreen")
	_vsync = _check(box, "VSync", "Vsync")
	var res_l := Label.new()
	res_l.text = "Resolution (windowed)"
	box.add_child(res_l)
	_resolution = OptionButton.new()
	_resolution.name = "Resolution"
	for res in RESOLUTIONS:
		_resolution.add_item(res)
	_resolution.item_selected.connect(func(_i): _persist())
	box.add_child(_resolution)
	_ui_scale_label = Label.new()
	_ui_scale_label.text = "UI scale"
	box.add_child(_ui_scale_label)
	_ui_scale = _slider(box, "", 0.75, 1.5, 0.05, "UiScale")
	_section(box, "Accessibility")
	_reduce = _check(box, "Reduce motion", "ReduceMotion")
	_shake = _check(box, "Screen shake", "ScreenShake")
	_hit_stop = _check(box, "Hit stop", "HitStop")
	_flash = _check(box, "Hit flash", "HitFlash")
	_colorblind = _check(box, "Colour-blind crystal palette", "ColorblindPalette")
	_section(box, "Controls")
	var hint := Label.new()
	hint.text = "Click a binding, then press a key or mouse button. Escape cancels."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	_conflict = Label.new()
	_conflict.name = "ConflictWarning"
	_conflict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_conflict.add_theme_color_override("font_color", Color(0.95, 0.55, 0.45))
	box.add_child(_conflict)
	for action in _InputBindings.ACTIONS:
		_add_bind_row(box, action)
	var reset := Button.new()
	reset.text = "Reset bindings"
	reset.pressed.connect(_on_reset_bindings)
	box.add_child(reset)
	var how := Button.new()
	how.text = "How to play"
	how.pressed.connect(func(): _Tutorial.open(get_tree(), true))
	box.add_child(how)
	var controls := Button.new()
	controls.text = "Controls"
	controls.pressed.connect(func(): _Tutorial.open_controls(get_tree()))
	box.add_child(controls)
	_status = Label.new()
	_status.name = "SettingsStatus"
	box.add_child(_status)
	sync_from_settings()
	if not _PlayerSettings.runtime_applied:
		_PlayerSettings.apply_runtime(get_tree())


func _section(box: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.78, 0.62, 1.0))
	box.add_child(label)


func _slider(box: VBoxContainer, text: String, min_v: float, max_v: float, step: float, node_name: String) -> HSlider:
	if text != "":
		var label := Label.new()
		label.text = text
		box.add_child(label)
	var slider := HSlider.new()
	slider.name = node_name
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(180, 20)
	slider.value_changed.connect(func(_v): _persist())
	box.add_child(slider)
	return slider


func _check(box: VBoxContainer, text: String, node_name: String) -> CheckBox:
	var box_check := CheckBox.new()
	box_check.name = node_name
	box_check.text = text
	box_check.toggled.connect(func(_v): _persist())
	box.add_child(box_check)
	return box_check


func _add_bind_row(box: VBoxContainer, action: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_l := Label.new()
	name_l.text = _InputBindings.label_of(action)
	name_l.custom_minimum_size = Vector2(140, 0)
	row.add_child(name_l)
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_begin_listen.bind(action))
	row.add_child(button)
	box.add_child(row)
	_bind_rows[action] = button


func sync_from_settings() -> void:
	var data: Dictionary = _PlayerSettings.load_settings()
	_set_preset(int(data.get("quality_preset", _PerformanceQualityConfig.Preset.MEDIUM)))
	_set_slider(_rd, float(data.get("render_distance", 2)))
	_set_slider(_veg, float(data.get("vegetation_scatter_multiplier", 1.0)))
	_set_check(_fx, bool(data.get("combat_visuals_enabled", true)))
	_set_slider(_vol_master, float(data.get("volume_master", 1.0)))
	_set_slider(_vol_music, float(data.get("volume_music", 1.0)))
	_set_slider(_vol_sfx, float(data.get("volume_sfx", 1.0)))
	_set_slider(_vol_ui, float(data.get("volume_ui", 1.0)))
	_set_check(_fullscreen, bool(data.get("fullscreen", false)))
	_set_check(_vsync, bool(data.get("vsync", true)))
	_set_resolution(str(data.get("resolution", "1280x720")))
	_set_slider(_ui_scale, float(data.get("ui_scale", 1.0)))
	_set_check(_reduce, bool(data.get("reduce_motion", false)))
	_set_check(_shake, bool(data.get("screen_shake_enabled", true)))
	_set_check(_hit_stop, bool(data.get("hit_stop_enabled", true)))
	_set_check(_flash, bool(data.get("flash_effects_enabled", true)))
	_set_check(_colorblind, bool(data.get("colorblind_palette", false)))
	_apply_reduce_motion_lock()
	_refresh_scale_label()
	_refresh_bindings()
	if _resolution:
		_resolution.disabled = bool(_fullscreen.button_pressed) if _fullscreen else false


func set_volume(bus: String, value: float) -> void:
	var slider := _slider_for_bus(bus)
	if slider == null:
		return
	slider.value = clampf(value, 0.0, 1.0)


func set_ui_scale(scale: float) -> void:
	if _ui_scale == null:
		_PlayerSettings.set_ui_scale(scale)
		return
	_ui_scale.value = clampf(scale, 0.75, 1.5)


func _slider_for_bus(bus: String) -> HSlider:
	match bus:
		"Music":
			return _vol_music
		"SFX":
			return _vol_sfx
		"UI":
			return _vol_ui
		_:
			return _vol_master


func _begin_listen(action: String) -> void:
	_listen_action = action
	_listen_after_msec = Time.get_ticks_msec() + 180
	if _conflict:
		_conflict.text = "Press a key for %s" % _InputBindings.label_of(action)
	var button: Button = _bind_rows.get(action)
	if button:
		button.text = "Press a key..."
	set_process_input(true)


func _input(event: InputEvent) -> void:
	if _listen_action == "":
		return
	if not is_visible_in_tree():
		_listen_action = ""
		return
	if Time.get_ticks_msec() < _listen_after_msec:
		if event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		if key.physical_keycode == KEY_ESCAPE:
			_cancel_listen()
			get_viewport().set_input_as_handled()
			return
		_commit_listen(key)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed:
			return
		_commit_listen(button)
		get_viewport().set_input_as_handled()


func _cancel_listen() -> void:
	_listen_action = ""
	if _conflict:
		_conflict.text = "Rebind cancelled."
	_refresh_bindings()


func _commit_listen(event: InputEvent) -> void:
	var action := _listen_action
	_listen_action = ""
	var warning := _PlayerSettings.bind_action(action, event)
	if warning != "":
		if _conflict:
			_conflict.text = "%s is already used by %s." % [_InputBindings.event_label(event), warning]
	else:
		if _conflict:
			_conflict.text = ""
		if _status:
			_status.text = "Binding saved."
	_refresh_bindings()


func _on_reset_bindings() -> void:
	_listen_action = ""
	_PlayerSettings.reset_bindings()
	if _conflict:
		_conflict.text = "Bindings reset to defaults."
	_refresh_bindings()
	if _status:
		_status.text = "Defaults restored."


func _on_preset_selected(_idx: int) -> void:
	if _preset == null:
		_persist()
		return
	var pid: int = _preset.get_item_id(_preset.selected)
	var cfg: _PerformanceQualityConfig
	if pid == _PerformanceQualityConfig.Preset.SAFE:
		cfg = _PerformanceQualityConfig.apply_safe_mode()
	else:
		cfg = _PerformanceQualityConfig.apply_preset(pid)
	_set_slider(_rd, float(cfg.render_distance))
	_set_slider(_veg, float(cfg.vegetation_scatter_multiplier))
	_persist()


func _persist() -> void:
	if not is_inside_tree():
		return
	var data := _PlayerSettings.load_settings()
	if _preset:
		data["quality_preset"] = _preset.get_item_id(_preset.selected)
	if _rd:
		data["render_distance"] = int(_rd.value)
	if _veg:
		data["vegetation_scatter_multiplier"] = float(_veg.value)
	if _fx:
		data["combat_visuals_enabled"] = bool(_fx.button_pressed)
	if _vol_master:
		data["volume_master"] = float(_vol_master.value)
	if _vol_music:
		data["volume_music"] = float(_vol_music.value)
	if _vol_sfx:
		data["volume_sfx"] = float(_vol_sfx.value)
	if _vol_ui:
		data["volume_ui"] = float(_vol_ui.value)
	if _fullscreen:
		data["fullscreen"] = bool(_fullscreen.button_pressed)
	if _vsync:
		data["vsync"] = bool(_vsync.button_pressed)
	if _resolution and _resolution.selected >= 0:
		data["resolution"] = _resolution.get_item_text(_resolution.selected)
	if _ui_scale:
		data["ui_scale"] = float(_ui_scale.value)
	var reduce := bool(_reduce.button_pressed) if _reduce else bool(data.get("reduce_motion", false))
	data["reduce_motion"] = reduce
	if reduce:
		data["screen_shake_enabled"] = false
		data["hit_stop_enabled"] = false
		_set_check(_shake, false)
		_set_check(_hit_stop, false)
	else:
		if _shake:
			data["screen_shake_enabled"] = bool(_shake.button_pressed)
		if _hit_stop:
			data["hit_stop_enabled"] = bool(_hit_stop.button_pressed)
	if _flash:
		data["flash_effects_enabled"] = bool(_flash.button_pressed)
	if _colorblind:
		data["colorblind_palette"] = bool(_colorblind.button_pressed)
	_apply_reduce_motion_lock()
	if _resolution and _fullscreen:
		_resolution.disabled = bool(_fullscreen.button_pressed)
	_refresh_scale_label()
	var display_changed := (
		bool(data.get("fullscreen", false)) != _PlayerSettings.fullscreen
		or bool(data.get("vsync", true)) != _PlayerSettings.vsync_enabled
		or str(data.get("resolution", "")) != _PlayerSettings.resolution
	)
	var scale_changed := absf(float(data.get("ui_scale", 1.0)) - _PlayerSettings.ui_scale) > 0.001
	if not _PlayerSettings.save_settings(data):
		if _status:
			_status.text = "Could not save settings."
		return
	if scale_changed:
		_PlayerSettings.apply_ui_scale(get_tree())
	if display_changed:
		_PlayerSettings.apply_display()
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("apply_saved_volumes"):
		audio.apply_saved_volumes()
	var tree := get_tree()
	_PlayerSettings.apply_accessibility(tree)
	var perf = tree.get_first_node_in_group("performance_service") if tree else null
	var root = tree.get_first_node_in_group("composition_root") if tree else null
	var registry = root.get("registry") if root and "registry" in root else null
	_PlayerSettings.apply_to_performance(perf)
	if perf and registry and perf.has_method("apply_to_registered"):
		perf.apply_to_registered(registry, {})
	if _status and _status.text != "Binding saved." and _status.text != "Defaults restored.":
		_status.text = "Saved."


func _apply_reduce_motion_lock() -> void:
	var locked := bool(_reduce.button_pressed) if _reduce else false
	if _shake:
		_shake.disabled = locked
	if _hit_stop:
		_hit_stop.disabled = locked


func _refresh_scale_label() -> void:
	if _ui_scale_label and _ui_scale:
		_ui_scale_label.text = "UI scale  %d%%" % int(round(_ui_scale.value * 100.0))


func _refresh_bindings() -> void:
	for action in _bind_rows.keys():
		var button: Button = _bind_rows[action]
		if button and action != _listen_action:
			button.text = _InputBindings.binding_text(str(action))


func _set_preset(pid: int) -> void:
	if _preset == null:
		return
	_preset.set_block_signals(true)
	for i in _preset.item_count:
		if _preset.get_item_id(i) == pid:
			_preset.select(i)
			break
	_preset.set_block_signals(false)


func _set_resolution(text: String) -> void:
	if _resolution == null:
		return
	_resolution.set_block_signals(true)
	var found := false
	for i in _resolution.item_count:
		if _resolution.get_item_text(i) == text:
			_resolution.select(i)
			found = true
			break
	if not found:
		_resolution.add_item(text)
		_resolution.select(_resolution.item_count - 1)
	_resolution.set_block_signals(false)


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
