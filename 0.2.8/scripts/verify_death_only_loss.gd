extends SceneTree

const _GameManager = preload("res://game/game_manager.gd")
const _CrystalManager = preload("res://crystal/crystal_manager.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL " + msg)


func _run() -> void:
	if not _GameManager.DEATH_ONLY_LOSS:
		_fail("DEATH_ONLY_LOSS must default true")
	_test_coverage_does_not_lose()
	_test_town_does_not_lose()
	_test_crystal_touch_does_not_lose()
	_test_death_loses()
	if _failed == 0:
		print("All death only loss tests OK")
		quit(0)
	else:
		push_error("verify_death_only_loss: %d failure(s)" % _failed)
		quit(1)


func _test_coverage_does_not_lose() -> void:
	var gm := _GameManager.new()
	root.add_child(gm)
	gm.max_crystal_coverage = 0.01
	var crystal := _CrystalManager.new()
	crystal.covered_cells = 100000
	gm._crystal = crystal
	gm._check_crystal_overrun()
	gm._check_crystal_overrun()
	if gm.run_state != _GameManager.RunState.PLAYING:
		_fail("coverage over max must stay PLAYING, state=%s reason=%s" % [gm.run_state, gm.last_loss_reason])
	elif gm.coverage_warning == "":
		_fail("coverage over max must set a warning")
	elif gm.coverage_hud_note(1.0) != "over cap":
		_fail("coverage HUD note missing, got %s" % gm.coverage_hud_note(1.0))
	elif gm.coverage_hud_note(0.0) != "":
		_fail("coverage under the cap must not warn")
	else:
		print("OK coverage over max stays playing: %s" % gm.coverage_warning)
	crystal.free()
	gm.free()


func _test_town_does_not_lose() -> void:
	var gm := _GameManager.new()
	root.add_child(gm)
	var crystal := _CrystalManager.new()
	crystal.power = 5.0
	gm._crystal = crystal
	gm._on_town_fallen("Harbor", Vector2i(12, -4))
	if gm.run_state != _GameManager.RunState.PLAYING:
		_fail("town fallen must stay PLAYING, state=%s reason=%s" % [gm.run_state, gm.last_loss_reason])
	elif gm.fallen_towns != 1 or crystal.power < 40.0:
		_fail("town penalty missing surge or count power=%.1f towns=%d" % [crystal.power, gm.fallen_towns])
	elif gm.last_town_penalty == "":
		_fail("town fallen must record a penalty line")
	else:
		print("OK town fallen stays playing: %s" % gm.last_town_penalty)
	crystal.free()
	gm.free()


func _test_crystal_touch_does_not_lose() -> void:
	var gm := _GameManager.new()
	root.add_child(gm)
	gm._on_crystal_touched_player()
	gm._on_crystal_touched_player()
	if gm.run_state != _GameManager.RunState.PLAYING:
		_fail("crystal touch must stay PLAYING, state=%s reason=%s" % [gm.run_state, gm.last_loss_reason])
	elif gm.crystal_touch_note == "":
		_fail("crystal touch must set a warning")
	elif gm.deaths != 0:
		_fail("crystal touch must not count a death")
	else:
		print("OK crystal touch stays playing: %s" % gm.crystal_touch_note)
	gm.free()


func _test_death_loses() -> void:
	var gm := _GameManager.new()
	gm._on_player_died()
	if gm.run_state != _GameManager.RunState.LOST or gm.last_loss_reason == "":
		_fail("death must set LOST with a reason, state=%s reason=%s" % [gm.run_state, gm.last_loss_reason])
	elif gm.deaths != 1:
		_fail("death must count, deaths=%d" % gm.deaths)
	else:
		print("OK death loses: %s" % gm.last_loss_reason)
	gm.free()
