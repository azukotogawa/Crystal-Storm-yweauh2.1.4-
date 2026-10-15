extends SceneTree

const _Registry = preload("res://systems/game_visual_registry.gd")
const _WorldEntity = preload("res://entities/world_entity.gd")
const _CrystalEnemy = preload("res://entities/crystal_enemy.gd")
const _Brains = preload("res://entities/entity_brain_registry.gd")
const _Settings = preload("res://config/world_settings.gd")
const _Body = preload("res://player/player_body_mesh.gd")
const _Sun = preload("res://helpers/terrain_lighting.gd")
const _Creature = preload("res://helpers/voxel_creature_builder.gd")

const ANIMALS: Array[String] = ["boar", "deer", "rabbit", "bird", "town_militia", "town_villager"]
const ENEMIES: Array[String] = [
	"crystal_mite", "crystal_stag", "crystal_wisp", "corrupted_beast",
	"farm_bomber", "thornling", "shard_guard", "origin_warden", "spawn_elite",
]
const RIGGED: Array[String] = [
	"player", "boar", "deer", "rabbit", "bird", "town_militia",
	"crystal_mite", "crystal_stag", "crystal_wisp", "corrupted_beast",
	"farm_bomber", "thornling", "shard_guard",
]
const CLEAR := Color(1.0, 0.0, 1.0)

var _scratch: String = ""
var _cam: Camera3D
var _stage: Node3D
var _ground: MeshInstance3D
var _holder: Node
var _player: Node3D
var _failed: int = 0
var _lines: PackedStringArray = PackedStringArray()


class _Player extends Node3D:
	var voxel_position := Vector3.ZERO

	func get_voxel_position() -> Vector3:
		return voxel_position

	func set_damage_origin(_origin: Vector3) -> void:
		pass

	func take_damage(_amount: float, _source: StringName = &"") -> void:
		pass


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("display art voxel needs a window")
		quit(1)
		return
	_scratch = OS.get_environment("CRYSTALSTORM_SCRATCH")
	if _scratch.is_empty():
		_scratch = "D:/ARCHIVE/CrystalStorm/verify-evidence/art-voxel"
	DirAccess.make_dir_recursive_absolute(_scratch)
	DisplayServer.window_set_title("Crystal Storm art voxel")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	_stage_world()
	_Brains.reset()
	_Brains.ensure_builtins()
	await _shoot_player()
	for kind in ANIMALS:
		await _shoot_animal(kind)
	for kind in ENEMIES:
		await _shoot_enemy(kind)
	_write_log()
	if _failed == 0:
		print("ART VOXEL WINDOW OK")
		quit(0)
	else:
		push_error("ART VOXEL WINDOW FAILED %d" % _failed)
		quit(1)


func _stage_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = CLEAR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.46, 0.50)
	env.ambient_light_energy = 0.35
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
	var sun: Vector3 = _Sun.SUN.normalized()
	var light := DirectionalLight3D.new()
	light.shadow_enabled = false
	light.position = sun * 20.0
	root.add_child(light)
	light.look_at(Vector3.ZERO, Vector3.UP)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 16.0
	_cam.current = true
	root.add_child(_cam)
	_ground = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(8.0, 8.0)
	_ground.mesh = quad
	_ground.rotation.x = -PI * 0.5
	var floor_mat := StandardMaterial3D.new()
	floor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_mat.albedo_color = Color(0.34, 0.40, 0.30)
	_ground.material_override = floor_mat
	root.add_child(_ground)
	_holder = Node.new()
	root.add_child(_holder)
	var registry := _Registry.new()
	registry.entity_voxel_models_enabled = true
	registry.entity_sprites_enabled = false
	_holder.add_child(registry)
	_player = _Player.new()
	_player.name = "Player"
	_player.add_to_group("player")
	_holder.add_child(_player)
	_park_player(Vector2i(80, 80))


func _park_enemy_chase(home: Vector2i) -> void:
	var aim := Vector2i(home.x + 4, home.y)
	var world := _place_marker(aim)
	_player.voxel_position = world
	_player.global_position = world


