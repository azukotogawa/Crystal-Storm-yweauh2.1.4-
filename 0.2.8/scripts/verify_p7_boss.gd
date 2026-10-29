extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")
const GI = preload("res://helpers/gameplay_input.gd")
const _Enemy = preload("res://entities/crystal_enemy.gd")


func _init() -> void:
	call_deferred("_run")


func _flash(node: Node) -> float:
	var best := 0.0
	if node is GeometryInstance3D and str(node.name) != "TelegraphRing" and str(node.name) != "StrikeTelegraph":
		var a = (node as GeometryInstance3D).get_instance_shader_parameter("flash_amount")
		if a != null:
			best = maxf(best, float(a))
	for c in node.get_children():
		best = maxf(best, _flash(c))
	return best


func _body_offset(node: Node) -> float:
	var s := 0.0
	for c in node.get_children():
		if c is MeshInstance3D and str(c.name) != "TelegraphRing" and str(c.name) != "StrikeTelegraph":
			s += c.position.length()
		s += _body_offset(c)
	return s


func _run() -> void:
	var tag := OS.get_environment("P7_TAG")
	var p = await C.boot(self)
	GI.world_loading = false
	GI.modal_open = false
	var vs := C.vs()
	var spawner = get_first_node_in_group("crystal_enemy_spawner")
	var parent: Node = spawner.get_parent() if spawner else root
	for act in [&"slam", &"charge", &"burst"]:
		var e = _Enemy.new()
		parent.add_child(e)
		var off := 2.0 if act != &"charge" else 7.0
		e.global_position = p.global_position + Vector3(off * vs, 0.0, 0.0)
		e.setup(&"origin_warden", p)
		for _i in 3:
			await physics_frame
		e._special.cooldown = 0.0
		e._special._arm(act)
		var anims := []
		var max_flash := 0.0
		var ring_red := 0
		var ring_frames := 0
		var moved_frames := 0
		var max_step := 0.0
		var total := 0.0
		var pose_var := 0.0
		var last_off := -1.0
		var last: Vector3 = e.global_position
		for f in 150:
			p.health = p.max_health
			await physics_frame
			var ring = e.get_node_or_null("TelegraphRing")
			if ring and ring.visible:
				ring_frames += 1
				var col: Color = ring.material_override.albedo_color
				if col.r > 0.9 and col.g < 0.5 and col.b < 0.3:
					ring_red += 1
			max_flash = maxf(max_flash, _flash(e))
			var an = e.get("boss_anim")
			var nm: String = "%s/%s" % [str(an), e.locomotion_pose]
			if anims.is_empty() or anims[-1] != nm:
				anims.append(nm)
			var bo := _body_offset(e)
			if last_off >= 0.0:
				pose_var = maxf(pose_var, absf(bo - last_off))
			last_off = bo
			var d: float = Vector2(e.global_position.x - last.x, e.global_position.z - last.z).length() / vs
			if d > 0.01:
				moved_frames += 1
				total += d
			max_step = maxf(max_step, d)
			last = e.global_position
		print("P7_BOSS tag=%s act=%s ring_frames=%d ring_red=%d max_body_flash=%.2f moved_frames=%d max_step_cols=%.2f total_cols=%.2f pose_part_delta=%.3f anims=%s" % [tag, act, ring_frames, ring_red, max_flash, moved_frames, max_step, total, pose_var, ",".join(anims)])
		e.queue_free()
		await physics_frame
	quit(0)