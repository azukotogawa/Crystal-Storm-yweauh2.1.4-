extends Control
## Player-facing shell: MAIN MENU → WORLD SELECT → NEW WORLD → GAME, plus SETTINGS.

const _WorldManager = preload("res://systems/world_manager.gd")
const _PlayerSettings = preload("res://systems/player_settings.gd")
const _PerformanceQualityConfig = preload("res://config/performance_quality_config.gd")

enum Screen { MAIN, WORLD_SELECT, NEW_WORLD, SETTINGS }

const COL_BG := Color(0.04, 0.05, 0.10, 1.0)
const COL_TITLE := Color(0.78, 0.92, 1.0, 1.0)
const COL_SUB := Color(0.55, 0.72, 0.88, 0.95)
const COL_MUTED := Color(0.45, 0.58, 0.70, 0.9)
const COL_PANEL := Color(0.08, 0.10, 0.16, 0.94)
const COL_ACCENT := Color(0.45, 0.78, 0.95, 1.0)
const COL_DANGER := Color(0.85, 0.38, 0.42, 1.0)

var _screen: Screen = Screen.MAIN
var _stack: Control
var _selected_id: String = ""
var _status: Label
var _world_list: VBoxContainer
var _name_edit: LineEdit
var _seed_edit: LineEdit
var _rename_edit: LineEdit
var _confirm_layer: Control
var _preset_opt: OptionButton
var _rd_slider: HSlider
var _veg_slider: HSlider
var _fx_check: CheckBox


func _ready() -> void:
	add_to_group("frontend_root")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_chrome()
	if _WorldManager.consume_return_to_select():
		_show(Screen.WORLD_SELECT)
	else:
		_show(Screen.MAIN)


func _build_chrome() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = COL_BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var vignette := ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.02, 0.02, 0.05, 0.35)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)
	_stack = Control.new()
	_stack.name = "Screens"
	_stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_stack)
	_confirm_layer = Control.new()
	_confirm_layer.name = "ConfirmLayer"
	_confirm_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.visible = false
	_confirm_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_confirm_layer)


func _clear_stack() -> void:
	for c in _stack.get_children():
		c.queue_free()
	_status = null
	_world_list = null


func _show(which: Screen) -> void:
	_screen = which
	_clear_stack()
	match which:
		Screen.MAIN:
			_build_main()
		Screen.WORLD_SELECT:
			_build_world_select()
		Screen.NEW_WORLD:
			_build_new_world()
		Screen.SETTINGS:
			_build_settings()


func _card() -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stack.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 420)
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = Color(0.25, 0.45, 0.65, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	return box


func _title(box: Control, text: String, sub: String = "") -> void:
	var t := Label.new()
	t.text = text
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 36)
	t.add_theme_color_override("font_color", COL_TITLE)
	t.add_theme_color_override("font_outline_color", Color(0.15, 0.35, 0.55, 0.9))
	t.add_theme_constant_override("outline_size", 4)
	box.add_child(t)
	if not sub.is_empty():
		var s := Label.new()
		s.text = sub
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.add_theme_font_size_override("font_size", 15)
		s.add_theme_color_override("font_color", COL_SUB)
		box.add_child(s)


func _btn(text: String, on_press: Callable, danger: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 36)
	if danger:
		b.add_theme_color_override("font_color", COL_DANGER)
	else:
		b.add_theme_color_override("font_color", COL_ACCENT)
	b.pressed.connect(on_press)
	return b


func _set_status(msg: String) -> void:
	if _status:
		_status.text = msg


func _build_main() -> void:
	var box := _card()
	_title(box, "CRYSTAL STORM", "Maze. Dig. Survive.")
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	box.add_child(spacer)
	var play := _btn("Play", func(): _show(Screen.WORLD_SELECT))
	play.name = "Play"
	var settings := _btn("Settings", func(): _show(Screen.SETTINGS))
	settings.name = "Settings"
	var quit_b := _btn("Quit", func(): get_tree().quit())
	quit_b.name = "Quit"
	box.add_child(play)
	box.add_child(settings)
	box.add_child(quit_b)


