extends SceneTree

const _Look = preload("res://config/main_crystal_look.gd")
const _Mesh = preload("res://helpers/main_crystal_mesh.gd")
const _CrystalManager = preload("res://crystal/crystal_manager.gd")
const _Spawn = preload("res://crystal/crystal_spawn_point.gd")
const _Types = preload("res://helpers/crystal_types.gd")
const _Def = preload("res://config/spawn_point_def.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _Coords = preload("res://helpers/world_visual_coords.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var look := _Look.load_active()
	if look == null or look.shard_count() < 6:
		push_error("main crystal look needs at least 6 shards")
		quit(1)
		return
	if look.emission_energy < 1.0 or look.colorblind_emission_energy < 1.0:
		push_error("main crystal emission is not a glow")
		failed = true
	else:
		print("OK main crystal emission %.2f" % look.emission_energy)
	if absf(_Def.RELEASED_CRYSTAL_HEALTH - 500.0) > 0.001:
		push_error("released crystal health changed")
		failed = true
	else:
		print("OK released crystal health %.0f" % _Def.RELEASED_CRYSTAL_HEALTH)

	var holder := Node3D.new()
	root.add_child(holder)
	var heart := _Mesh.attach(holder, 1.6, false)
	if not _shape_ok(heart, 1.6):
		failed = true
	var mat := heart.get_child(0).material_override as StandardMaterial3D
	if mat == null or not mat.emission_enabled or mat.emission_energy_multiplier < 1.0:
		push_error("main crystal shard is not emissive")
		failed = true
	else:
		print("OK main crystal emissive energy %.2f" % mat.emission_energy_multiplier)
	_Mesh.repaint(heart, true)
	if mat.emission != look.colorblind_emission:
		push_error("colorblind repaint missed the heart")
		failed = true
	else:
		print("OK colorblind heart emission")
	if heart.find_child("CollisionShape3D", true, false) != null:
		push_error("main crystal mesh added a hit shape")
		failed = true

	var crystal := _CrystalManager.new()
	crystal.name = "CrystalManager"
	crystal.cancel_bootstrap()
	crystal.set_process(false)
	root.add_child(crystal)
	await process_frame
	var origin := _Spawn.new(1, Vector2i(4, 6), _Types.SpawnKind.ORIGIN, 500.0, false)
	origin.def_id = &"released_crystal"
	var ruin := _Spawn.new(2, Vector2i(8, 6), _Types.SpawnKind.RUIN, 120.0, false)
	crystal._spawn_points.append(origin)
	crystal._spawn_points.append(ruin)
	crystal._refresh_spawn_markers()
	var origin_anchor: Node3D = crystal._spawn_markers.get(1)
	var ruin_anchor: Node3D = crystal._spawn_markers.get(2)
	if origin_anchor == null or origin_anchor.get_node_or_null("HeartCrystal") == null:
		push_error("origin crystal has no voxel heart")
		failed = true
	elif origin_anchor.get_node_or_null("FallbackPrism") != null:
		push_error("origin crystal still draws the pink cube")
		failed = true
	else:
		var sprite := origin_anchor.get_node_or_null("Sprite") as Sprite3D
		if sprite == null or sprite.visible:
			push_error("origin sprite should stay in the tree and stay hidden")
			failed = true
		else:
			print("OK origin heart replaces the cube")
	if ruin_anchor == null or ruin_anchor.get_node_or_null("HeartCrystal") != null:
		push_error("ruin spawn picked up the main crystal mesh")
		failed = true
	else:
		var ruin_sprite := ruin_anchor.get_node_or_null("Sprite") as Sprite3D
		if ruin_sprite == null or not ruin_sprite.visible:
			push_error("ruin spawn sprite hidden")
			failed = true
		else:
			print("OK ruin spawn keeps its sprite")
	var vs: float = _WorldSettings.get_active().voxel_scale
	var marker_size := vs * 0.8
	var fill := origin_anchor.get_node_or_null("HpFill") as MeshInstance3D if origin_anchor else null
	if fill == null or absf(fill.position.y - marker_size * 1.25) > 0.001:
		push_error("crystal hp bar moved")
		failed = true
	else:
		print("OK crystal hp bar height")
	var expected := _Coords.column_to_world_pos(4.5, marker_size * 0.5 + 0.12, 6.5)
	if origin_anchor == null or origin_anchor.position.distance_to(expected) > 0.001:
		push_error("crystal anchor moved")
		failed = true
	else:
		print("OK crystal anchor")
	if absf(origin.health - 500.0) > 0.001 or absf(origin.max_health - 500.0) > 0.001:
		push_error("crystal health changed while building the mesh")
		failed = true
	crystal.free()
	if failed:
		quit(1)
		return
	print("All main crystal model tests OK")
	quit(0)


func _shape_ok(heart: Node3D, marker_size: float) -> bool:
	if heart.get_child_count() < 6:
		push_error("heart shard count %d" % heart.get_child_count())
		return false
	var min_p := Vector3(INF, INF, INF)
	var max_p := Vector3(-INF, -INF, -INF)
	var size_span := 0.0
	var first_size := Vector3.ZERO
	for child in heart.get_children():
		var shard := child as MeshInstance3D
		if shard == null or not (shard.mesh is BoxMesh):
			push_error("heart child is not a voxel box")
			return false
		var box := shard.mesh as BoxMesh
		if first_size == Vector3.ZERO:
			first_size = box.size
		size_span = maxf(size_span, box.size.distance_to(first_size))
		var half := box.size * 0.5
		min_p = min_p.min(shard.position - half)
		max_p = max_p.max(shard.position + half)
	if size_span < marker_size * 0.15:
		push_error("heart shards are the same cube")
		return false
	if absf(min_p.x + max_p.x) < marker_size * 0.08 or absf(min_p.z + max_p.z) < marker_size * 0.08:
		push_error("heart is symmetric min=%s max=%s" % [min_p, max_p])
		return false
	print("OK jagged heart span %s .. %s" % [min_p, max_p])
	return true
