extends SceneTree
## Regression: scenario presets apply on production main.tscn (teleport + kit grants).


const MAIN_SCENE := "res://scenes/main.tscn"
const _ScenarioPresets = preload("res://helpers/scenario_presets.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		push_error("main scene load failed")
		_ProbeExit.finish_tree(self, 1, "Scenario presets FAILED")
		return

	var game: Node = main_packed.instantiate()
	root.add_child(game)

	var player: Node = null
	for _attempt in 600:
		player = get_first_node_in_group("player")
		if player != null and bool(player.get("world_ready")):
			break
		await process_frame

	if player == null:
		push_error("player bootstrap timeout")
		_ProbeExit.finish_tree(self, 1, "Scenario presets FAILED")
		return

	for _w in 60:
		await process_frame

	var dig_msg := _ScenarioPresets.apply(self, "dig_flat")
	if "tp(8,8)" not in dig_msg:
		push_error("dig_flat should tp to (8,8): %s" % dig_msg)
		failed = true
	else:
		print("OK dig_flat tp")

	var pos: Vector3 = player.voxel_position
	if absf(pos.x - 8.5) > 0.6 or absf(pos.z - 8.5) > 0.6:
		push_error("dig_flat player pos wrong: %s" % pos)
		failed = true
	else:
		print("OK dig_flat player position")

	var inv = player.get("inventory")
	if inv == null:
		push_error("inventory missing after dig_flat")
		failed = true
	elif inv.count_item("stone_pick") < 1:
		push_error("dig_flat should grant stone_pick")
		failed = true
	else:
		print("OK dig_flat kit")

	var combat_msg := _ScenarioPresets.apply(self, "combat_ring")
	if "tp(11,11)" not in combat_msg:
		push_error("combat_ring tp failed: %s" % combat_msg)
		failed = true
	else:
		print("OK combat_ring tp")

	pos = player.voxel_position
	if absf(pos.x - 11.5) > 0.6 or absf(pos.z - 11.5) > 0.6:
		push_error("combat_ring player pos wrong: %s" % pos)
		failed = true
	else:
		print("OK combat_ring position")

	if inv and inv.count_item("wooden_sword") < 1:
		push_error("combat_ring should grant sword")
		failed = true
	else:
		print("OK combat_ring sword")

	var builder_msg := _ScenarioPresets.apply(self, "builder")
	if "tp(5,5)" not in builder_msg:
		push_error("builder tp failed: %s" % builder_msg)
		failed = true
	elif inv and inv.count_item("stone") < 8:
		push_error("builder should grant stone")
		failed = true
	else:
		print("OK builder kit")

	var smoke_msg := _ScenarioPresets.apply(self, "smoke_origin")
	if "tp(" not in smoke_msg:
		push_error("smoke_origin tp failed: %s" % smoke_msg)
		failed = true
	else:
		print("OK smoke_origin tp")

	var bad := _ScenarioPresets.apply(self, "nonexistent")
	if "Unknown scenario" not in bad:
		push_error("unknown scenario should error")
		failed = true
	else:
		print("OK unknown scenario rejected")

	if _ScenarioPresets.list_ids().size() < 5:
		push_error("expected >=5 scenario ids")
		failed = true
	else:
		print("OK scenario id count=%d" % _ScenarioPresets.list_ids().size())

	if failed:
		_ProbeExit.finish_tree(self, 1, "Scenario presets FAILED")
		return
	_ProbeExit.finish_tree(self, 0, "All scenario preset tests OK")