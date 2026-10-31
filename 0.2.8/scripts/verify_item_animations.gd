extends SceneTree


const _ItemAnim = preload("res://systems/item_anim.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _HeldItemView = preload("res://systems/held_item_view.gd")
const _AimIndicator = preload("res://systems/aim_indicator.gd")
const _HitMarkers = preload("res://systems/hit_markers.gd")
const _WeaponController = preload("res://weapons/weapon_controller.gd")
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _CombatVfx = preload("res://systems/combat_visual_feedback.gd")
const _PlayerSettings = preload("res://systems/player_settings.gd")

var _failed := false


class _Rig extends Node3D:
	var camera: Camera3D
	var voxel_position := Vector3.ZERO


class _FarHighlight extends Node:
	func get_action_column() -> Vector3:
		return Vector3(500.0, 2.0, 500.0)


class _AimLog extends RefCounted:
	var cells: Array[Vector2i] = []
	var actives: Array[bool] = []

	func on_aim(cell: Vector2i, _world_pos: Vector3, active: bool) -> void:
		cells.append(cell)
		actives.append(active)


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _run() -> void:
	await process_frame
	_check_kinds()
	_check_impact_frames()
	_check_controller_clock()
	_check_held_pool()
	_check_held_reads()
	_check_aim()
	_check_hit_markers()
	_PlayerSettings.hit_markers_enabled = true
	_PlayerSettings.crack_overlay_enabled = true
	if _failed:
		quit(1)
	else:
		print("All item animation checks OK")
		quit(0)


func _check_kinds() -> void:
	var expect := {
		"wooden_sword": _ItemAnim.Kind.SWING,
		"spear": _ItemAnim.Kind.THRUST,
		"crystal_hammer": _ItemAnim.Kind.SWING,
		"stone_pick": _ItemAnim.Kind.SWING,
		"shortbow": _ItemAnim.Kind.AIM,
		"sling": _ItemAnim.Kind.AIM,
		"herb": _ItemAnim.Kind.RAISE,
		"crystal_bomb": _ItemAnim.Kind.RAISE,
		"wood": _ItemAnim.Kind.RAISE,
		"stone": _ItemAnim.Kind.RAISE,
		"crystal_shard": _ItemAnim.Kind.RAISE,
		"leather_armor": _ItemAnim.Kind.NONE,
		"stone_plate": _ItemAnim.Kind.NONE,
		"crystal_weave": _ItemAnim.Kind.NONE,
	}
	for item_id in _ItemTypes.ITEMS:
		var spec: Dictionary = _ItemAnim.spec_for(str(item_id))
		var kind := int(spec.get("kind", -1))
		if kind < _ItemAnim.Kind.NONE or kind > _ItemAnim.Kind.AIM:
			_fail("anim kind out of range for %s" % item_id)
			continue
		if expect.has(item_id) and kind != int(expect[item_id]):
			_fail("%s kind %s expected %s" % [item_id, kind, expect[item_id]])
		var ratio := float(spec.get("impact_ratio", -1.0))
		if ratio < 0.0 or ratio > 0.92:
			_fail("%s impact ratio %s" % [item_id, ratio])
	if int(_ItemAnim.spec_for("missing_item").get("kind", -1)) != _ItemAnim.Kind.NONE:
		_fail("unknown item should have no pose")
	else:
		print("OK item kinds")


func _check_impact_frames() -> void:
	var step := 1.0 / 60.0
	for item_id in ["wooden_sword", "spear", "crystal_hammer", "shortbow", "stone_pick"]:
		var spec: Dictionary = _ItemAnim.spec_for(item_id)
		var impact := float(spec.get("impact_time", -1.0))
		var pb = _ItemAnim.playback_for(item_id)
		var fired_at := -1.0
		var guard := 0
		while guard < 400:
			var before := float(pb.elapsed)
			var fired: bool = pb.advance(step)
			if fired:
				if impact > 0.0 and before > impact + 0.0001:
					_fail("%s fired after the impact window" % item_id)
				if float(pb.elapsed) + 0.0001 < impact:
					_fail("%s damage sample is before impact" % item_id)
				fired_at = float(pb.elapsed)
				break
			if before + step < impact - 0.0001 and float(pb.elapsed) >= impact:
				_fail("%s crossed impact without firing" % item_id)
			guard += 1
		if fired_at < 0.0:
			_fail("%s never reached impact" % item_id)
		elif fired_at > impact + step + 0.001:
			_fail("%s impact sample drifted to %s (impact %s)" % [item_id, fired_at, impact])
	if not _failed:
		print("OK swing impact frames")


func _check_controller_clock() -> void:
	var wc = _WeaponController.new()
	wc.begin_animation_clock("wooden_sword")
	var impact := wc.animation_impact_time()
	var step := 1.0 / 60.0
	var fired := false
	var guard := 0
	while guard < 300:
		var hit: bool = wc.tick_animation_clock(step)
		if not hit and wc.animation_damage_elapsed() >= 0.0:
			_fail("controller recorded damage before the impact frame")
			break
		if hit:
			fired = true
			var elapsed := wc.animation_damage_elapsed()
			if absf(elapsed - impact) > step + 0.001:
				_fail("controller damage at %s, impact %s" % [elapsed, impact])
			break
		guard += 1
	wc.free()
	if not fired:
		_fail("controller clock never released the strike")
	else:
		print("OK controller impact clock")


func _check_held_pool() -> void:
	var view = _HeldItemView.new()
	root.add_child(view)
	var kids := view.visual_child_count()
	for i in 50:
		var id := "wooden_sword" if i % 2 == 0 else "shortbow"
		view.show_item(id)
		view.apply_playback(_ItemAnim.playback_for("spear" if i % 3 == 0 else "herb"))
	if view.visual_child_count() != kids or view.get_child_count() != 2:
		_fail("held item view allocated nodes across 50 poses")
	elif view.get_node("Arm").cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_fail("held item casts a shadow")
	elif view.get_node("HeldItem").cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_fail("held item mesh casts a shadow")
	else:
		print("OK held item pool")


func _check_held_reads() -> void:
	var ws = _WorldSettings.get_active()
	var vs: float = ws.voxel_scale
	var view = _HeldItemView.new()
	root.add_child(view)
	view.show_item("wooden_sword")
	var icon: Node3D = view.get_node("HeldItem")
	if icon is SpriteBase3D or _held_mesh_count(icon) < 1:
		_fail("held sword is a flat sprite, not a 3D mesh")
	else:
		var bounds := _held_local_bounds(icon)
		var thin := minf(bounds.size.x, bounds.size.z)
		if bounds.size.y < ws.player_height():
			_fail("held sword height %.2f is shorter than the body %.2f" % [bounds.size.y, ws.player_height()])
		elif thin < vs * 0.12:
			_fail("held sword is a flat card (thickness %.3f)" % thin)
		else:
			var half_w := bounds.size.x * 0.5
			var inner := absf(icon.position.x) - half_w
			if inner < ws.player_radius() * 0.9:
				_fail("held sword overlaps the torso (inner %.2f radius %.2f)" % [inner, ws.player_radius()])
	var sword_ready: Vector3 = icon.position
	var sword = _ItemAnim.playback_for("wooden_sword")
	sword.elapsed = sword.impact_time() * 0.45
	view.apply_playback(sword)
	if icon.position.distance_to(sword_ready) < vs * 0.85:
		_fail("sword use pose barely moved (%.2f)" % icon.position.distance_to(sword_ready))
	view.show_item("spear")
	var spear_ready_z: float = icon.position.z
	var spear = _ItemAnim.playback_for("spear")
	spear.elapsed = spear.impact_time()
	view.apply_playback(spear)
	if spear_ready_z - icon.position.z < vs * 1.0:
		_fail("spear thrust did not lunge")
	view.show_item("herb")
	var herb_ready_y: float = icon.position.y
	var herb = _ItemAnim.playback_for("herb")
	herb.elapsed = herb.impact_time()
	view.apply_playback(herb)
	if icon.position.y < herb_ready_y + vs * 0.8:
		_fail("herb raise did not lift")
	view.show_item("shortbow")
	var bow_ready: Vector3 = icon.position
	var bow = _ItemAnim.playback_for("shortbow")
	bow.elapsed = bow.impact_time() * 0.5
	view.apply_playback(bow)
	if icon.position.distance_to(bow_ready) < vs * 0.2:
		_fail("bow draw did not move")
	view.show_item("crystal_hammer")
	var hammer_ready_y: float = icon.position.y
	var hammer = _ItemAnim.playback_for("crystal_hammer")
	if not is_equal_approx(float(hammer.impact_ratio), 0.62):
		_fail("hammer pre-hit impact_ratio must stay 0.62")
	elif not is_equal_approx(float(hammer.duration), 1.1):
		_fail("hammer pre-hit duration must stay 1.1")
	else:
		hammer.elapsed = hammer.impact_time() * 0.40
		view.apply_playback(hammer)
		var raised_y: float = icon.position.y
		if raised_y < hammer_ready_y + vs * 0.7:
			_fail("hammer is not raised during the pre-hit delay")
		hammer.elapsed = hammer.impact_time()
		view.apply_playback(hammer)
		if icon.position.y > raised_y - vs * 0.6:
			_fail("hammer did not slam down on the impact frame")
	view.show_item("leather_armor")
	if view.visible:
		_fail("armor should not show a held icon")
	elif not _failed:
		print("OK held item size and use poses")


func _held_mesh_count(node: Node) -> int:
	var n := 0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null and node.visible:
		n += 1
	for child in node.get_children():
		n += _held_mesh_count(child)
	return n


func _held_local_bounds(item: Node3D) -> AABB:
	var merged := AABB()
	var any := false
	var pending: Array[Node] = [item]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			pending.append(child)
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.mesh == null or not mi.visible:
				continue
			var xf := item.global_transform.affine_inverse() * mi.global_transform
			var ab := mi.get_aabb()
			for corner in _aabb_corners(ab):
				var p: Vector3 = xf * corner
				if not any:
					merged = AABB(p, Vector3.ZERO)
					any = true
				else:
					merged = merged.expand(p)
	return merged


func _aabb_corners(ab: AABB) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in 8:
		out.append(ab.position + Vector3(
			ab.size.x if (i & 1) != 0 else 0.0,
			ab.size.y if (i & 2) != 0 else 0.0,
			ab.size.z if (i & 4) != 0 else 0.0
		))
	return out


func _check_aim() -> void:
	var ws = _WorldSettings.get_active()
	var vs: float = ws.voxel_scale
	var rig := _Rig.new()
	rig.voxel_position = Vector3(10.0, 4.0, 20.0)
	rig.camera = Camera3D.new()
	rig.camera.name = "Camera3D"
	rig.add_child(rig.camera)
	var aim = _AimIndicator.new()
	rig.add_child(aim)
	aim.bind_player(rig)
	root.add_child(rig)
	rig.global_position = Vector3(ws.column_to_world(10.0), 4.0, ws.column_to_world(20.0))
	rig.camera.position = Vector3(0.0, vs * 1.6, 0.0)
	rig.camera.look_at(rig.camera.global_position + Vector3(0.0, 0.0, -8.0), Vector3.UP)
	var log := _AimLog.new()
	aim.tool_aim_changed.connect(log.on_aim)
	aim.tick("stone_pick")
	if log.cells.is_empty() or not log.actives[0]:
		_fail("tool aim did not signal a cell")
	else:
		var cell: Vector2i = log.cells[0]
		var origin := Vector2(rig.voxel_position.x, rig.voxel_position.z)
		var dist := Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5).distance_to(origin)
		if dist > _ActionTargeting.reach() + 0.05:
			_fail("tool cell %s is past interaction range (%s)" % [cell, dist])
	if aim.get_node("MeleeReticle").visible or aim.get_node("AimLine").visible:
		_fail("tool aim drew its own block marker")
	var before_signals := log.cells.size()
	aim.tick("stone_pick")
	if log.cells.size() != before_signals:
		_fail("tool aim signaled again for the same cell")
	aim.tick("wooden_sword")
	var ring: MeshInstance3D = aim.get_node("MeleeReticle")
	if not ring.visible:
		_fail("melee aim hid the reticle")
	var sword_reach := minf(float(_ItemTypes.get_def("wooden_sword").get("range", 2.8)), _ActionTargeting.reach()) * vs
	var flat_d := _horiz(ring.global_position, rig.global_position)
	if flat_d > sword_reach + 0.3 or absf(flat_d - sword_reach) > 0.35:
		_fail("melee reticle distance %s, reach %s" % [flat_d, sword_reach])
	rig.camera.look_at(rig.global_position + Vector3(0.0, 0.0, -vs * 1.5), Vector3.UP)
	aim.tick("wooden_sword")
	var pitched := _horiz(ring.global_position, rig.global_position)
	if pitched > sword_reach + 0.3:
		_fail("pitched melee reticle left reach (%s > %s)" % [pitched, sword_reach])
	rig.camera.look_at(rig.camera.global_position + Vector3(0.0, 0.0, -8.0), Vector3.UP)
	aim.tick("shortbow")
	var end: MeshInstance3D = aim.get_node("AimEnd")
	if not end.visible:
		_fail("ranged aim hid the end marker")
	var bow_reach := float(_ItemTypes.get_def("shortbow").get("range", 14.0)) * vs
	var bow_d := _horiz(end.global_position, rig.global_position)
	if bow_d > bow_reach + 0.35 or bow_d < vs:
		_fail("bow marker distance %s, cap %s" % [bow_d, bow_reach])
	rig.camera.look_at(rig.global_position + Vector3(0.0, 0.0, -vs * 2.0), Vector3.UP)
	aim.tick("shortbow")
	if _horiz(end.global_position, rig.global_position) > bow_reach + 0.35:
		_fail("pitched bow marker left its range")
	var aim_kids := aim.get_child_count()
	for _i in 50:
		aim.tick("wooden_sword" if _i % 2 == 0 else "shortbow")
	if aim.get_child_count() != aim_kids:
		_fail("aim indicator allocated nodes")
	elif ring.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_fail("aim reticle casts a shadow")
	_check_aim_clamp(ws, vs)
	if not _failed:
		print("OK aim indicator")