func _build_world_select() -> void:
	var box := _card()
	box.get_parent().custom_minimum_size = Vector2(640, 520)
	_title(box, "Worlds", "Choose a world to enter")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 180)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_world_list = VBoxContainer.new()
	_world_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_world_list)
	_refresh_world_list()
	_rename_edit = LineEdit.new()
	_rename_edit.placeholder_text = "Rename selected world"
	box.add_child(_rename_edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var play_w := _btn("Play", _on_play_selected)
	play_w.name = "PlayWorld"
	var new_w := _btn("New World", func(): _show(Screen.NEW_WORLD))
	new_w.name = "NewWorld"
	row.add_child(play_w)
	row.add_child(new_w)
	box.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	row2.add_child(_btn("Rename", _on_rename_selected))
	row2.add_child(_btn("Delete", _on_delete_selected, true))
	row2.add_child(_btn("Back", func(): _show(Screen.MAIN)))
	box.add_child(row2)
	_status = Label.new()
	_status.add_theme_color_override("font_color", COL_MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_set_status("Select a world, or create a new one.")


func _refresh_world_list() -> void:
	if _world_list == null:
		return
	for c in _world_list.get_children():
		c.queue_free()
	var worlds: Array = _WorldManager.list_worlds()
	if worlds.is_empty():
		var empty := Label.new()
		empty.text = "No worlds yet."
		empty.add_theme_color_override("font_color", COL_MUTED)
		_world_list.add_child(empty)
		return
	for w_v in worlds:
		var w: Dictionary = w_v
		var id := str(w.get("id", ""))
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = id == _selected_id
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var last := int(w.get("last_played_unix", 0))
		var last_s := "Never"
		if last > 0:
			last_s = Time.get_datetime_string_from_unix_time(last)
		var bake_s := "Ready" if not bool(w.get("bake_incomplete", true)) else str(w.get("progress", "Incomplete"))
		b.text = "%s    seed %d    %s    %s" % [str(w.get("name", "")), int(w.get("seed", 0)), last_s, bake_s]
		b.pressed.connect(_on_select_world.bind(id))
		_world_list.add_child(b)


func _on_select_world(world_id: String) -> void:
	_selected_id = world_id
	var row: Dictionary = _WorldManager.get_world(world_id)
	if row.is_empty():
		return
	_set_status("%s  ·  seed %d  ·  %s" % [row.get("name", ""), int(row.get("seed", 0)), row.get("progress", "")])
	_refresh_world_list()


func _on_play_selected() -> void:
	if _selected_id.is_empty():
		_set_status("Select a world first.")
		return
	var loaded: Dictionary = _WorldManager.load_world(_selected_id)
	if not bool(loaded.get("ok", false)):
		_set_status("Could not load world.")
		return
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_rename_selected() -> void:
	if _selected_id.is_empty():
		_set_status("Select a world to rename.")
		return
	var name := _rename_edit.text if _rename_edit else ""
	var res: Dictionary = _WorldManager.rename_world(_selected_id, name)
	if not bool(res.get("ok", false)):
		_set_status("Rename failed: %s" % str(res.get("error", "")))
		return
	_set_status("Renamed to %s." % str(res.get("name", name)))
	_refresh_world_list()


func _on_delete_selected() -> void:
	if _selected_id.is_empty():
		_set_status("Select a world to delete.")
		return
	_show_delete_confirm(_selected_id)


func _show_delete_confirm(world_id: String) -> void:
	for c in _confirm_layer.get_children():
		c.queue_free()
	_confirm_layer.visible = true
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	_confirm_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 160)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var row: Dictionary = _WorldManager.get_world(world_id)
	var lab := Label.new()
	lab.text = "Delete \"%s\"? This cannot be undone." % str(row.get("name", "world"))
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(lab)
	var rowb := HBoxContainer.new()
	rowb.add_theme_constant_override("separation", 8)
	var cancel := _btn("Cancel", func():
		_confirm_layer.visible = false
	)
	var yes := _btn("Delete", func():
		var res: Dictionary = _WorldManager.delete_world(world_id, true)
		_confirm_layer.visible = false
		if bool(res.get("ok", false)):
			_selected_id = ""
			_set_status("World deleted.")
		else:
			_set_status("Delete failed.")
		_refresh_world_list()
	, true)
	yes.name = "ConfirmDelete"
	cancel.name = "CancelDelete"
	rowb.add_child(cancel)
	rowb.add_child(yes)
	box.add_child(rowb)


func _build_new_world() -> void:
	var box := _card()
	_title(box, "New World", "Name a world and choose its seed")
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "World name"
	_name_edit.text = "New Storm"
	box.add_child(_name_edit)
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "Seed"
	_seed_edit.text = str(12349)
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed_edit)
	seed_row.add_child(_btn("Randomize", _on_randomize_seed))
	box.add_child(seed_row)
	var create_b := _btn("Create", _on_create_world)
	create_b.name = "CreateWorld"
	var back_n := _btn("Back", func(): _show(Screen.WORLD_SELECT))
	back_n.name = "Back"
	box.add_child(create_b)
	box.add_child(back_n)
	_status = Label.new()
	_status.add_theme_color_override("font_color", COL_MUTED)
	box.add_child(_status)