func _park_player(cell: Vector2i) -> void:
	var ws = _Settings.get_active()
	_player.voxel_position = Vector3(float(cell.x) + 0.5, 4.0, float(cell.y) + 0.5)
	_player.global_position = Vector3(
		ws.column_to_world(_player.voxel_position.x),
		4.0,
		ws.column_to_world(_player.voxel_position.z)
	)


func _place_marker(cell: Vector2i) -> Vector3:
	var ws = _Settings.get_active()
	return Vector3(ws.column_to_world(float(cell.x) + 0.5), 0.0, ws.column_to_world(float(cell.y) + 0.5))


func _aim(at: Vector3) -> void:
	var yaw := deg_to_rad(45.0)
	var hdist := 100.0 * sqrt(2.0)
	var focus := at + Vector3(0.0, 1.4, 0.0)
	_cam.position = focus + Vector3(sin(yaw) * hdist, 101.0, cos(yaw) * hdist)
	_cam.rotation_degrees = Vector3(-35.264, 45.0, 0.0)
	_ground.global_position = Vector3(at.x, 0.0, at.z)


func _shoot_player() -> void:
	var ws = _Settings.get_active()
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "PlayerMesh"
	_stage = mesh_node
	root.add_child(mesh_node)
	_Body.apply_to(mesh_node, ws.player_height(), ws.player_radius())
	var home := Vector3(0.0, 0.0, 0.0)
	mesh_node.global_position = home
	_Body.play_pose(mesh_node, "idle", 0.0)
	var rest := _corners(mesh_node)
	_aim(home)
	for _i in 8:
		_Body.play_pose(mesh_node, "idle", float(_i) * 0.35)
		await process_frame
	await RenderingServer.frame_post_draw
	var idle_shift := _max_delta(rest, _corners(mesh_node))
	var idle_px := await _shot("player_idle")
	var idle_pose := _corners(mesh_node)
	_Body.play_pose(mesh_node, "walk", 1.6)
	await process_frame
	await RenderingServer.frame_post_draw
	var walk_shift := _max_delta(idle_pose, _corners(mesh_node))
	var walk_px := await _shot("player_walk")
	_grade("player", "idle", "walk", idle_shift, walk_shift, idle_px, walk_px, mesh_node, true)
	mesh_node.free()
	_stage = null


func _shoot_animal(kind: String) -> void:
	var cfg = _Brains.get_def(StringName(kind))
	if cfg == null:
		_fail_line(kind, "no brain")
		return
	var home := Vector2i(12, 9)
	var entity := _WorldEntity.new()
	_holder.add_child(entity)
	entity.set_physics_process(false)
	entity.setup(cfg, home, null, null, null)
	var mark := _place_marker(home)
	entity.global_position = mark
	_aim(mark)
	var rig := _visual(entity)
	var rest := _corners(rig) if rig != null else {}
	var idle_shift := 0.0
	for _i in 24:
		await process_frame
		if rig != null:
			idle_shift = maxf(idle_shift, _max_delta(rest, _corners(rig)))
	var idle_pose := str(entity.get("locomotion_pose"))
	entity.global_position = mark
	_aim(mark)
	var idle_px := await _shot("%s_idle" % kind)
	var posed := _corners(rig) if rig != null else {}
	entity.set_physics_process(true)
	var walk_shift := 0.0
	var walk_pose := idle_pose
	var walked := 0.0
	var origin := entity.global_position
	var walk_px := {"pixels": 0, "tall": 0}
	for _w in 180:
		await process_frame
		walked = entity.global_position.distance_to(origin)
		walk_pose = str(entity.get("locomotion_pose"))
		if rig != null:
			walk_shift = maxf(walk_shift, _max_delta(posed, _corners(rig)))
		if walk_pose == "walk" and walk_shift >= 0.2 and walked > 0.3:
			entity.set_physics_process(false)
			entity.set_process(false)
			entity.global_position = mark
			_aim(mark)
			if rig != null:
				_Creature.play(rig, "walk", 0.8)
			walk_px = await _shot("%s_walk" % kind)
			break
	if int(walk_px.get("pixels", 0)) == 0:
		entity.global_position = mark
		_aim(mark)
		walk_px = await _shot("%s_walk" % kind)
	entity.set_physics_process(false)
	_grade(kind, idle_pose, walk_pose, idle_shift, walk_shift, idle_px, walk_px, entity, true)
	entity.queue_free()


