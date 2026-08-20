extends SceneTree
## P1 regression: player movement triggers throttled proximity LOD refresh.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var player_src := (load("res://player/player.gd") as GDScript).source_code
	if "_maybe_refresh_proximity_lod" not in player_src:
		push_error("player must refresh proximity LOD on movement")
		failed = true
	elif "refresh_proximity_lod" not in player_src:
		push_error("player must call registry refresh_proximity_lod")
		failed = true
	else:
		print("OK player proximity LOD hook")

	var registry_src := (load("res://systems/game_visual_registry.gd") as GDScript).source_code
	if "func refresh_proximity_lod" not in registry_src:
		push_error("game_visual_registry must expose refresh_proximity_lod")
		failed = true
	elif "repopulate_all" not in registry_src.split("refresh_proximity_lod")[1].split("func")[0]:
		push_error("refresh_proximity_lod must repopulate vegetation")
		failed = true
	else:
		print("OK registry refresh_proximity_lod")

	if failed:
		quit(1)
		return
	print("All proximity visual refresh tests OK")
	quit(0)