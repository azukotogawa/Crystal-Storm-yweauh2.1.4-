extends SceneTree

const C = preload("res://scripts/verify_p6_common.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var p = await C.boot(self)
	var pc: Vector2i = C.pcol(p)
	var m = await C.spawn_mite(self, pc + Vector2i(2, 0))
	for _f in 30:
		await physics_frame
	var world = get_first_node_in_group("world")
	if world == null:
		world = p.get("world")
	var mc := Vector2(float(pc.x + 2) + 0.5, float(pc.y) + 0.5)
	print("DBG vs=%.2f p_gpos=%s p_vox=%s p_feet_sample=%.3f surf_p=%.3f surf_m=%.3f m_gpos=%s m_center=%s m_radius=%.3f ph=%.3f" % [C.vs(), p.global_position, p.voxel_position, p._sample_walkable_feet(float(pc.x) + 0.5, float(pc.y) + 0.5), world.get_surface_height(float(pc.x) + 0.5, float(pc.y) + 0.5) if world else -1.0, world.get_surface_height(mc.x, mc.y) if world else -1.0, m.global_position, m.get_combat_center(), m.get_combat_radius() if m.has_method("get_combat_radius") else -1.0, Player.get_player_height()])
	quit(0)
