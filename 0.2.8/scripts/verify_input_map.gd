extends SceneTree

const _InputBindings = preload("res://systems/input_bindings.gd")

var _failed := 0


func _init() -> void:
	_check_table()
	_check_conflicts()
	_check_hotbar_has_no_shift()
	_check_no_hardcoded_keys()
	_check_attack_is_mouse_only()
	if _failed > 0:
		push_error("verify_input_map: %d failure(s)" % _failed)
		quit(1)
		return
	print("All input map tests OK")
	quit(0)


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)


func _check_table() -> void:
	for action in _InputBindings.ACTIONS:
		if not InputMap.has_action(action) or InputMap.action_get_events(action).is_empty():
			_fail("action %s has no binding" % action)
		if not _InputBindings.LABELS.has(action):
			_fail("action %s has no label" % action)
	for want in ["skill_1", "skill_2", "skill_3", "skill_tree", "hotbar_9", "hotbar_10", "rotate_piece", "rotate_piece_back", "place_variant", "hotbar_next", "hotbar_prev", "camera_zoom_in", "camera_zoom_out", "camera_reset", "camera_free_look"]:
		if not _InputBindings.ACTIONS.has(want):
			_fail("table is missing %s" % want)
	for gone in ["channel_water"]:
		if _InputBindings.ACTIONS.has(gone) or InputMap.has_action(gone):
			_fail("%s must not exist" % gone)
	print("OK every action has a binding and a label")


func _check_conflicts() -> void:
	var clashes: Array = []
	for action in _InputBindings.ACTIONS:
		for ev in InputMap.action_get_events(action):
			var other := _InputBindings.conflict_for(action, ev)
			if other != "":
				clashes.append("%s vs %s" % [action, other])
	if not clashes.is_empty():
		_fail("actions share key and modifiers: %s" % str(clashes))
	else:
		print("OK no two actions share key and modifiers")


func _check_hotbar_has_no_shift() -> void:
	for i in range(1, 11):
		for ev in InputMap.action_get_events("hotbar_%d" % i):
			if ev is InputEventKey and (ev as InputEventKey).shift_pressed:
				_fail("hotbar_%d uses Shift" % i)
	for i in range(1, 4):
		var shifted := false
		for ev in InputMap.action_get_events("skill_%d" % i):
			if ev is InputEventKey and (ev as InputEventKey).shift_pressed:
				shifted = true
		if not shifted:
			_fail("skill_%d is not on Shift+number" % i)
	print("OK hotbar has no Shift and skills use Shift+number")


func _check_attack_is_mouse_only() -> void:
	for ev in InputMap.action_get_events("attack"):
		if not ev is InputEventMouseButton:
			_fail("attack has a non-mouse binding")
	print("OK attack is mouse only")


func _check_no_hardcoded_keys() -> void:
	var banned := ["KEY_Z", "KEY_X", "KEY_BRACKET", "is_key_pressed(KEY_SHIFT", "is_key_pressed(KEY_CTRL", "is_physical_key_pressed(KEY_Z", "MOUSE_BUTTON_WHEEL"]
	var hits: Array = []
	for dir in ["weapons", "player"]:
		_scan("res://" + dir, banned, hits)
	if not hits.is_empty():
		_fail("hard-coded gameplay keys remain: %s" % str(hits))
	else:
		print("OK no hard-coded gameplay keys in weapons and player")


func _scan(path: String, banned: Array, hits: Array) -> void:
	for file in DirAccess.get_files_at(path):
		if not file.ends_with(".gd"):
			continue
		var text := FileAccess.get_file_as_string(path + "/" + file)
		for word in banned:
			if word in text:
				hits.append("%s/%s %s" % [path, file, word])
	for sub in DirAccess.get_directories_at(path):
		_scan(path + "/" + sub, banned, hits)
