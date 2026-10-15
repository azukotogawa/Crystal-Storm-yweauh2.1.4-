extends SceneTree

const _Progression = preload("res://systems/progression_service.gd")

var _failed: int = 0


func _init() -> void:
	_run()
	if _failed == 0:
		print("All progression tests OK")
		quit(0)
	else:
		push_error("verify_progression: %d failure(s)" % _failed)
		quit(1)


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)
	print("FAIL " + msg)


func _run() -> void:
	_check_flag_and_curve()
	_check_level_up()
	_check_registered()


func _check_flag_and_curve() -> void:
	if not _Progression.XP_ENABLED:
		_fail("XP_ENABLED must default true")
	if _Progression.xp_to_advance(1) != 50:
		_fail("level 1 threshold %d want 50" % _Progression.xp_to_advance(1))
	if _Progression.xp_to_advance(4) != 400:
		_fail("level 4 threshold %d want 400" % _Progression.xp_to_advance(4))
	if _Progression.xp_to_advance(0) != 50:
		_fail("level 0 must use the level 1 threshold")
	for lv in [2, 3, 10]:
		var expect := int(round(50.0 * pow(float(lv), 1.5)))
		var got := _Progression.xp_to_advance(lv)
		if got != expect:
			_fail("level %d threshold %d want %d" % [lv, got, expect])
	if _failed == 0:
		print("OK curve 50 * level^1.5")


func _check_level_up() -> void:
	var svc = _Progression.new()
	var gained: Array = []
	var ups: Array = []
	svc.xp_gained.connect(func(amount: int, total: int) -> void: gained.append([amount, total]))
	svc.level_up.connect(func(lv: int) -> void: ups.append(lv))
	svc.add_xp(0)
	svc.add_xp(-3)
	if svc.xp != 0 or svc.level != 1 or not gained.is_empty() or not ups.is_empty():
		_fail("non-positive xp must not move the bar")
		return
	svc.add_xp(49)
	if svc.level != 1 or svc.xp != 49 or ups.size() != 0 or gained != [[49, 49]]:
		_fail("49 xp should stay level 1, got level %d xp %d" % [svc.level, svc.xp])
		return
	svc.add_xp(1)
	if svc.level != 2 or svc.xp != 0 or ups != [2]:
		_fail("50 xp should reach level 2, got level %d xp %d ups %s" % [svc.level, svc.xp, str(ups)])
		return
	var fresh = _Progression.new()
	var multi: Array = []
	fresh.level_up.connect(func(lv: int) -> void: multi.append(lv))
	var into_3 := _Progression.xp_to_advance(1) + _Progression.xp_to_advance(2)
	fresh.add_xp(into_3)
	if fresh.level != 3 or fresh.xp != 0 or multi != [2, 3]:
		_fail("stacked grant should reach level 3, got level %d xp %d ups %s" % [fresh.level, fresh.xp, str(multi)])
		return
	var spare := _Progression.xp_to_advance(3) - 1
	fresh.add_xp(spare)
	if fresh.level != 3 or fresh.xp != spare:
		_fail("remainder under the next threshold drifted")
		return
	print("OK level-up")


func _check_registered() -> void:
	var root_src := FileAccess.get_file_as_string("res://systems/composition_root.gd")
	var scene_src := FileAccess.get_file_as_string("res://scenes/main.tscn")
	if not root_src.contains("ID_PROGRESSION") or not root_src.contains("_register_progression"):
		_fail("composition root does not register progression")
	elif not root_src.contains("&\"progression_service\""):
		_fail("progression service id missing")
	elif not scene_src.contains("ProgressionService") or not scene_src.contains("res://systems/progression_service.gd"):
		_fail("main scene is missing ProgressionService")
	else:
		print("OK progression registered")
