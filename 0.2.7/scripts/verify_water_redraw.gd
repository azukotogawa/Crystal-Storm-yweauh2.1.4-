extends SceneTree
## Passive water levels change the body the chunk lid reads, and do not spawn a second water mesh.


const _VoxelFluidService = preload("res://fluids/voxel_fluid_service.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _WorldSettings = preload("res://config/world_settings.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	_ChannelRegistry.reset()
	var svc := _VoxelFluidService.new()
	root.add_child(svc)
	await process_frame
	# The per-cell ChannelWaterVisual mesh is gone. Flood body + chunk lids are the only water.
	if ResourceLoader.exists("res://fluids/channel_water_visual.gd"):
		push_error("channel_water_visual.gd is a second water renderer and must stay deleted")
		failed = true
	elif svc.get_node_or_null("ChannelWaterVisual") != null:
		push_error("channel fill must not add a ChannelWaterVisual node")
		failed = true
	else:
		print("OK no ChannelWaterVisual script")

	var layer: float = _WorldSettings.get_active().layer_height()
	var pos := Vector2i(3, 5)
	svc.show_channel_level(pos, 0.25, 4.0)
	var shallow: float = _ChannelRegistry.get_runtime_surface_y(pos.x, pos.y)
	var expect_shallow: float = 4.0 + 0.25 * layer
	if absf(shallow - expect_shallow) > 0.05:
		push_error("shallow waterline %.3f expected %.3f" % [shallow, expect_shallow])
		failed = true
	elif _ChannelRegistry.get_water_level(pos.x, pos.y) < 0.2:
		push_error("shallow fill did not store a water level")
		failed = true
	else:
		print("OK shallow waterline %.3f" % shallow)

	svc.show_channel_level(pos, 0.9, 4.0)
	var deep: float = _ChannelRegistry.get_runtime_surface_y(pos.x, pos.y)
	if deep <= shallow + layer * 0.15:
		push_error("deeper water did not raise the waterline shallow=%.3f deep=%.3f" % [shallow, deep])
		failed = true
	else:
		print("OK deep waterline %.3f" % deep)

	svc.show_channel_level(pos, 0.0, 4.0)
	if _ChannelRegistry.has_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER):
		push_error("empty channel still stores water")
		failed = true
	else:
		print("OK empty channel clears the fill")

	var mesh_count := 0
	for child in svc.get_children():
		if child is MeshInstance3D:
			mesh_count += 1
	if mesh_count > 0 or svc.get_node_or_null("ChannelWaterVisual") != null:
		push_error("show_channel_level spawned %d mesh node(s); water stays on the chunk lid" % mesh_count)
		failed = true
	else:
		print("OK show_channel_level adds no second water mesh")

	if failed:
		quit(1)
		return
	print("All water redraw tests OK")
	quit(0)
