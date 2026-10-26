extends SceneTree

const _Inventory = preload("res://inventory/inventory.gd")

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	print("FAIL " + msg)


func _key(code: int, pressed: bool, shift: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code as Key
	ev.keycode = code as Key
	ev.shift_pressed = shift
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _run() -> void:
	var skills := Node.new()
	skills.set_script(load("res://systems/skill_service.gd"))
	root.add_child(skills)
	skills._unlocked[&"dash"] = true
	skills.equip(0, &"dash")
	var bar := Control.new()
	bar.set_script(load("res://ui/skill_bar.gd"))
	root.add_child(bar)
	var weapon := Node.new()
	weapon.set_script(load("res://weapons/weapon_controller.gd"))
	root.add_child(weapon)
	weapon.inventory = _Inventory.new()
	weapon.select_hotbar(4)
	var fired: Array = []
	skills.skill_activated.connect(func(slot: int, id: StringName) -> void: fired.append([slot, String(id)]))
	await process_frame
	await process_frame
	var idle: Dictionary = bar.slot_text(0)
	if idle.name != "Dash" or idle.key != "Shift+1" or idle.cooldown != "":
		_fail("idle slot %s" % str(idle))

	_key(KEY_1, true, true)
	await process_frame
	await process_frame
	_key(KEY_1, false, true)
	await process_frame
	if fired != [[0, "dash"]]:
		_fail("Shift+1 fired %s" % str(fired))
	if weapon.get_active_hotbar_index() != 4:
		_fail("Shift+1 changed hotbar to %d" % weapon.get_active_hotbar_index())
	if bar.slot_text(0).cooldown == "":
		_fail("cooldown label empty after dash")
	skills.release_cooldown(0)
	await process_frame
	await process_frame
	if bar.slot_text(0).cooldown != "":
		_fail("cooldown label did not clear")

	_key(KEY_1, true, false)
	await process_frame
	_key(KEY_1, false, false)
	await process_frame
	if fired.size() != 1:
		_fail("plain 1 fired a skill")
	if weapon.get_active_hotbar_index() != 0:
		_fail("plain 1 did not select slot 1")

	if _failed == 0:
		print("All skill bar checks OK")
		quit(0)
	else:
		quit(1)
