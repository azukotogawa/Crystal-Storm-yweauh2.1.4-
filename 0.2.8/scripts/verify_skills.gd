extends SceneTree

const _Skills = preload("res://systems/skill_service.gd")
const _Progression = preload("res://systems/progression_service.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)
	print("FAIL " + msg)


func _run() -> void:
	_check_flag_and_shape()
	_check_registered()
	_check_unlock_and_slots()
	_check_cooldowns()
	_check_hotkeys()
	_check_save_round_trip()
	if _failed == 0:
		print("All skills tests OK")
		quit(0)
	else:
		push_error("verify_skills: %d failure(s)" % _failed)
		quit(1)


func _check_flag_and_shape() -> void:
	if not _Skills.SKILLS_ENABLED:
		_fail("SKILLS_ENABLED must default true")
		return
	if _Skills.ACTIVE_SLOTS != 3 or _Skills.HOTKEY_ACTIONS.size() != 3:
		_fail("active slots must be 3")
		return
	if _Skills.HOTKEY_ACTIONS != ["skill_1", "skill_2", "skill_3"]:
		_fail("hotkey actions drifted")
		return
	var project := FileAccess.get_file_as_string("res://project.godot")
	if not project.contains("skill_1=") or not project.contains("skill_2=") or not project.contains("skill_3="):
		_fail("project input is missing skill hotkeys")
		return
	if project.find("physical_keycode\":67") < 0 or project.find("physical_keycode\":72") < 0 or project.find("physical_keycode\":74") < 0:
		_fail("skill hotkeys must be C, H, and J")
		return
	for tree in [_Skills.TREE_FIGHTER, _Skills.TREE_MINER, _Skills.TREE_BUILDER]:
		var ids: Array = _Skills.new().tree_ids(tree)
		if ids.size() < 1:
			_fail("tree %s is empty" % String(tree))
			return
	if not _Skills.CATALOG.has(&"dash") or not _Skills.CATALOG.has(&"ground_slam"):
		_fail("starter catalog is missing the planned actives")
		return
	if not _Skills.CATALOG.has(&"crystal_pulse") or not _Skills.CATALOG.has(&"quick_wall"):
		_fail("starter catalog is missing crystal pulse or quick wall")
		return
	print("OK skills flag and 3 slots")


func _check_registered() -> void:
	var root_src := FileAccess.get_file_as_string("res://systems/composition_root.gd")
	var scene_src := FileAccess.get_file_as_string("res://scenes/main.tscn")
	var save_src := FileAccess.get_file_as_string("res://systems/save_game_service.gd")
	if not root_src.contains("ID_SKILLS") or not root_src.contains("_register_skills"):
		_fail("composition root does not register skills")
	elif not root_src.contains("&\"skill_service\""):
		_fail("skill service id missing")
	elif not scene_src.contains("SkillService") or not scene_src.contains("res://systems/skill_service.gd"):
		_fail("main scene is missing SkillService")
	elif not save_src.contains("snapshot[\"skills\"]") or not save_src.contains("skills.import_state"):
		_fail("run save does not store skills")
	else:
		print("OK skills registered")


func _host() -> Node:
	var host := Node.new()
	host.name = "SkillHost"
	root.add_child(host)
	return host


func _pair(points: int):
	var host := _host()
	var prog = _Progression.new()
	var skills = _Skills.new()
	host.add_child(prog)
	host.add_child(skills)
	prog.skill_points = points
	return {"host": host, "prog": prog, "skills": skills}


func _drop(pair: Dictionary) -> void:
	var host: Node = pair.host
	host.free()


func _check_unlock_and_slots() -> void:
	var dry = _pair(0)
	if dry.skills.unlock(&"dash"):
		_fail("unlock must refuse when progression has no skill points")
		_drop(dry)
		return
	if dry.prog.skill_points != 0:
		_fail("a refused unlock spent a point")
		_drop(dry)
		return
	_drop(dry)
	var pair = _pair(2)
	var skills = pair.skills
	var prog = pair.prog
	if skills.unlock(&"no_such_skill"):
		_fail("unknown skill unlocked")
		_drop(pair)
		return
	if not skills.unlock(&"dash") or prog.skill_points != 1 or not skills.is_unlocked(&"dash"):
		_fail("dash unlock did not spend one progression point")
		_drop(pair)
		return
	if skills.unlock(&"dash") or prog.skill_points != 1:
		_fail("a second unlock spent another point")
		_drop(pair)
		return
	if skills.equip(0, &"ground_slam"):
		_fail("a locked skill equipped")
		_drop(pair)
		return
	if not skills.unlock(&"fighter_passive") or prog.skill_points != 0:
		_fail("passive unlock did not spend the last point")
		_drop(pair)
		return
	if skills.equip(0, &"fighter_passive"):
		_fail("a passive took an active slot")
		_drop(pair)
		return
	if not skills.equip(0, &"dash") or skills.slot_skill(0) != &"dash":
		_fail("dash did not equip into slot 0")
		_drop(pair)
		return
	if skills.equip(1, &"dash"):
		_fail("the same skill equipped twice")
		_drop(pair)
		return
	if skills.equip(3, &"dash"):
		_fail("slot 3 exists")
		_drop(pair)
		return
	_drop(pair)
	var rich = _pair(3)
	rich.skills.unlock(&"dash")
	rich.skills.unlock(&"ground_slam")
	rich.skills.unlock(&"crystal_pulse")
	if not rich.skills.equip(0, &"dash") or not rich.skills.equip(1, &"ground_slam") or not rich.skills.equip(2, &"crystal_pulse"):
		_fail("three actives did not fill the slots")
		_drop(rich)
		return
	if rich.prog.skill_points != 0:
		_fail("three unlocks left points behind")
		_drop(rich)
		return
	_drop(rich)
	print("OK unlock spends progression points")


func _check_cooldowns() -> void:
	var pair = _pair(1)
	var skills = pair.skills
	skills.unlock(&"dash")
	skills.equip(0, &"dash")
	var fired: Array = []
	skills.skill_activated.connect(func(slot: int, skill_id: StringName) -> void: fired.append([slot, String(skill_id)]))
	if not skills.try_activate(0) or fired != [[0, "dash"]]:
		_fail("equipped dash did not activate")
		_drop(pair)
		return
	if skills.cooldown_left(0) != _Skills.DEFAULT_COOLDOWN:
		_fail("cooldown did not start at the catalog length")
		_drop(pair)
		return
	if skills.try_activate(0):
		_fail("a cooling skill activated again")
		_drop(pair)
		return
	skills._process(0.4)
	if absf(skills.cooldown_left(0) - 0.6) > 0.001:
		_fail("cooldown did not tick, left %s" % str(skills.cooldown_left(0)))
		_drop(pair)
		return
	_GameplayInput.pause_open = true
	skills._process(1.0)
	_GameplayInput.pause_open = false
	if absf(skills.cooldown_left(0) - 0.6) > 0.001:
		_fail("pause moved the cooldown")
		_drop(pair)
		return
	skills._process(0.6)
	if skills.cooldown_left(0) > 0.001 or not skills.try_activate(0):
		_fail("cooldown did not finish")
		_drop(pair)
		return
	if skills.try_activate(1):
		_fail("an empty slot activated")
		_drop(pair)
		return
	_drop(pair)
	print("OK cooldowns")


func _check_hotkeys() -> void:
	var pair = _pair(3)
	var skills = pair.skills
	skills.unlock(&"dash")
	skills.unlock(&"ground_slam")
	skills.unlock(&"quick_wall")
	skills.equip(0, &"dash")
	skills.equip(1, &"ground_slam")
	skills.equip(2, &"quick_wall")
	var fired: Array = []
	skills.skill_activated.connect(func(slot: int, skill_id: StringName) -> void: fired.append([slot, String(skill_id)]))
	if not InputMap.has_action("skill_1") or not InputMap.has_action("skill_2") or not InputMap.has_action("skill_3"):
		_fail("InputMap is missing a skill hotkey")
		_drop(pair)
		return
	Input.action_press("skill_2")
	skills._process(0.0)
	Input.action_release("skill_2")
	skills._process(0.0)
	if fired != [[1, "ground_slam"]]:
		_fail("skill_2 did not fire slot 1, got %s" % str(fired))
		_drop(pair)
		return
	Input.action_press("skill_2")
	skills._process(0.0)
	Input.action_release("skill_2")
	if fired.size() != 1:
		_fail("skill_2 fired through the cooldown")
		_drop(pair)
		return
	_GameplayInput.map_open = true
	Input.action_press("skill_1")
	skills._process(5.0)
	Input.action_release("skill_1")
	_GameplayInput.map_open = false
	if fired.size() != 1 or skills.cooldown_left(1) <= 0.0:
		_fail("the map let a hotkey through or ticked a cooldown")
		_drop(pair)
		return
	_drop(pair)
	print("OK hotkeys")


func _check_save_round_trip() -> void:
	var pair = _pair(2)
	var skills = pair.skills
	skills.unlock(&"quick_wall")
	skills.unlock(&"builder_passive")
	skills.equip(2, &"quick_wall")
	skills.try_activate(2)
	var blob: Dictionary = skills.export_state()
	var other = _pair(9)
	other.skills.import_state(blob)
	if not other.skills.is_unlocked(&"quick_wall") or not other.skills.is_unlocked(&"builder_passive"):
		_fail("import dropped an unlock")
		_drop(pair)
		_drop(other)
		return
	if other.skills.slot_skill(2) != &"quick_wall" or other.skills.slot_skill(0) != &"":
		_fail("import moved the equipped slot")
		_drop(pair)
		_drop(other)
		return
	if absf(other.skills.cooldown_left(2) - _Skills.DEFAULT_COOLDOWN) > 0.001:
		_fail("import dropped the cooldown")
		_drop(pair)
		_drop(other)
		return
	if other.prog.skill_points != 9:
		_fail("skill import rewrote progression points")
		_drop(pair)
		_drop(other)
		return
	var before: Dictionary = other.skills.export_state()
	other.skills.import_state({})
	if other.skills.export_state() != before:
		_fail("an empty skills block wiped the run")
		_drop(pair)
		_drop(other)
		return
	_drop(other)
	_drop(pair)
	print("OK skills save round trip")
