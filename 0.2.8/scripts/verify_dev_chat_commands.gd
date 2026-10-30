extends SceneTree

const _DeveloperAssistant = preload("res://systems/developer_assistant.gd")
const _DevChatOverlay = preload("res://ui/dev_chat_overlay.gd")
const _DevCommandGate = preload("res://helpers/dev_command_gate.gd")
const _CrystalManager = preload("res://crystal/crystal_manager.gd")
const _CrystalSpawnPoint = preload("res://crystal/crystal_spawn_point.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _Player = preload("res://player/player.gd")


var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	_failed += 1
	push_error(message)
	print("FAIL %s" % message)


func _check(name: String, ok: bool) -> void:
	if ok:
		print("OK %s" % name)
	else:
		_fail(name)


func _run() -> void:
	OS.set_environment("CRYSTALSTORM_SHOWCASE", "")
	OS.set_environment("CRYSTALSTORM_HARNESS", "")
	OS.set_environment("CRYSTALSTORM_DEV_COMMANDS", "")
	_check("gate release off", not _DevCommandGate.allowed_for("res://main.gd", false, false))
	_check("gate showcase script off", not _DevCommandGate.allowed_for("res://scripts/verify_honest_bot_showcase.gd", true, false))
	_check("gate harness script off", not _DevCommandGate.allowed_for("res://scripts/verify_honest_bot_scenario.gd", true, false))
	_check("gate debug play on", _DevCommandGate.allowed_for("res://main.gd", true, false))
	_check("gate live", _DevCommandGate.allowed())

	var crystal := _CrystalManager.new()
	crystal.set_process(false)
	root.add_child(crystal)
	crystal.cancel_bootstrap()
	await process_frame
	var heart := _CrystalSpawnPoint.new(1, Vector2i(4, -4), _CrystalTypes.SpawnKind.ORIGIN, 200.0, true)
	heart.def_id = &"released_crystal"
	crystal.harness_setup_spawns([heart])

	var player := _Player.new()
	player.set_physics_process(false)
	player.set_process(false)
	root.add_child(player)
	await process_frame
	var before_stone: int = player.inventory.count_item("stone")
	player.health = 80.0
	player.dev_god = false
	player.voxel_position = Vector3(1.5, 4.0, 1.5)

	var assistant := _DeveloperAssistant.new()
	root.add_child(assistant)
	var overlay := _DevChatOverlay.new()
	root.add_child(overlay)
	await process_frame

	var slash := InputEventKey.new()
	slash.physical_keycode = KEY_SLASH
	slash.keycode = KEY_SLASH
	slash.unicode = 47
	slash.pressed = true
	overlay._unhandled_input(slash)
	await process_frame
	_check("slash opens", overlay.is_chat_open() and overlay._line_edit.text == "/")
	overlay.call("_close_chat")
	await process_frame
	_check("slash close", not overlay.is_chat_open())

	var help: String = assistant.send_message("/help")
	_check("help", "/tp" in help and "/give" in help and "/crystal" in help and "/time" in help and "/god" in help)

	var tp: String = assistant.send_message("/tp 20 -8")
	_check("tp", absf(player.voxel_position.x - 20.5) < 0.01 and absf(player.voxel_position.z + 7.5) < 0.01 and "20" in tp)

	var give: String = assistant.send_message("/give stone 5")
	_check("give", player.inventory.count_item("stone") == before_stone + 5 and "Gave 5 stone" in give)

	var set_crystal: String = assistant.send_message("/crystal 40")
	var prog: Dictionary = crystal.get_spawn_progress()
	var hp := float(prog.get("crystal_health", -1.0))
	var mx := float(prog.get("crystal_max_health", 0.0))
	var pct := hp / mx * 100.0 if mx > 0.0 else -1.0
	_check("crystal set", absf(pct - 40.0) < 0.05 and "40.0" in set_crystal)
	var read_crystal: String = assistant.send_message("/crystal")
	_check("crystal read", "40.0" in read_crystal)

	Engine.time_scale = 1.0
	var time_set: String = assistant.send_message("/time 2")
	_check("time set", is_equal_approx(Engine.time_scale, 2.0) and "scale 2.00" in time_set)
	var time_read: String = assistant.send_message("/time")
	_check("time read", is_equal_approx(Engine.time_scale, 2.0) and "scale 2.00" in time_read)
	assistant.send_message("/time 1")
	_check("time reset", is_equal_approx(Engine.time_scale, 1.0))

	var hp_before: float = player.health
	var god_on: String = assistant.send_message("/god toggle")
	player.take_damage(50.0, &"dev_test")
	_check("god toggle on", player.dev_god and is_equal_approx(player.health, hp_before) and "ON" in god_on)
	var god_off: String = assistant.send_message("/god toggle")
	player.take_damage(50.0, &"dev_test")
	_check("god toggle off", not player.dev_god and player.health < hp_before and "OFF" in god_off)

	var stone_locked: int = player.inventory.count_item("stone")
	var god_locked := player.dev_god
	OS.set_environment("CRYSTALSTORM_SHOWCASE", "1")
	var blocked_give: String = assistant.send_message("/give stone 3")
	var blocked_god: String = assistant.send_message("/god toggle")
	overlay._unhandled_input(slash)
	await process_frame
	_check("showcase blocks", blocked_give == "" and blocked_god == "" and player.inventory.count_item("stone") == stone_locked and player.dev_god == god_locked and not overlay.is_chat_open())
	OS.set_environment("CRYSTALSTORM_SHOWCASE", "")

	OS.set_environment("CRYSTALSTORM_HARNESS", "1")
	var harness_give: String = assistant.send_message("/give stone 1")
	_check("harness blocks", harness_give == "" and player.inventory.count_item("stone") == stone_locked)
	OS.set_environment("CRYSTALSTORM_HARNESS", "")

	OS.set_environment("CRYSTALSTORM_DEV_COMMANDS", "0")
	_check("release flag blocks", assistant.send_message("/help") == "" and not _DevCommandGate.allowed())
	OS.set_environment("CRYSTALSTORM_DEV_COMMANDS", "")
	_check("commands return", "/help" in assistant.send_message("/help"))

	if _failed == 0:
		print("DEV CHAT COMMANDS OK")
		quit(0)
	else:
		print("DEV CHAT COMMANDS FAILED %d" % _failed)
		quit(1)
