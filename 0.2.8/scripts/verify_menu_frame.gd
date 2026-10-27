extends SceneTree

const _Layout = preload("res://config/hud_layout.gd")
const _Inventory = preload("res://inventory/inventory.gd")
const _InventoryPanel = preload("res://ui/inventory_panel.gd")
const _PauseMenu = preload("res://ui/pause_menu.gd")
const _SkillTree = preload("res://ui/skill_tree_panel.gd")
const _Tutorial = preload("res://ui/tutorial_overlay.gd")
const _ModalPanel = preload("res://ui/modal_panel.gd")
const _InputBindings = preload("res://systems/input_bindings.gd")

const SIZES := [Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1366, 768), Vector2i(1920, 1080), Vector2i(2560, 1440)]

var _failed := 0
var _sub: SubViewport


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	print("FAIL " + msg)


func _escape() -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.physical_keycode = KEY_ESCAPE
	key.pressed = true
	return key


func _frames(n: int = 3) -> void:
	for i in n:
		await process_frame


func _modal_of(menu: Node) -> Control:
	for child in menu.get_children():
		if child is _ModalPanel:
			return child
	return null


func _run() -> void:
	var scr := GDScript.new()
	scr.source_code = "extends Node3D\nvar inventory = null\n"
	scr.reload()
	var player := Node3D.new()
	player.set_script(scr)
	player.add_to_group("player")
	player.inventory = _Inventory.new()
	root.add_child(player)
	_sub = SubViewport.new()
	_sub.size = SIZES[0]
	_sub.disable_3d = true
	root.add_child(_sub)
	var inv := _InventoryPanel.new()
	_sub.add_child(inv)
	var pause := _PauseMenu.new()
	_sub.add_child(pause)
	var skills := _SkillTree.new()
	_sub.add_child(skills)
	await _frames()
	var layout = _Layout.load_active()
	for size in SIZES:
		_sub.size = size
		await _frames()
		var view := Vector2(size)
		var safe: Rect2 = layout.safe_area(view)
		inv.visible = true
		inv._visible_panel = true
		await _check_open("inventory", _modal_of(inv), view, safe)
		await _check_escape("inventory", _modal_of(inv))
		inv.visible = false
		inv._visible_panel = false
		pause.open()
		await _check_open("pause", _modal_of(pause), view, safe)
		pause.close()
		skills.visible = true
		skills._modal.open()
		await _check_open("skills", skills._modal, view, safe)
		skills.close()
		var tutorial := _Tutorial.new()
		_sub.add_child(tutorial)
		await _frames()
		tutorial.show_controls()
		await _check_open("controls", tutorial._modal, view, safe)
		await _check_controls_scroll(tutorial, view)
		tutorial.close_overlay()
		await _frames()
	await _check_stack()
	_check_groups()
	if _failed == 0:
		print("All menu frame checks OK")
		quit(0)
	else:
		quit(1)


func _check_open(name: String, modal: Control, view: Vector2, safe: Rect2) -> void:
	await _frames()
	if modal == null:
		_fail("%s has no modal panel" % name)
		return
	if not modal.is_visible_in_tree():
		_fail("%s modal is not visible" % name)
		return
	var rect: Rect2 = modal.frame_rect()
	var center := rect.get_center()
	if absf(center.x - view.x * 0.5) > 2.0 or absf(center.y - view.y * 0.5) > 2.0:
		_fail("%s %s not centered in %s" % [name, rect, view])
	if not safe.grow(2.0).encloses(rect):
		_fail("%s %s leaves the safe area %s" % [name, rect, safe])
	if modal.backdrop.mouse_filter != Control.MOUSE_FILTER_STOP:
		_fail("%s backdrop does not capture the mouse" % name)
	var focus := _sub.gui_get_focus_owner()
	if focus == null or not modal.is_ancestor_of(focus):
		_fail("%s did not take focus (%s)" % [name, focus])
	if modal.bar.get_node_or_null("Close") == null or modal.bar.get_node_or_null("CloseHint") == null:
		_fail("%s lacks its close controls" % name)


