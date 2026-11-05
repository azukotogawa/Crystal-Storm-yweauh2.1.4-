extends SceneTree
const Quality = preload("res://config/performance_quality_config.gd")
const NearProps = preload("res://world/near_props.gd")
const MeshBuilder = preload("res://helpers/chunk_surface_mesh_builder.gd")

func _init() -> void:
	var bad := 0
	var low = Quality.apply_preset(Quality.Preset.LOW)
	var med = Quality.apply_preset(Quality.Preset.MEDIUM)
	var high = Quality.apply_preset(Quality.Preset.HIGH)
	var safe = Quality.apply_safe_mode()

	if low.scene_shadows or low.near_prop_radius != 0 or low.wave_lod_radius < 1:
		bad += 1
		print("FAIL LOW shadows/props/wave low.shadows=%s rad=%d wave=%d" % [low.scene_shadows, low.near_prop_radius, low.wave_lod_radius])
	else:
		print("OK LOW cheap: shadows off, near_prop_radius=0, wave_lod_radius=%d rebuilds=%d" % [low.wave_lod_radius, low.max_wave_lod_rebuilds_per_frame])

	if not med.scene_shadows or med.shadow_max_distance > 210.0 or med.shadow_max_distance < 200.0:
		bad += 1
		print("FAIL MEDIUM shadow budget dist=%.1f" % med.shadow_max_distance)
	else:
		print("OK MEDIUM shadow_max_distance=%.1f (iGPU-shortened)" % med.shadow_max_distance)
	if med.near_prop_radius != 1 or med.near_prop_max_cubes > 400 or med.max_wave_lod_rebuilds_per_frame != 2:
		bad += 1
		print("FAIL MEDIUM props/wave rad=%d cubes=%d rebuilds=%d" % [med.near_prop_radius, med.near_prop_max_cubes, med.max_wave_lod_rebuilds_per_frame])
	else:
		print("OK MEDIUM near_prop_radius=1 cubes=%d wave_rebuilds=%d" % [med.near_prop_max_cubes, med.max_wave_lod_rebuilds_per_frame])

	if high.near_prop_max_cubes < med.near_prop_max_cubes or high.max_wave_lod_rebuilds_per_frame < med.max_wave_lod_rebuilds_per_frame:
		bad += 1
		print("FAIL HIGH should allow more props/wave than MEDIUM")
	else:
		print("OK HIGH cubes=%d wave_rebuilds=%d" % [high.near_prop_max_cubes, high.max_wave_lod_rebuilds_per_frame])

	if safe.near_prop_radius != 0 or safe.scene_shadows:
		bad += 1
		print("FAIL SAFE not cheap")
	else:
		print("OK SAFE near props off")

	# near_props apply_render_tier disables at radius 0
	var np = NearProps.new()
	root.add_child(np)
	np.apply_render_tier(0, 0)
	if np.radius != 0 or np.max_cubes_per_chunk != 0:
		bad += 1
		print("FAIL near_props apply_render_tier did not zero")
	else:
		print("OK near_props apply_render_tier disables")
	np.apply_render_tier(2, 100)
	if np.radius != 2 or np.max_cubes_per_chunk != 100:
		bad += 1
		print("FAIL near_props apply_render_tier set")
	else:
		print("OK near_props apply_render_tier radius=2 cubes=100")

	# wave lod radius is settable
	var old_r: int = int(MeshBuilder.WAVE_LOD_R)
	MeshBuilder.WAVE_LOD_R = 1
	if int(MeshBuilder.WAVE_LOD_R) != 1:
		bad += 1
		print("FAIL WAVE_LOD_R not settable")
	else:
		print("OK WAVE_LOD_R settable")
	MeshBuilder.WAVE_LOD_R = old_r

	print("RENDER_TIERS summary bad=%d" % bad)
	quit(0 if bad == 0 else 1)