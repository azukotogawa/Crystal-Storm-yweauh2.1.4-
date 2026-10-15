extends SceneTree


const _CrystalManager = preload("res://crystal/crystal_manager.gd")
const _CrystalEvolution = preload("res://crystal/crystal_evolution.gd")
const _RelicManager = preload("res://relics/relic_manager.gd")
const _RelicRegistry = preload("res://relics/relic_registry.gd")
const _StatComponent = preload("res://stats/stat_component.gd")
const _GameOverlayScene = preload("res://ui/game_overlay.tscn")
const _RelicChoicePanel = preload("res://ui/relic_choice_panel.gd")
const _GameManager = preload("res://game/game_manager.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false

	for path in [
		"res://crystal/crystal_manager.gd",
		"res://ui/game_overlay.gd",
		"res://game/game_manager.gd",
	]:
		var scr: GDScript = load(path) as GDScript
		if scr == null or scr.reload() != OK:
			push_error("FAIL compile %s" % path)
			failed = true
		else:
			print("OK compile ", path)

	if _CrystalManager.relic_for_enemy_unlock(&"crystal_mite") != &"mason_glove":
		push_error("grass unlock should map to mason_glove")
		failed = true
	elif _CrystalManager.relic_for_enemy_unlock(&"thornling") != &"flow_anchor":
		push_error("bush unlock should map to flow_anchor")
		failed = true
	else:
		print("OK unlock→relic map")

	var evo := _CrystalEvolution.new()
	evo.configure([])
	if not evo.is_unlocked(&"crystal_mite"):
		push_error("crystal_mite should be unlocked at run start")
		failed = true
	else:
		print("OK crystal_mite unlocked at start")
	var unlock: Dictionary = {}
	for _i in 10:
		unlock = evo.record_absorption(&"grass")
	if not unlock.is_empty():
		push_error("grass absorption should not unlock crystal_mite again, got %s" % str(unlock))
		failed = true
	else:
		print("OK grass absorption does not re-unlock crystal_mite")
	for _i in 5:
		unlock = evo.record_absorption(&"bush")
	if not unlock.is_empty():
		push_error("bush unlock should trigger on the 6th absorption, not earlier")
		failed = true
	unlock = evo.record_absorption(&"bush")
	if str(unlock.get("enemy_id", "")) != "thornling":
		push_error("expected thornling unlock, got %s" % str(unlock))
		failed = true
	else:
		print("OK bush threshold unlock")

	failed = await _test_e2e_unlock_relic_overlay() or failed
	failed = await _test_unlock_signal_grants_relic() or failed
	failed = await _test_full_slots_headless() or failed
	failed = await _test_full_slots_replace_panel() or failed

	var gm: _GameManager = _GameManager.new()
	if not ("last_loss_reason" in gm):
		push_error("game manager missing last_loss_reason")
		failed = true
	else:
		print("OK loss reason field")

	if failed:
		print("P2 progression feedback tests FAILED")
		quit(1)
		return
	print("All P2 progression feedback tests OK")
	quit(0)


func _test_e2e_unlock_relic_overlay() -> bool:
	var failed := false

	var body := CharacterBody3D.new()
	body.add_to_group("player")
	var stats := _StatComponent.new()
	stats.name = "StatComponent"
	body.add_child(stats)
	var relic_mgr := _RelicManager.new()
	relic_mgr.name = "RelicManager"
	body.add_child(relic_mgr)

	var cm := _CrystalManager.new()
	cm.add_to_group("crystal_manager")
	cm.evolution = _CrystalEvolution.new()
	cm.evolution.configure([])

	root.add_child(cm)
	root.add_child(body)

	var overlay: Control = _GameOverlayScene.instantiate() as Control
	root.add_child(overlay)

	for _i in 60:
		await process_frame
		if overlay._progression_bound:
			break

	if not overlay._progression_bound:
		push_error("overlay progression signals never bound (evolution/relic_manager)")
		failed = true
		return failed

	for _i in 10:
		cm.evolution.record_absorption(&"grass")

	if &"crystal_mite" not in overlay._unlocked_enemies:
		push_error("overlay did not list the start-unlocked crystal_mite")
		failed = true
	else:
		print("OK overlay lists start-unlocked crystal_mite")

	var granted: StringName = cm.call("_grant_relic_for_unlock", &"crystal_mite")
	if granted != &"mason_glove":
		push_error("e2e grant expected mason_glove, got %s" % str(granted))
		failed = true
	elif &"mason_glove" not in relic_mgr.equipped:
		push_error("e2e relic not equipped on player RelicManager")
		failed = true
	else:
		print("OK e2e unlock grants mason_glove")

	_RelicRegistry.ensure_builtins()
	var glove_def = _RelicRegistry.get_def(&"mason_glove")
	var glove_name: String = glove_def.display_name if glove_def else "Mason's Glove"
	if glove_name not in overlay._equipped_relic_names:
		push_error("overlay HUD relic list missing %s" % glove_name)
		failed = true
	else:
		print("OK overlay HUD relic line")

	var toast: Label = overlay.get_node_or_null("ToastLabel") as Label
	if toast == null or not toast.visible or "Mason" not in toast.text:
		push_error("overlay relic toast missing mason glove, got %s" % (toast.text if toast else "<none>"))
		failed = true
	else:
		print("OK overlay relic toast: %s" % toast.text)

	await _clear_root()
	return failed


func _clear_root() -> void:
	for child in root.get_children():
		if child.has_method("cancel_bootstrap"):
			child.cancel_bootstrap()
	await process_frame
	for child in root.get_children():
		if is_instance_valid(child):
			child.free()
	Engine.time_scale = 1.0


func _make_player_and_crystal() -> Dictionary:
	await _clear_root()
	var body := CharacterBody3D.new()
	body.add_to_group("player")
	var stats := _StatComponent.new()
	stats.name = "StatComponent"
	body.add_child(stats)
	var relic_mgr := _RelicManager.new()
	relic_mgr.name = "RelicManager"
	body.add_child(relic_mgr)
	var cm := _CrystalManager.new()
	cm.add_to_group("crystal_manager")
	cm.evolution = _CrystalEvolution.new()
	root.add_child(cm)
	root.add_child(body)
	cm.configure_evolution()
	_RelicRegistry.ensure_builtins()
	return {"cm": cm, "relics": relic_mgr, "body": body}


func _test_unlock_signal_grants_relic() -> bool:
	var failed := false
	var nodes := await _make_player_and_crystal()
	var cm: _CrystalManager = nodes.cm
	var relics: _RelicManager = nodes.relics

	cm.evolution.enemy_unlocked.emit(&"crystal_mite")
	if &"mason_glove" in relics.equipped:
		push_error("crystal_mite signal must not equip a relic")
		failed = true
	else:
		print("OK crystal_mite signal skips the relic")

	var unlock: Dictionary = {}
	for _i in 6:
		unlock = cm.evolution.record_absorption(&"bush")
	if str(unlock.get("enemy_id", "")) != "thornling":
		push_error("bush milestone expected thornling, got %s" % str(unlock))
		failed = true
	elif &"flow_anchor" not in relics.equipped:
		push_error("thornling unlock did not equip flow_anchor, equipped=%s" % str(relics.equipped))
		failed = true
	else:
		print("OK thornling milestone grants flow_anchor")

	var before := relics.equipped.size()
	cm.evolution.enemy_unlocked.emit(&"thornling")
	if relics.equipped.size() != before or relics.equipped.count(&"flow_anchor") != 1:
		push_error("second thornling unlock granted again")
		failed = true
	else:
		print("OK unlock relic is once per run")

	for _i in 10:
		cm.evolution.record_absorption(&"grass")
	if &"mason_glove" in relics.equipped:
		push_error("grass absorption equipped mason_glove")
		failed = true
	else:
		print("OK grass absorption does not equip mason_glove")

	var granted: StringName = cm.call("_grant_relic_for_unlock", &"crystal_mite")
	if granted != &"mason_glove" or &"mason_glove" not in relics.equipped:
		push_error("direct crystal_mite grant should still equip mason_glove, got %s" % str(granted))
		failed = true
	else:
		print("OK direct crystal_mite grant still equips")
	return failed


func _test_full_slots_headless() -> bool:
	var failed := false
	var nodes := await _make_player_and_crystal()
	var cm: _CrystalManager = nodes.cm
	var relics: _RelicManager = nodes.relics
	for relic_id in [&"pathfinder_charm", &"ruin_seal", &"crystal_ward"]:
		if not relics.equip(relic_id):
			push_error("setup failed to fill slot %s" % str(relic_id))
			return true
	var before: Array = relics.export_equipped()
	for _i in 6:
		cm.evolution.record_absorption(&"bush")
	if relics.export_equipped() != before or &"flow_anchor" in relics.equipped:
		push_error("full slots without overlay changed relics to %s" % str(relics.equipped))
		failed = true
	else:
		print("OK full slots without overlay do not force-replace")
	return failed


func _test_full_slots_replace_panel() -> bool:
	var failed := false
	var nodes := await _make_player_and_crystal()
	var cm: _CrystalManager = nodes.cm
	var relics: _RelicManager = nodes.relics
	for relic_id in [&"pathfinder_charm", &"ruin_seal", &"crystal_ward"]:
		if not relics.equip(relic_id):
			push_error("replace setup failed to fill slot %s" % str(relic_id))
			return true
	var overlay: Control = _GameOverlayScene.instantiate() as Control
	root.add_child(overlay)
	await process_frame
	var before: Array = relics.export_equipped()
	for _i in 6:
		cm.evolution.record_absorption(&"bush")
	var panel = _RelicChoicePanel._open
	if panel == null or not is_instance_valid(panel):
		push_error("full slots with overlay did not open a relic panel")
		failed = true
	elif not panel._choosing_replace or panel._replace_id != &"flow_anchor":
		push_error("replace panel mode=%s relic=%s" % [str(panel._choosing_replace), str(panel._replace_id)])
		failed = true
	elif relics.export_equipped() != before:
		push_error("replace panel changed relics before a choice %s" % str(relics.equipped))
		failed = true
	else:
		print("OK full slots open replace panel for flow_anchor")
	if panel != null and is_instance_valid(panel):
		panel.free()
	if _RelicChoicePanel._open != null:
		push_error("replace panel stayed open after free")
		failed = true
	if absf(Engine.time_scale - 1.0) > 0.001:
		push_error("time_scale left at %.3f after replace panel" % Engine.time_scale)
		failed = true
	else:
		print("OK replace panel restored time scale")
	await _clear_root()
	return failed