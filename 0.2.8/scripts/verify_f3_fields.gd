extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var crystal := CrystalStub.new()
	var progress := ProgressStub.new()
	var spawner := EnemyStub.new()
	root.add_child(crystal)
	root.add_child(progress)
	root.add_child(spawner)

	var packed := load("res://scenes/f3_overlay.tscn") as PackedScene
	if packed == null:
		push_error("f3 overlay scene missing")
		quit(1)
		return
	var overlay := packed.instantiate()
	root.add_child(overlay)
	await process_frame

	if overlay.is_overlay_visible():
		push_error("overlay should start hidden")
		failed = true
	else:
		print("OK overlay starts hidden")

	overlay.toggle_overlay()
	await process_frame
	if not overlay.is_overlay_visible():
		push_error("toggle should show the overlay")
		failed = true
	else:
		print("OK toggle shows overlay")

	var text: String = str(overlay.overlay_text())
	var label := overlay.get_node_or_null("Readout") as Label
	var shown := ""
	if label:
		shown = label.text
	if shown != text:
		push_error("readout does not match overlay text")
		failed = true
	for line in ["crystal 125/500", "boss spawned", "xp 40 lv 3", "enemies 4"]:
		if line not in text:
			push_error("missing field %s in %s" % [line, text])
			failed = true
		else:
			print("OK ", line)

	overlay.toggle_overlay()
	if overlay.is_overlay_visible():
		push_error("second toggle should hide the overlay")
		failed = true
	else:
		print("OK toggle hides overlay")

	if failed:
		push_error("F3 FIELDS FAILED")
		quit(1)
		return
	print("F3 FIELDS OK")
	quit(0)


class CrystalStub:
	extends Node

	func _enter_tree() -> void:
		add_to_group("crystal_manager")

	func get_spawn_progress() -> Dictionary:
		return {
			"crystal_health": 125.4,
			"crystal_max_health": 500.0,
			"boss_spawned": true,
			"warden_alive": false,
		}


class ProgressStub:
	extends Node

	var xp: int = 40
	var level: int = 3

	func _enter_tree() -> void:
		add_to_group("progression_service")


class EnemyStub:
	extends Node

	func _enter_tree() -> void:
		add_to_group("crystal_enemy_spawner")

	func get_active_count() -> int:
		return 4
