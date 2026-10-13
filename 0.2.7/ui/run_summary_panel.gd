class_name RunSummaryPanel
extends VBoxContainer
## End-of-run stats. The dictionary comes from GameManager.run_summary().

const _ThemeBuilder = preload("res://ui/theme/theme_builder.gd")

var _body: Label
var _summary: Dictionary = {}


func _ready() -> void:
	_ThemeBuilder.apply(self)
	add_theme_constant_override("separation", 6)
	_body = Label.new()
	_body.name = "SummaryBody"
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	var world_btn := Button.new()
	world_btn.name = "WorldSelectButton"
	world_btn.text = "World Select"
	world_btn.pressed.connect(_on_world_select)
	row.add_child(world_btn)
	var new_btn := Button.new()
	new_btn.name = "NewRunButton"
	new_btn.text = "New Run"
	new_btn.pressed.connect(_on_new_run)
	row.add_child(new_btn)


func show_summary(summary: Dictionary) -> void:
	_summary = summary
	visible = true
	if _body == null:
		return
	_body.text = format_summary(summary)


func summary_text() -> String:
	if _body == null:
		return ""
	return _body.text


static func format_summary(summary: Dictionary) -> String:
	var outcome := str(summary.get("outcome", "playing"))
	var title := "Run in progress"
	if outcome == "win":
		title = "Win"
	elif outcome == "loss":
		title = "Loss"
	var boss := "yes" if bool(summary.get("boss_defeated", false)) else "no"
	return "%s\nTime: %.1fs\nSpawns destroyed: %d\nBoss defeated: %s\nCrystal broken: %d\nEnemies killed: %d\nRelics taken: %d\nDeaths: %d" % [
		title,
		float(summary.get("time_sec", 0.0)),
		int(summary.get("spawns_destroyed", 0)),
		boss,
		int(summary.get("crystal_broken", 0)),
		int(summary.get("enemies_killed", 0)),
		int(summary.get("relics_taken", 0)),
		int(summary.get("deaths", 0)),
	]


func _on_world_select() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var game = tree.get_first_node_in_group("game")
	if game and game.has_method("return_to_world_select"):
		game.return_to_world_select()
		return
	tree.change_scene_to_file("res://scenes/frontend.tscn")


func _on_new_run() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var gm = tree.get_first_node_in_group("game_manager")
	if gm and gm.has_method("restart_run"):
		gm.restart_run()
		return
	tree.reload_current_scene()
