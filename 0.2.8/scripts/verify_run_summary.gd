extends SceneTree


const _GameManager = preload("res://game/game_manager.gd")
const _RunSummary = preload("res://ui/run_summary_panel.gd")

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _run() -> void:
	await process_frame
	var won := _GameManager.new()
	root.add_child(won)
	await process_frame
	while Time.get_ticks_msec() < 3000:
		await process_frame
	won.run_started_msec = Time.get_ticks_msec() - 2500
	won.note_spawn_destroyed()
	won.note_crystal_broken(3)
	won.note_enemy_killed()
	won.note_relic_taken()
	won.notify_boss_defeated()
	var win_data: Dictionary = won.run_summary()
	if str(win_data.get("outcome", "")) != "win":
		_fail("win outcome is %s" % str(win_data.get("outcome", "")))
	if not bool(win_data.get("boss_defeated", false)):
		_fail("boss_defeated is false after notify_boss_defeated")
	if int(win_data.get("spawns_destroyed", 0)) != 1:
		_fail("spawns_destroyed is %d" % int(win_data.get("spawns_destroyed", 0)))
	if int(win_data.get("crystal_broken", 0)) != 3:
		_fail("crystal_broken is %d" % int(win_data.get("crystal_broken", 0)))
	if int(win_data.get("enemies_killed", 0)) != 1:
		_fail("enemies_killed is %d" % int(win_data.get("enemies_killed", 0)))
	if int(win_data.get("relics_taken", 0)) != 1:
		_fail("relics_taken is %d" % int(win_data.get("relics_taken", 0)))
	if int(win_data.get("deaths", 0)) != 0:
		_fail("win deaths is %d" % int(win_data.get("deaths", 0)))
	if float(win_data.get("time_sec", 0.0)) < 2.0:
		_fail("win time_sec is %.3f" % float(win_data.get("time_sec", 0.0)))
	won.queue_free()
	await process_frame

	var lost := _GameManager.new()
	root.add_child(lost)
	await process_frame
	lost.note_enemy_killed()
	lost._on_player_died()
	var loss_data: Dictionary = lost.run_summary()
	if str(loss_data.get("outcome", "")) != "loss":
		_fail("loss outcome is %s" % str(loss_data.get("outcome", "")))
	if int(loss_data.get("deaths", 0)) < 1:
		_fail("loss deaths is %d" % int(loss_data.get("deaths", 0)))
	if str(loss_data.get("loss_reason", "")) != "You died.":
		_fail("loss reason is %s" % str(loss_data.get("loss_reason", "")))
	if int(loss_data.get("enemies_killed", 0)) != 1:
		_fail("loss enemies_killed is %d" % int(loss_data.get("enemies_killed", 0)))

	var panel := _RunSummary.new()
	root.add_child(panel)
	await process_frame
	panel.show_summary(win_data)
	_check_panel(panel, "Win")
	panel.show_summary(loss_data)
	_check_panel(panel, "Loss")
	var formatted := _RunSummary.format_summary(win_data)
	if not formatted.contains("Win") or not formatted.contains("Boss defeated: yes"):
		_fail("format_summary missed the win lines")
	lost.queue_free()
	panel.queue_free()
	if _failed:
		quit(1)
	else:
		print("All run summary checks OK")
		quit(0)


func _check_panel(panel: Node, title: String) -> void:
	var body := panel.get_node_or_null("SummaryBody") as Label
	if body == null:
		_fail("summary body missing")
		return
	var text := body.text
	for needle in [title, "Time:", "Spawns destroyed:", "Boss defeated:", "Crystal broken:", "Enemies killed:", "Relics taken:", "Deaths:"]:
		if not text.contains(needle):
			_fail("summary text missing %s" % needle)
	var world_btn := panel.find_child("WorldSelectButton", true, false) as Button
	if world_btn == null:
		_fail("World Select button missing")
	elif world_btn.text != "World Select":
		_fail("World Select button label changed")
	var new_btn := panel.find_child("NewRunButton", true, false) as Button
	if new_btn == null:
		_fail("New Run button missing")
	elif new_btn.text != "New Run":
		_fail("New Run button label changed")
