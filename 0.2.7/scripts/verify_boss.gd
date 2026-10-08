extends SceneTree
## Warden phase change, telegraph before damage, boss victory, and a 3-relic offer.


const _BossBrain = preload("res://entities/boss_brain.gd")
const _RelicChoice = preload("res://relics/relic_choice.gd")
const _GameManager = preload("res://game/game_manager.gd")


class _RelicBag extends RefCounted:
	var got: Array[StringName] = []

	func equip(relic_id: StringName) -> bool:
		got.append(relic_id)
		return true


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	if not _phase_and_telegraph():
		failed = true
	if not _victory():
		failed = true
	if not _relics():
		failed = true
	if failed:
		push_error("Boss tests FAILED")
		quit(1)
		return
	print("All boss OK")
	quit(0)


func _phase_and_telegraph() -> bool:
	var brain := _BossBrain.new()
	brain.notify_hp_ratio(0.51)
	if brain.phase != 1:
		push_error("51%% HP must stay in phase 1")
		return false
	var elapsed := 0.0
	var saw_telegraph := false
	var impacted := false
	for _i in 30:
		var step := 0.1
		var row: Dictionary = brain.tick(step, 1.0)
		elapsed += step
		if bool(row.get("telegraph", false)) and not bool(row.get("impact", false)):
			saw_telegraph = true
		if bool(row.get("impact", false)):
			impacted = true
			if not saw_telegraph:
				push_error("slam damaged before its telegraph")
				return false
			if elapsed + 0.001 < _BossBrain.SLAM_WINDUP:
				push_error("slam landed before the windup, elapsed %.2f" % elapsed)
				return false
			break
	if not impacted:
		push_error("close warden never slammed")
		return false

	var phased := _BossBrain.new()
	phased.notify_hp_ratio(0.50)
	if phased.phase != 2:
		push_error("50%% HP must open phase 2")
		return false
	var opened: Dictionary = phased.tick(0.05, 1.0)
	if int(opened.get("summon", 0)) != 3 or not bool(opened.get("telegraph", false)) or bool(opened.get("impact", false)):
		push_error("phase 2 should telegraph a burst and summon 3 mites before damage")
		return false
	print("OK phase switch at 50%% and telegraph before damage")
	return true


func _victory() -> bool:
	var gm := _GameManager.new()
	root.add_child(gm)
	if gm.run_state != _GameManager.RunState.PLAYING:
		push_error("fresh game should be playing")
		return false
	_BossBrain.on_warden_killed(self)
	if gm.run_state != _GameManager.RunState.WON or str(gm.victory_reason) != "boss":
		push_error("warden death should win the run as a boss victory")
		return false
	var loss := _GameManager.new()
	loss.run_state = _GameManager.RunState.LOST
	loss.notify_boss_defeated()
	if loss.run_state != _GameManager.RunState.LOST:
		push_error("a loss must stay a loss when the warden dies")
		return false
	print("OK boss death wins and does not override a loss")
	return true


func _relics() -> bool:
	for seed in [0, 1, 4, 9]:
		var ids := _RelicChoice.roll(seed)
		if ids.size() != 3:
			push_error("relic offer should be 3, got %d" % ids.size())
			return false
		if ids[0] == ids[1] or ids[1] == ids[2] or ids[0] == ids[2]:
			push_error("relic offer reused an id")
			return false
	if _RelicChoice.roll(0)[0] != &"mason_glove":
		push_error("seed 0 should open on mason_glove")
		return false
	var bag := _RelicBag.new()
	var equipped := _RelicChoice.present(null, bag, 0, "Spawn destroyed — choose a relic")
	if equipped != &"mason_glove" or bag.got.size() != 1 or bag.got[0] != &"mason_glove":
		push_error("headless relic choice should equip the first of three")
		return false
	print("OK relic choice offers 3 distinct relics")
	return true
