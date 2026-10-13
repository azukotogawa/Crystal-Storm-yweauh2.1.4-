extends SceneTree
## Regression: moving jump uses expanded min/max floor band (not max-feet-only snap).


const _WorldSettings = preload("res://config/world_settings.gd")


func _init() -> void:
	var layer: float = _WorldSettings.get_active().layer_height()
	var base_snap: float = _WorldSettings.get_active().floor_snap_distance()
	var moving_snap: float = base_snap + layer * 0.45

	# Slope edge: feet at center height while probe max is one layer higher.
	var center_h := 10.0
	var min_h := center_h
	var max_h := center_h + layer * 0.55
	var pos_y := center_h

	var strict_max_feet := pos_y <= max_h + base_snap and pos_y >= max_h - base_snap
	if strict_max_feet:
		push_error("strict max-feet snap should fail before moving tolerance")
		quit(1)

	var moving_band := pos_y >= min_h - moving_snap and pos_y <= max_h + moving_snap
	if not moving_band:
		push_error("moving snap band should accept center feet between probe min/max")
		quit(1)

	var player_scr: GDScript = load("res://player/player.gd") as GDScript
	var src := player_scr.source_code
	if "_ground_snap_distance" not in src or "layer_height() * 0.45" not in src:
		push_error("player.gd must use expanded moving ground snap")
		quit(1)

	print("OK moving jump snap band center=%.2f max=%.2f snap=%.2f" % [center_h, max_h, moving_snap])
	quit(0)