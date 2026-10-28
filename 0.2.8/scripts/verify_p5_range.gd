extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const _AT = preload("res://player/action_targeting.gd")
const _Strike = preload("res://weapons/weapon_strike.gd")
const _Stub = preload("res://scripts/spatial_combat_stub.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(game)
	var player = null
	for _i in 1800:
		player = get_first_node_in_group("player")
		if player and bool(player.get("world_ready")):
			break
		await process_frame
	for _i in 60:
		await physics_frame
	var ws = WorldSettings.get_active()
	var scale: float = ws.voxel_scale
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var v: Vector3 = player.get_voxel_position()
	var cx := int(floor(v.x))
	var cz := int(floor(v.z))
	var stub: Node3D = _Stub.new()
	stub.set_meta("combat_radius", 0.35 * scale / 2.0)
	root.add_child(stub)
	var origin: Vector3 = _AT.attack_origin_world(player, 0.5)
	var bad := 0
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for item in ["wooden_sword", "spear"]:
		var r: float = float(ItemTypes.get_def(item).get("range", 2.0))
		var n := int(floor(r))
		for dv in dirs:
			var dir: Vector2i = dv
			for d in [n - 1, n, n + 1]:
				var col := Vector2i(cx, cz) + dir * int(d)
				var lit: bool = _AT._column_in_range(player, col.x, col.y, r)
				var top := Vector3(ws.column_to_world(float(col.x) + 0.5), player.global_position.y, ws.column_to_world(float(col.y) + 0.5))
				stub.global_position = Vector3(top.x, origin.y, top.z)
				var hit := false
				if item == "spear":
					hit = not _Strike.thrust_targets(origin, Vector3(dir.x, 0, dir.y), r * scale, [stub], 2).is_empty()
				else:
					var ro := stub.global_position + Vector3(0, 10, 0)
					hit = CombatHitbox.pick_under_ray([stub], ro, Vector3.DOWN, origin, r * scale, 0.4) != null
				var sp := cam.unproject_position(top)
				var ro2 := cam.project_ray_origin(sp)
				var rd2 := cam.project_ray_normal(sp)
				var pt: Vector3 = ro2 + rd2 * ((player.global_position.y - ro2.y) / rd2.y)
				var gate: bool = _AT._column_in_range(player, int(floor(ws.world_to_column(pt.x))), int(floor(ws.world_to_column(pt.z))), r)
				var ok := lit == hit and lit == gate
				if not ok:
					bad += 1
				print("RANGE %s r=%.1f dir=%s d=%d lit=%s hit=%s gate=%s %s" % [item, r, dir, d, lit, hit, gate, "OK" if ok else "MISMATCH"])
	print("RANGE mismatches=%d" % bad)
	print("P5 RANGE " + ("OK" if bad == 0 else "FAIL"))
	quit(0 if bad == 0 else 1)