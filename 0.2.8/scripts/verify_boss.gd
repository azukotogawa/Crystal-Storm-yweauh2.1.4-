extends SceneTree


const _BossBrain = preload("res://entities/boss_brain.gd")
const _RelicChoice = preload("res://relics/relic_choice.gd")
const _RelicChoicePanel = preload("res://ui/relic_choice_panel.gd")
const _GameManager = preload("res://game/game_manager.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")


class _RelicBag extends RefCounted:
	var got: Array[StringName] = []

	func equip(relic_id: StringName) -> bool:
		got.append(relic_id)
		return true


class _FullBag extends RefCounted:
	var equipped: Array[StringName] = []
	var max_slots: int = 3

	func equip(relic_id: StringName) -> bool:
		if relic_id in equipped:
			return true
		if equipped.size() >= max_slots:
			return false
		equipped.append(relic_id)
		return true

	func unequip(relic_id: StringName) -> void:
		equipped.erase(relic_id)


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
	if not _queued_relic_scale():
		failed = true
	if not _full_slots_replace():
		failed = true
	Engine.time_scale = 1.0
	_GameplayInput.pause_open = false
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
			if elapsed + 0.001 < brain.telegraph_sec:
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
	if gm.run_state != _GameManager.RunState.PLAYING or gm.phase == _GameManager.Phase.VICTORY:
		push_error("warden death must not win while one crystal is the goal")
		return false
	if str(gm.victory_reason) == "boss":
		push_error("warden death must not set a boss victory")
		return false
	if not gm.boss_defeated:
		push_error("warden death must record boss_defeated")
		return false
	var loss := _GameManager.new()
	loss.run_state = _GameManager.RunState.LOST
	loss.notify_boss_defeated()
	if loss.run_state != _GameManager.RunState.LOST:
		push_error("a loss must stay a loss when the warden dies")
		return false
	print("OK boss death is a stat and does not override a loss")
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


func _queued_relic_scale() -> bool:
	Engine.time_scale = 0.8
	_GameplayInput.pause_open = false
	var overlay := Control.new()
	overlay.name = "RelicProbeOverlay"
	overlay.add_to_group("game_overlay")
	root.add_child(overlay)
	var bag := _RelicBag.new()
	_RelicChoice.present(self, bag, 0, "Heart destroyed — choose a relic")
	_RelicChoice.present(self, bag, 1, "Origin Warden fell — choose a relic")
	if not is_equal_approx(Engine.time_scale, 0.05):
		push_error("first relic panel should slow time, got %s" % Engine.time_scale)
		overlay.free()
		return false
	var first := _live_panel(overlay)
	if first == null or not _press_role(first, "offer", "mason_glove"):
		push_error("could not choose the first queued relic")
		overlay.free()
		return false
	if not is_equal_approx(Engine.time_scale, 0.05):
		push_error("queued relic panel dropped slow-mo, got %s" % Engine.time_scale)
		overlay.free()
		return false
	var second := _live_panel(overlay)
	if second == null or second == first or not _press_role(second, "offer", "flow_anchor"):
		push_error("queued relic panel did not open")
		overlay.free()
		return false
	if not is_equal_approx(Engine.time_scale, 0.8):
		push_error("last relic panel restored %s, want the pre-modal 0.8" % Engine.time_scale)
		overlay.free()
		return false
	if _GameplayInput.pause_open:
		push_error("pause_open stayed set after the last relic panel")
		overlay.free()
		return false
	overlay.free()
	print("OK queued relic panels restore the pre-modal time scale")
	return true


func _full_slots_replace() -> bool:
	Engine.time_scale = 1.0
	_GameplayInput.pause_open = false
	var overlay := Control.new()
	overlay.name = "RelicFullOverlay"
	overlay.add_to_group("game_overlay")
	root.add_child(overlay)
	var bag := _FullBag.new()
	bag.equipped = [&"mason_glove", &"flow_anchor", &"crystal_ward"]
	_RelicChoicePanel.open(self, bag, [&"pathfinder_charm", &"ruin_seal", &"mason_glove"], "Slots full")
	var panel := _live_panel(overlay)
	if panel == null or not _press_role(panel, "offer", "pathfinder_charm"):
		push_error("could not pick a relic while slots are full")
		overlay.free()
		return false
	if _live_panel(overlay) == null:
		push_error("full relic slots closed the offer")
		overlay.free()
		return false
	if not is_equal_approx(Engine.time_scale, 0.05):
		push_error("replace choice should keep the run slowed")
		overlay.free()
		return false
	if bag.equipped.size() != 3 or &"pathfinder_charm" in bag.equipped:
		push_error("full slots equipped a relic before a replace choice")
		overlay.free()
		return false
	var hint := ""
	for node in _walk(panel):
		if node is Label and "slots are full" in (node as Label).text.to_lower():
			hint = (node as Label).text
			break
	if hint == "":
		push_error("full slots did not say the slots are full")
		overlay.free()
		return false
	if not _press_role(panel, "replace", "mason_glove"):
		push_error("could not replace an equipped relic")
		overlay.free()
		return false
	if &"pathfinder_charm" not in bag.equipped or &"mason_glove" in bag.equipped:
		push_error("replace did not swap relics, got %s" % [bag.equipped])
		overlay.free()
		return false
	if not is_equal_approx(Engine.time_scale, 1.0):
		push_error("replace left time_scale at %s" % Engine.time_scale)
		overlay.free()
		return false
	overlay.free()
	print("OK full relic slots replace one and then restore time")
	return true


func _live_panel(host: Node) -> RelicChoicePanel:
	for child in host.get_children():
		if child is RelicChoicePanel and not (child as Node).is_queued_for_deletion():
			return child as RelicChoicePanel
	return null


func _press_role(panel: Node, role: String, relic_id: String) -> bool:
	for node in _walk(panel):
		if node is Button and str(node.get_meta("relic_role", "")) == role and str(node.get_meta("relic_id", "")) == relic_id:
			(node as Button).pressed.emit()
			return true
	return false


func _walk(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out