func _shoot_enemy(kind: String) -> void:
	var home := Vector2i(20, 20)
	_park_enemy_chase(home)
	var enemy := _CrystalEnemy.new()
	enemy.enemy_id = StringName(kind)
	_holder.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = _place_marker(home)
	enemy.setup(StringName(kind), _player)
	var mark := _place_marker(home)
	enemy.global_position = mark
	_aim(mark)
	var rig := _visual(enemy)
	var rest := _corners(rig) if rig != null else {}
	var idle_shift := 0.0
	for _i in 24:
		await process_frame
		if rig != null:
			idle_shift = maxf(idle_shift, _max_delta(rest, _corners(rig)))
	var idle_pose := str(enemy.get("locomotion_pose"))
	enemy.global_position = mark
	_aim(mark)
	var idle_px := await _shot("%s_idle" % kind)
	var posed := _corners(rig) if rig != null else {}
	enemy.set_physics_process(true)
	var walk_shift := 0.0
	var walk_pose := idle_pose
	var walked := 0.0
	var origin := enemy.global_position
	var walk_px := {"pixels": 0, "tall": 0}
	for _w in 180:
		await process_frame
		walked = enemy.global_position.distance_to(origin)
		walk_pose = str(enemy.get("locomotion_pose"))
		if rig != null:
			walk_shift = maxf(walk_shift, _max_delta(posed, _corners(rig)))
		if walk_pose == "walk" and walk_shift >= 0.2 and walked > 0.3:
			enemy.set_physics_process(false)
			enemy.set_process(false)
			enemy.global_position = mark
			_aim(mark)
			if rig != null:
				_Creature.play(rig, "walk", 0.8)
			walk_px = await _shot("%s_walk" % kind)
			break
	if int(walk_px.get("pixels", 0)) == 0:
		enemy.global_position = mark
		_aim(mark)
		walk_px = await _shot("%s_walk" % kind)
	enemy.set_physics_process(false)
	_grade(kind, idle_pose, walk_pose, idle_shift, walk_shift, idle_px, walk_px, enemy, false)
	enemy.queue_free()
	_park_player(Vector2i(80, 80))


func _grade(kind: String, idle_pose: String, walk_pose: String, idle_shift: float, walk_shift: float, idle_px: Dictionary, walk_px: Dictionary, body: Node, want_idle: bool) -> void:
	var expect := kind in RIGGED
	var info := _style(body)
	var idle_ok := (not want_idle or idle_pose == "idle") and idle_shift >= 0.05 and int(idle_px.get("pixels", 0)) >= 40
	var walk_ok := walk_pose == "walk" and walk_shift >= 0.2 and int(walk_px.get("pixels", 0)) >= 40
	var style_ok := int(info["sprites"]) == 0 and int(info["meshes"]) >= 2 and not bool(info["flat"]) and str(info["rig"]) != ""
	if not expect:
		style_ok = false
	var anim_ok := idle_ok and walk_ok
	if expect and not anim_ok:
		_failed += 1
	if expect and not style_ok:
		_failed += 1
	var anim := "PASS" if anim_ok else "FAIL"
	var style := "PASS" if style_ok else "FAIL"
	if not expect:
		anim = "SKIP"
		style = "FAIL"
	var line := "CHECK %s anim=%s style=%s idle_pose=%s walk_pose=%s idle_shift=%.3f walk_shift=%.3f idle_px=%d walk_px=%d sprites=%d meshes=%d flat=%s rig=%s" % [
		kind, anim, style, idle_pose, walk_pose, idle_shift, walk_shift,
		int(idle_px.get("pixels", 0)), int(walk_px.get("pixels", 0)),
		int(info["sprites"]), int(info["meshes"]), str(info["flat"]), str(info["rig"]),
	]
	print(line)
	_lines.append(line)


