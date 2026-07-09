extends SceneTree
## Regression: cardinal ramp walkable height slopes down toward the low neighbor.


const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _WorldSettings = preload("res://config/world_settings.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var layer: float = _WorldSettings.get_active().layer_height()
	var high_h: float = 10.0
	var low_top: float = high_h
	var landing_top: float = high_h + layer
	var dir := Vector2i(-1, 0)

	var west_h: float = _TerrainRamps.surface_height_on_ramp(6.05, 5.5, high_h, dir)
	var east_h: float = _TerrainRamps.surface_height_on_ramp(6.95, 5.5, high_h, dir)
	if west_h < east_h - 0.05:
		print("OK ramp slopes down toward low neighbor west=%.2f east=%.2f" % [west_h, east_h])
	else:
		push_error("ramp must slope down toward low neighbor west=%.2f east=%.2f" % [west_h, east_h])
		failed = true

	if absf(east_h - landing_top) > layer * 0.15:
		push_error("landing interior walkable expected ~%.2f got %.2f" % [landing_top, east_h])
		failed = true
	else:
		print("OK landing interior walkable=%.2f" % east_h)

	if absf(west_h - low_top) > layer * 0.15:
		push_error("low edge walkable expected ~%.2f got %.2f" % [low_top, west_h])
		failed = true
	else:
		print("OK low edge walkable=%.2f" % west_h)

	if failed:
		print("Ramp slope tests FAILED")
		quit(1)
		return
	print("All ramp slope tests OK")
	quit(0)