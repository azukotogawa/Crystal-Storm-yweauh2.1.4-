extends CanvasLayer

const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _ThemeBuilder = preload("res://ui/theme/theme_builder.gd")
const _Skills = preload("res://systems/skill_service.gd")
const _Passives = preload("res://player/skill_passives.gd")

const TOGGLE_ACTION := "skill_tree"
const TOGGLE_KEY := 75

var _points: Label
var _buttons: Dictionary = {}


func _ready() -> void:
	add_to_group("skill_tree")
	layer = 35
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_ensure_action()
	_build()


func _exit_tree() -> void:
	if visible and get_tree() and not _GameplayInput.pause_open:
		get_tree().paused = false
	if _GameplayInput.skill_tree_open:
		_GameplayInput.skill_tree_open = false


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or not _is_toggle(key):
		return
	if _GameplayInput.pause_open or _GameplayInput.dev_chat_open or _GameplayInput.world_loading or _GameplayInput.map_open:
		return
	toggle()
	var vp := get_viewport()
	if vp:
		vp.set_input_as_handled()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if _GameplayInput.pause_open or _GameplayInput.dev_chat_open or _GameplayInput.world_loading or _GameplayInput.map_open:
		return
	visible = true
	_GameplayInput.skill_tree_open = true
	if get_tree():
		get_tree().paused = true
	_bind_skills()
	_refresh()


func close() -> void:
	visible = false
	_GameplayInput.skill_tree_open = false
	if get_tree() and not _GameplayInput.pause_open:
		get_tree().paused = false
	var vp := get_viewport()
	if vp:
		vp.gui_release_focus()


func _ensure_action() -> void:
	if InputMap.has_action(TOGGLE_ACTION):
		return
	InputMap.add_action(TOGGLE_ACTION)
	var key := InputEventKey.new()
	key.physical_keycode = TOGGLE_KEY
	InputMap.action_add_event(TOGGLE_ACTION, key)


func _is_toggle(key: InputEventKey) -> bool:
	if InputMap.has_action(TOGGLE_ACTION):
		var probe := InputEventKey.new()
		probe.physical_keycode = key.physical_keycode
		probe.pressed = true
		if probe.is_action_pressed(TOGGLE_ACTION):
			return true
	return key.physical_keycode == TOGGLE_KEY


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.06, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var root := CenterContainer.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_ThemeBuilder.apply(root)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(640, 360)
	root.add_child(panel)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	var title := Label.new()
	title.name = "Title"
	title.text = "Skills"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	body.add_child(title)
	_points = Label.new()
	_points.name = "Points"
	_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_points)
	var branches := HBoxContainer.new()
	branches.name = "Branches"
	branches.add_theme_constant_override("separation", 12)
	branches.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(branches)
	_column(branches, _Skills.TREE_FIGHTER, "Fighter")
	_column(branches, _Skills.TREE_MINER, "Miner")
	_column(branches, _Skills.TREE_BUILDER, "Builder")


func _column(parent: Node, tree: StringName, title: String) -> void:
	var col := VBoxContainer.new()
	col.name = String(tree)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	parent.add_child(col)
	var heading := Label.new()
	heading.name = "Heading"
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 16)
	col.add_child(heading)
	for skill_id in _ids(tree):
		var button := Button.new()
		button.name = String(skill_id)
		button.custom_minimum_size = Vector2(0, 36)
		button.pressed.connect(_on_skill_pressed.bind(skill_id))
		col.add_child(button)
		_buttons[skill_id] = button


func _on_skill_pressed(skill_id: StringName) -> void:
	var skills = _skills()
	if skills == null:
		return
	if not skills.is_unlocked(skill_id):
		if not skills.unlock(skill_id):
			_refresh()
			return
	if not skills.is_active(skill_id):
		_refresh()
		return
	for i in skills.ACTIVE_SLOTS:
		if skills.slot_skill(i) == skill_id:
			skills.clear_slot(i)
			_refresh()
			return
	for i in skills.ACTIVE_SLOTS:
		if skills.slot_skill(i) == &"":
			skills.equip(i, skill_id)
			_refresh()
			return


func _bind_skills() -> void:
	var skills = _skills()
	if skills == null:
		return
	if skills.has_signal("skill_unlocked") and not skills.skill_unlocked.is_connected(_refresh_unlocked):
		skills.skill_unlocked.connect(_refresh_unlocked)
	if skills.has_signal("skill_equipped") and not skills.skill_equipped.is_connected(_refresh_equipped):
		skills.skill_equipped.connect(_refresh_equipped)


func _refresh_unlocked(_skill_id: StringName) -> void:
	_refresh()


func _refresh_equipped(_slot: int, _skill_id: StringName) -> void:
	_refresh()


func _refresh() -> void:
	var skills = _skills()
	var points := 0
	if skills != null and skills.has_method("skill_points"):
		points = skills.skill_points()
	if _points:
		_points.text = "Points %d" % points
	for skill_id in _buttons.keys():
		var button: Button = _buttons[skill_id]
		button.text = _caption(skills, skill_id)


func _caption(skills, skill_id: StringName) -> String:
	var title := _title(skill_id)
	if skills == null or not skills.is_unlocked(skill_id):
		return title + "  (locked)"
	if skills.is_active(skill_id):
		for i in skills.ACTIVE_SLOTS:
			if skills.slot_skill(i) == skill_id:
				return "%s  (slot %d)" % [title, i + 1]
		return title + "  (unlocked)"
	return title + "  (on)"


func _title(skill_id: StringName) -> String:
	match skill_id:
		_Passives.FIGHTER:
			return "Tough +%d HP" % int(_Passives.MAX_HP)
		_Passives.MINER:
			return "Quick Mine +%s" % str(_Passives.MINING_SPEED)
		_Passives.BUILDER:
			return "Sturdy +%d HP" % _Passives.STRUCTURE_HP
		&"dash":
			return "Dash"
		&"ground_slam":
			return "Ground Slam"
		&"crystal_pulse":
			return "Crystal Pulse"
		&"quick_wall":
			return "Quick Wall"
		_:
			return String(skill_id)


func _ids(tree: StringName) -> Array:
	var ids: Array = []
	for skill_id in _Skills.CATALOG.keys():
		var spec: Dictionary = _Skills.CATALOG[skill_id]
		if spec.get("tree", &"") == tree:
			ids.append(skill_id)
	ids.sort()
	return ids


func _skills():
	if is_inside_tree():
		var node := get_tree().get_first_node_in_group("skill_service")
		if node != null:
			return node
	return _Skills.get_active()