func _fail_line(kind: String, why: String) -> void:
	_failed += 1
	var line := "CHECK %s anim=FAIL style=FAIL %s" % [kind, why]
	print(line)
	_lines.append(line)


func _visual(body: Node) -> Node3D:
	var rig := body.get_node_or_null("CreatureRig") as Node3D
	if rig != null and rig.visible:
		return rig
	var prop := body.get_node_or_null("VoxelProp") as Node3D
	if prop != null and prop.visible:
		return prop
	return body as Node3D


func _style(body: Node) -> Dictionary:
	var info := {"sprites": 0, "meshes": 0, "flat": true, "rig": ""}
	if body != null:
		_walk_style(body, body, info)
	return info


func _walk_style(root: Node, node: Node, info: Dictionary) -> void:
	if str(node.name) == "ContactShadow":
		return
	if node.name == "CreatureRig" or node.name == "PlayerRig":
		info["rig"] = str(node.name)
	if node is Sprite3D and (node as Node3D).visible:
		info["sprites"] = int(info["sprites"]) + 1
	if node is MeshInstance3D and node != root:
		var mi := node as MeshInstance3D
		if mi.visible and mi.mesh != null:
			info["meshes"] = int(info["meshes"]) + 1
			var box := mi.get_aabb().size
			var thin := minf(box.x, minf(box.y, box.z))
			var wide := maxf(box.x, maxf(box.y, box.z))
			if wide > 0.02 and thin > wide * 0.2:
				info["flat"] = false
			if mi.material_override is StandardMaterial3D:
				var mat := mi.material_override as StandardMaterial3D
				if mat.albedo_texture != null:
					info["sprites"] = int(info["sprites"]) + 1
	for child in node.get_children():
		_walk_style(root, child, info)


func _shot(name: String) -> Dictionary:
	for _i in 2:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var path := _scratch.path_join("%s.png" % name)
	if img == null:
		print("SHOT missing %s" % name)
		return {"pixels": 0, "tall": 0}
	img.save_png(path)
	var stats := _subject_pixels(img)
	print("SHOT %s pixels=%d tall=%d" % [path, int(stats["pixels"]), int(stats["tall"])])
	return stats


func _subject_pixels(img: Image) -> Dictionary:
	var n := 0
	var y0 := img.get_height()
	var y1 := 0
	var step := 2
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var px := img.get_pixel(x, y)
			if absf(px.r - CLEAR.r) + absf(px.g - CLEAR.g) + absf(px.b - CLEAR.b) < 0.25:
				continue
			n += 1
			y0 = mini(y0, y)
			y1 = maxi(y1, y)
	var tall := 0 if n == 0 else (y1 - y0)
	return {"pixels": n * step * step, "tall": tall}


func _corners(root: Node) -> Dictionary:
	var out := {}
	if root is Node3D:
		_corner_walk(root as Node3D, root, out)
	return out


func _corner_walk(root: Node3D, node: Node, out: Dictionary) -> void:
	if node is MeshInstance3D and node != root:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var box := mi.get_aabb()
			var corner: Vector3 = mi.global_transform * (box.position + Vector3(box.size.x, 0.0, box.size.z))
			out[str(root.get_path_to(mi))] = root.to_local(corner)
	for child in node.get_children():
		_corner_walk(root, child, out)


func _max_delta(before: Dictionary, after: Dictionary) -> float:
	var best := 0.0
	for key in before.keys():
		if not after.has(key):
			continue
		best = maxf(best, (before[key] as Vector3).distance_to(after[key]))
	return best


func _write_log() -> void:
	var file := FileAccess.open(_scratch.path_join("checks.txt"), FileAccess.WRITE)
	if file == null:
		return
	for line in _lines:
		file.store_line(line)
	file.close()
