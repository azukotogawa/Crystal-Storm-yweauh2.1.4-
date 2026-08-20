extends SceneTree
## P2: absorption unlocks grant relics and game overlay surfaces progression feedback.


const _CrystalManager = preload("res://crystal/crystal_manager.gd")
const _CrystalEvolution = preload("res://crystal/crystal_evolution.gd")
const _RelicManager = preload("res://relics/relic_manager.gd")
const _RelicRegistry = preload("res://relics/relic_registry.gd")
const _StatComponent = preload("res://stats/stat_component.gd")
const _GameOverlayScene = preload("res://ui/game_overlay.tscn")
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
	var unlock: Dictionary = {}
	for _i in 9:
		unlock = evo.record_absorption(&"grass")
	if not unlock.is_empty():
		push_error("grass unlock should trigger on 10th absorption, not earlier")
		failed = true
	unlock = evo.record_absorption(&"grass")
	if str(unlock.get("enemy_id", "")) != "crystal_mite":
		push_error("expected crystal_mite unlock, got %s" % str(unlock))
		failed = true
	else:
		print("OK grass threshold unlock")

	failed = await _test_e2e_unlock_relic_overlay() or failed

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

	var unlock: Dictionary = {}
	for _i in 10:
		unlock = cm.evolution.record_absorption(&"grass")
	if str(unlock.get("enemy_id", "")) != "crystal_mite":
		push_error("e2e unlock expected crystal_mite, got %s" % str(unlock))
		failed = true

	if &"crystal_mite" not in overlay._unlocked_enemies:
		push_error("overlay did not record enemy unlock from evolution signal")
		failed = true
	else:
		print("OK overlay enemy unlock signal")

	var granted: StringName = cm.call("_grant_relic_for_unlock", StringName(unlock.get("enemy_id", "")))
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
	if toast == null or not toast.visible or toast.text == "":
		push_error("overlay relic toast not visible after equip")
		failed = true
	else:
		print("OK overlay relic toast: %s" % toast.text)

	return failed