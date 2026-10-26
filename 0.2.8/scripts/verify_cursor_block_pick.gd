extends SceneTree

const _ActionTargeting = preload("res://player/action_targeting.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FacePick = preload("res://player/face_pick.gd")

var _failed: int = 0
var _checked: int = 0


class _Host extends Player:
	func _ready() -> void:
		pass


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	print("FAIL " + msg)


func _run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1280, 720)
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(view)
	var ws = _WorldSettings.get_active()
	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 5
	world.name = "World"
	world.add_to_group("world")
	view.add_child(world)
	var player := _Host.new()
	player.name = "Player"
	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	player.add_child(mesh)
	player.set_process(false)
	player.set_physics_process(false)
	var home := Vector2i(20, 20)
	var top := _TerrainEdits.surface_block_y(world, home.x, home.y)
	var s: float = ws.voxel_scale
	player.voxel_position = Vector3(home.x + 0.5, float(top), home.y + 0.5)
	var inv := Inventory.new()
	inv.set_slot(0, "stone_pick", 1)
	player.inventory = inv
	player.world = world
	view.add_child(player)
	player.global_position = Vector3((home.x + 0.5) * s, float(top) * s, (home.y + 0.5) * s)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.current = true
	view.add_child(cam)
	player.camera = cam
	var weapon := WeaponController.new()
	weapon.name = "WeaponController"
	weapon.set_process(false)
	player.add_child(weapon)
	var hl := TargetHighlight.new()
	hl.name = "TargetHighlight"
	hl.set_process(false)
	player.add_child(hl)
	await process_frame
	await process_frame
	weapon.set_active_hotbar_index(0)
	var rect := view.get_visible_rect()
	for zoom in [16.0, 40.0]:
		cam.size = zoom
		for yaw_deg in [45.0, 100.0, 200.0, 315.0]:
			var yaw := deg_to_rad(yaw_deg)
			var hdist := 100.0 * sqrt(2.0)
			cam.global_position = player.global_position + Vector3(sin(yaw) * hdist, 101.0, cos(yaw) * hdist)
			cam.rotation_degrees = Vector3(-35.264, yaw_deg, 0.0)
			for dx in range(-6, 7, 2):
				for dz in range(-6, 7, 2):
					var cx := home.x + dx
					var cz := home.y + dz
					var cy := _TerrainEdits.surface_block_y(world, cx, cz)
					var face := Vector3((cx + 0.5) * s, float(cy) * s, (cz + 0.5) * s)
					var at := cam.unproject_position(face)
					if not rect.has_point(at):
						continue
					var motion := InputEventMouseMotion.new()
					motion.position = at
					motion.global_position = at
					view.push_input(motion, true)
					_ActionTargeting.note_event_mouse(at, rect.size)
					hl._aim_cache_ok = false
					hl._process(0.016)
					var got: Vector3 = hl.get_action_column()
					var gc := Vector2i(floori(got.x), floori(got.z))
					var vis: bool = hl._mesh.visible
					var pick: Vector3i = _ActionTargeting.last_pick_cell
					_checked += 1
					var truth: Dictionary = _FacePick.pick(world, cam.project_ray_origin(at), cam.project_ray_normal(at), _FacePick.eye(player), INF)
					if not bool(truth.get("hit", false)):
						_fail("no block under %s" % at)
						continue
					var tc: Vector3i = truth.cell
					cy = tc.y + 1
					var want := Vector2i(tc.x, tc.z)
					if _ActionTargeting.last_pick_face != _FacePick.face_code(truth.normal):
						_fail("face %d want %d" % [_ActionTargeting.last_pick_face, _FacePick.face_code(truth.normal)])
					var why := ""
					if not vis:
						why = "highlight hidden"
					elif gc != want:
						why = "highlight on %s" % gc
					elif pick != tc:
						why = "pick cell %s want %s" % [pick, tc]
					if why != "":
						_fail("zoom %.0f yaw %.0f block %s dist %.1f: %s" % [zoom, yaw_deg, want, Vector2(dx, dz).length(), why])
	print("checked %d" % _checked)
	if _failed == 0 and _checked > 40:
		print("All cursor block pick checks OK")
		quit(0)
	else:
		quit(1)