func _on_randomize_seed() -> void:
	if _seed_edit:
		_seed_edit.text = str(randi() % 100000000)


func _on_create_world() -> void:
	var name := _name_edit.text if _name_edit else ""
	var seed := int(_seed_edit.text) if _seed_edit and _seed_edit.text.is_valid_int() else 12349
	var res: Dictionary = _WorldManager.create_world(name, seed)
	if not bool(res.get("ok", false)):
		_set_status("Could not create: %s" % str(res.get("error", "")))
		return
	_selected_id = str(res.get("id", ""))
	_show(Screen.WORLD_SELECT)
	_set_status("Created %s." % str(res.get("name", name)))


func _build_settings() -> void:
	var box := _card()
	_title(box, "Settings", "Existing graphics and view options")
	var data: Dictionary = _PlayerSettings.load_settings()
	var preset_l := Label.new()
	preset_l.text = "Graphics quality"
	preset_l.add_theme_color_override("font_color", COL_SUB)
	box.add_child(preset_l)
	_preset_opt = OptionButton.new()
	_preset_opt.add_item("Low", int(_PerformanceQualityConfig.Preset.LOW))
	_preset_opt.add_item("Medium", int(_PerformanceQualityConfig.Preset.MEDIUM))
	_preset_opt.add_item("High", int(_PerformanceQualityConfig.Preset.HIGH))
	_preset_opt.add_item("Safe", int(_PerformanceQualityConfig.Preset.SAFE))
	var want: int = int(data.get("quality_preset", _PerformanceQualityConfig.Preset.MEDIUM))
	for i in _preset_opt.item_count:
		if _preset_opt.get_item_id(i) == want:
			_preset_opt.select(i)
			break
	box.add_child(_preset_opt)
	var rd_l := Label.new()
	rd_l.text = "Render distance"
	rd_l.add_theme_color_override("font_color", COL_SUB)
	box.add_child(rd_l)
	_rd_slider = HSlider.new()
	_rd_slider.min_value = 1
	_rd_slider.max_value = 8
	_rd_slider.step = 1
	_rd_slider.value = int(data.get("render_distance", 2))
	box.add_child(_rd_slider)
	var veg_l := Label.new()
	veg_l.text = "Vegetation density"
	veg_l.add_theme_color_override("font_color", COL_SUB)
	box.add_child(veg_l)
	_veg_slider = HSlider.new()
	_veg_slider.min_value = 0
	_veg_slider.max_value = 1
	_veg_slider.step = 0.05
	_veg_slider.value = float(data.get("vegetation_scatter_multiplier", 1.0))
	box.add_child(_veg_slider)
	_fx_check = CheckBox.new()
	_fx_check.text = "Combat effects"
	_fx_check.button_pressed = bool(data.get("combat_visuals_enabled", true))
	box.add_child(_fx_check)
	box.add_child(_btn("Save", _on_save_settings))
	box.add_child(_btn("Back", func(): _show(Screen.MAIN)))
	_status = Label.new()
	_status.add_theme_color_override("font_color", COL_MUTED)
	box.add_child(_status)


func _on_save_settings() -> void:
	var preset := int(_PerformanceQualityConfig.Preset.MEDIUM)
	if _preset_opt:
		preset = _preset_opt.get_item_id(_preset_opt.selected)
	var data := {
		"quality_preset": preset,
		"render_distance": int(_rd_slider.value) if _rd_slider else 2,
		"vegetation_scatter_multiplier": float(_veg_slider.value) if _veg_slider else 1.0,
		"combat_visuals_enabled": bool(_fx_check.button_pressed) if _fx_check else true,
	}
	if _PlayerSettings.save_settings(data):
		_set_status("Settings saved.")
	else:
		_set_status("Could not save settings.")