func _check_escape(name: String, modal: Control) -> void:
	_sub.push_input(_escape())
	await _frames()
	if modal.is_visible_in_tree():
		_fail("%s stayed open after Esc" % name)


func _check_controls_scroll(tutorial: Node, view: Vector2) -> void:
	var modal: Control = tutorial._modal
	var scroll: ScrollContainer = modal.scroll
	if scroll.size.y > view.y * 0.8 + 1.0:
		_fail("controls scroll area %s is taller than 80%% of %s" % [scroll.size.y, view.y])
	scroll.scroll_vertical = 100000
	await _frames()
	var grid: GridContainer = tutorial._grid
	var last := grid.get_child(grid.get_child_count() - 1) as Control
	if not scroll.get_global_rect().grow(2.0).encloses(last.get_global_rect()):
		_fail("scrolling does not reach the last controls row at %s" % view)
	var texts := []
	for child in grid.get_children():
		if child is Label:
			texts.append((child as Label).text)
	for want in ["Rotate piece", "Skill 1", "Next hotbar slot", "Hotbar 10", "Two-finger tap (right click)"]:
		if not texts.has(want):
			_fail("controls list lacks %s" % want)


func _check_groups() -> void:
	var seen := {}
	for group in _InputBindings.GROUPS:
		for action in group[1]:
			seen[action] = true
	for action in _InputBindings.ACTIONS:
		if not seen.has(action):
			_fail("controls groups miss %s" % action)
	print("hotbar_next=%s rotate_piece=%s skill_1=%s build_place=%s hotbar_10=%s" % [
		_InputBindings.binding_text("hotbar_next"),
		_InputBindings.binding_text("rotate_piece"),
		_InputBindings.binding_text("skill_1"),
		_InputBindings.binding_text("build_place"),
		_InputBindings.binding_text("hotbar_10"),
	])


func _focusables(node: Node, out: Array) -> void:
	for child in node.get_children():
		var c := child as Control
		if c == null or not c.visible:
			continue
		if c.focus_mode == Control.FOCUS_ALL:
			out.append(c)
		_focusables(c, out)


func _check_order(name: String, modal: Control) -> void:
	var list := []
	_focusables(modal.content, list)
	for i in range(1, list.size()):
		var a: Rect2 = (list[i - 1] as Control).get_global_rect()
		var b: Rect2 = (list[i] as Control).get_global_rect()
		var same_row := absf(a.position.y - b.position.y) < 4.0
		if not (b.position.y > a.position.y or (same_row and b.position.x >= a.position.x)):
			_fail("%s focus order breaks at %s" % [name, i])
	if list.size() > 1:
		if _sub.gui_get_focus_owner() != list[0]:
			_fail("%s first control is not focused on open" % name)
		for i in range(list.size() - 1):
			if (list[i] as Control).find_next_valid_focus() != list[i + 1]:
				_fail("%s Tab after %s does not reach the next control" % [name, (list[i] as Control).name])


func _check_stack() -> void:
	_sub.size = SIZES[0]
	var pause := _PauseMenu.new()
	_sub.add_child(pause)
	await _frames()
	_sub.push_input(_escape())
	await _frames()
	if not pause.visible:
		_fail("Esc with nothing open did not open the pause menu")
	await _check_order("pause", _modal_of(pause))
	var tutorial := _Tutorial.new()
	tutorial.process_mode = Node.PROCESS_MODE_ALWAYS
	_sub.add_child(tutorial)
	await _frames()
	tutorial.show_controls()
	await _frames()
	await _check_order("controls", tutorial._modal)
	_sub.push_input(_escape())
	await _frames()
	if is_instance_valid(tutorial) and tutorial._modal.is_visible_in_tree() or not pause.visible:
		_fail("Esc must close only the top modal (pause %s)" % [pause.visible])
	_sub.push_input(_escape())
	await _frames()
	if pause.visible:
		_fail("second Esc did not close the pause menu")
	if _sub.gui_get_focus_owner() != null:
		_fail("focus stayed in a closed menu")