func _check_aim_clamp(ws, vs: float) -> void:
	var rig := _Rig.new()
	rig.voxel_position = Vector3(10.0, 4.0, 20.0)
	var hl := _FarHighlight.new()
	hl.name = "TargetHighlight"
	rig.add_child(hl)
	var aim = _AimIndicator.new()
	rig.add_child(aim)
	aim.bind_player(rig)
	root.add_child(rig)
	rig.global_position = Vector3(ws.column_to_world(10.0), 4.0, ws.column_to_world(20.0))
	var log := _AimLog.new()
	aim.tool_aim_changed.connect(log.on_aim)
	aim.tick("stone_pick")
	if log.cells.is_empty():
		_fail("clamped tool aim did not signal")
		return
	var cell: Vector2i = log.cells[0]
	var origin := Vector2(10.0, 20.0)
	var dist := Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5).distance_to(origin)
	if dist > _ActionTargeting.reach() + 0.05:
		_fail("highlight cell was not clamped (%s dist %s)" % [cell, dist])
	if vs <= 0.0:
		_fail("voxel scale missing")


func _check_hit_markers() -> void:
	var marks = _HitMarkers.new()
	root.add_child(marks)
	var kids := marks.get_child_count()
	if kids != 6:
		_fail("hit marker pool size %s" % kids)
		return
	var hit := marks.show_at(Vector3(0, 1, 0), _HitMarkers.Result.HIT, 0.4)
	var miss := marks.show_at(Vector3(1, 1, 0), _HitMarkers.Result.MISS, 0.4)
	var blocked := marks.show_at(Vector3(2, 1, 0), _HitMarkers.Result.BLOCKED, 0.4)
	var ca := marks.slot_tint(hit)
	var cb := marks.slot_tint(miss)
	var cc := marks.slot_tint(blocked)
	if ca.is_equal_approx(cb) or ca.is_equal_approx(cc) or cb.is_equal_approx(cc):
		_fail("hit, miss, and blocked markers share a colour")
	if blocked.get_node("Cross").visible == false or blocked.get_node("Ring").visible:
		_fail("blocked marker should be a cross")
	if hit.get_node("Ring").cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_fail("hit marker casts a shadow")
	for i in 50:
		marks.show_at(Vector3(float(i), 0.0, 0.0), i % 3, 0.3)
	if marks.get_child_count() != kids:
		_fail("hit markers allocated nodes across 50 shows")
	_PlayerSettings.hit_markers_enabled = false
	if marks.show_at(Vector3.ZERO, _HitMarkers.Result.HIT, 0.2) != null:
		_fail("hit markers ignored the settings toggle")
	_PlayerSettings.hit_markers_enabled = true
	var vfx = _CombatVfx.new()
	root.add_child(vfx)
	vfx.show_attack_feedback(Vector3(1, 0, 2), _HitMarkers.Result.HIT)
	vfx.show_attack_feedback(Vector3(2, 0, 2), _HitMarkers.Result.MISS)
	vfx.show_attack_feedback(Vector3(3, 0, 2), _HitMarkers.Result.BLOCKED)
	var live = vfx.get_node_or_null("HitMarkers")
	if live == null or int(live.visible_count()) < 3:
		_fail("attack feedback did not show hit, miss, and blocked")
	elif live.get_child_count() != 6:
		_fail("attack feedback grew the hit-marker pool")
	else:
		print("OK hit markers")


func _horiz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
