extends SceneTree
## Passive water levels change a visible fill, not only a signal counter.


const _VoxelFluidService = preload("res://fluids/voxel_fluid_service.gd")
const _WorldSettings = preload("res://config/world_settings.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var svc := _VoxelFluidService.new()
	root.add_child(svc)
	await process_frame
	var listeners: int = svc.channel_fluid_changed.get_connections().size()
	if listeners < 1:
		push_error("channel_fluid_changed has no listener, got %d" % listeners)
		failed = true
	else:
		print("OK channel_fluid_changed listeners=%d" % listeners)

	var layer: float = _WorldSettings.get_active().layer_height()
	var pos := Vector2i(3, 5)
	svc.show_channel_level(pos, 0.25, 4.0)
	var shallow: float = svc._water_visual.cell_height(pos)
	var expect_shallow: float = 0.25 * layer * 0.55
	if absf(shallow - expect_shallow) > 0.05:
		push_error("shallow fill height %.3f expected %.3f" % [shallow, expect_shallow])
		failed = true
	else:
		print("OK shallow water height %.3f" % shallow)

	svc.show_channel_level(pos, 0.9, 4.0)
	var deep: float = svc._water_visual.cell_height(pos)
	if deep <= shallow + layer * 0.15:
		push_error("deeper water did not grow the fill shallow=%.3f deep=%.3f" % [shallow, deep])
		failed = true
	else:
		print("OK deep water height %.3f" % deep)

	svc._water_engine.depth[pos] = 0.45
	svc.channel_fluid_changed.emit(pos)
	var from_signal: float = svc._water_visual.cell_height(pos)
	var expect_signal: float = 0.45 * layer * 0.55
	if absf(from_signal - expect_signal) > 0.05:
		push_error("signal redraw height %.3f expected %.3f" % [from_signal, expect_signal])
		failed = true
	else:
		print("OK signal redraw height %.3f" % from_signal)

	svc._water_engine.depth[pos] = 0.0
	svc.channel_fluid_changed.emit(pos)
	if svc._water_visual.cell_height(pos) > 0.001:
		push_error("empty channel still draws water")
		failed = true
	else:
		print("OK empty channel hides the fill")

	if failed:
		quit(1)
		return
	print("All water redraw tests OK")
	quit(0)
