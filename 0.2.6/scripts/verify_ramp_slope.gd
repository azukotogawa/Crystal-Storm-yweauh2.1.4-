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
	for case in [
		{"dir": Vector2i(-1, 0), "low": 6.05, "high": 6.95, "axis": "x"},
		{"dir": Vector2i(1, 0), "low": 6.95, "high": 6.05, "axis": "x"},
		{"dir": Vector2i(0, -1), "low": 5.05, "high": 5.95, "axis": "z"},
		{"dir": Vector2i(0, 1), "low": 5.95, "high": 5.05, "axis": "z"},
	]:
		var dir: Vector2i = case.dir
		var low_coord: float = case.low
		var high_coord: float = case.high
		var low_h: float
		var high_h_at: float
		if case.axis == "x":
			low_h = _TerrainRamps.surface_height_on_ramp(low_coord, 5.5, high_h, dir)
			high_h_at = _TerrainRamps.surface_height_on_ramp(high_coord, 5.5, high_h, dir)
		else:
			low_h = _TerrainRamps.surface_height_on_ramp(5.5, low_coord, high_h, dir)
			high_h_at = _TerrainRamps.surface_height_on_ramp(5.5, high_coord, high_h, dir)
		if low_h < high_h_at - 0.05:
			print("OK ramp dir %s slopes down low=%.2f high=%.2f" % [dir, low_h, high_h_at])
		else:
			push_error("ramp dir %s must slope down low=%.2f high=%.2f" % [dir, low_h, high_h_at])
			failed = true
		if absf(high_h_at - landing_top) > layer * 0.15:
			push_error("dir %s landing interior expected ~%.2f got %.2f" % [dir, landing_top, high_h_at])
			failed = true
		if absf(low_h - low_top) > layer * 0.15:
			push_error("dir %s low edge expected ~%.2f got %.2f" % [dir, low_top, low_h])
			failed = true

	if failed:
		print("Ramp slope tests FAILED")
		quit(1)
		return
	print("All ramp slope tests OK")
	quit(0)