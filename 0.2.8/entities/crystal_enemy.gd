class_name CrystalEnemy
extends Node3D

const _EntityBrain = preload("res://entities/entity_brain.gd")
const _EntityBrainRegistry = preload("res://entities/entity_brain_registry.gd")
const _EntityNavigation = preload("res://entities/entity_navigation.gd")
const _EnemySpawnDef = preload("res://config/enemy_spawn_def.gd")
const _CombatLog = preload("res://systems/combat_log.gd")
const _VoxelPropBuilder = preload("res://helpers/voxel_prop_builder.gd")
const _VoxelCreature = preload("res://helpers/voxel_creature_builder.gd")
const _CombatRewards = preload("res://helpers/combat_rewards.gd")
const _BossBrain = preload("res://entities/boss_brain.gd")
const _Juice = preload("res://systems/juice.gd")
const _PlayerSettings = preload("res://systems/player_settings.gd")
const _ContactShadow = preload("res://helpers/contact_shadow.gd")
const _CreaturePose = preload("res://entities/creature_pose.gd")

signal detonated(damage: float)
signal attacked_player(damage: float)
signal combat_damaged(amount: float, remaining_health: float, source: StringName)
signal killed(enemy_id: StringName, world_pos: Vector2i, player_killed: bool)

@export var move_speed: float = 10.0
@export var contact_damage: float = 22.0
@export var detonate_radius: float = 2.8
@export var lifetime: float = 45.0
@export var max_health: float = 24.0

var enemy_id: StringName = &"crystal_mite"
var brain: _EntityBrain
var spawn_def: _EnemySpawnDef

var _target: Node3D
var _world: InfiniteNoiseWorld
var _chunk_manager: ChunkManager
var _crystal: CrystalManager
var _spatial: Node = null
var _profiler: Node = null
var _profiler_bound: bool = false
var health: float = 24.0
var _age: float = 0.0
var _mesh: MeshInstance3D
var _sprite: Sprite3D
var _voxel_prop: Node3D
var _part_rig: Node3D
var _bob_phase: float = 0.0
var _bob_ready: bool = false
var locomotion_pose: String = "idle"
var _attack_hold: float = 0.0
var _creature_pose: RefCounted = _CreaturePose.new()
var _bob_base_y: float = 0.0
var _bob_base_scale: Vector3 = Vector3.ONE
var _audio: Node
var _patrol_anchor: Vector2i = Vector2i.ZERO
var _last_damage_source: StringName = &""
var _hit_flash_timer: float = 0.0
var _base_tint: Color = Color(0.72, 0.2, 0.95)
var _mesh_radius: float = 0.22
var _hurt_player: float = 0.0
const HURT_LOCK := 0.22
var _knock_dir := Vector3.ZERO
var _knock_left := 0.0
var _special: _BossBrain
var _ring: MeshInstance3D
var _ring_anchor := Vector3.ZERO
var boss_phase: int = 1
const GUARDIAN_AGGRO_COLUMNS := 14.0
const GUARDIAN_LEASH_COLUMNS := 22.0
var _guardian_aggro: bool = false
var _heart_locked: bool = false
var _locked_heart: Vector2i = Vector2i.ZERO


func _ready() -> void:
	add_to_group("crystal_enemy")
	_bind_scene()
	_hook_visual_registry()
	_ContactShadow.attach(self, 0.06, 1.1)


func setup(
	id: StringName,
	target: Node3D,
	spawn_config: _EnemySpawnDef = null,
	patrol_anchor: Vector2i = Vector2i.ZERO
) -> void:
	enemy_id = id
	_target = target
	spawn_def = spawn_config
	_patrol_anchor = patrol_anchor
	_bind_scene()

	var brain_id: StringName = spawn_config.brain_config_id if spawn_config else id
	var brain_cfg = _EntityBrainRegistry.get_def(brain_id)
	if brain_cfg == null:
		brain_cfg = _EntityBrainRegistry.get_def(&"crystal_mite")
	brain = _EntityBrain.new(brain_cfg)

	var spawn_cell := _EntityNavigation.column_pos(global_position)
	if patrol_anchor != Vector2i.ZERO:
		spawn_cell = patrol_anchor
	brain.reset_at(spawn_cell, Vector2i.ZERO, patrol_anchor if patrol_anchor != Vector2i.ZERO else spawn_cell)

	if spawn_config:
		move_speed = spawn_config.move_speed
		contact_damage = spawn_config.contact_damage
		max_health = spawn_config.max_health
		lifetime = spawn_config.lifetime
		_mesh_radius = spawn_config.mesh_radius
		_base_tint = spawn_config.tint
		_setup_visual(spawn_config.tint, spawn_config.mesh_radius, spawn_config.mesh_height)
	else:
		_setup_visual(Color(0.72, 0.2, 0.95))

	health = max_health
	_bind_special(id)
	sync_spatial_index()


func refresh_visual() -> void:
	if spawn_def:
		_setup_visual(spawn_def.tint, spawn_def.mesh_radius, spawn_def.mesh_height)
	else:
		_setup_visual(_base_tint, _mesh_radius)


func _setup_visual(tint: Color, radius: float = 0.22, height: float = 0.70) -> void:
	_base_tint = tint
	_mesh_radius = radius
	if not is_inside_tree():
		call_deferred("_setup_visual", tint, radius, height)
		return
	var look := _visual_lookup_id()
	if _VoxelCreature.uses_rig(look) and _ensure_part_rig(look):
		_apply_body_scale()
		return
	_drop_part_rig()
	var registry = get_tree().get_first_node_in_group("game_visual_registry")
	if registry != null and bool(registry.get("entity_voxel_models_enabled")):
		_setup_voxel(tint)
		return
	var use_sprite: bool = registry != null and bool(registry.entity_sprites_enabled)
	var tex: Texture2D = _resolve_enemy_texture(registry) if use_sprite else null
	if use_sprite and tex != null:
		_setup_sprite(registry, tex, tint, height)
	else:
		_setup_mesh(tint, radius, height)
	_apply_body_scale()


func _hook_visual_registry() -> void:
	var registry = get_tree().get_first_node_in_group("game_visual_registry")
	if registry == null:
		return
	if registry.has_method("is_ready") and registry.is_ready():
		call_deferred("refresh_visual")
		return
	if registry.has_signal("visuals_ready") and not registry.visuals_ready.is_connected(_on_registry_visuals_ready):
		registry.visuals_ready.connect(_on_registry_visuals_ready, CONNECT_ONE_SHOT)


func _on_registry_visuals_ready() -> void:
	refresh_visual()


func _resolve_enemy_texture(registry) -> Texture2D:
	if registry == null:
		return null
	var look_id: StringName = _visual_lookup_id()
	if registry.has_method("get_sprite_texture"):
		return registry.get_sprite_texture(str(look_id))
	if registry.has_method("get_enemy_texture"):
		return registry.get_enemy_texture(look_id)
	return null


func _visual_lookup_id() -> StringName:
	if spawn_def:
		return spawn_def.resolved_visual_id()
	return enemy_id


func _ensure_part_rig(look: StringName) -> bool:
	var built: Node3D = _VoxelCreature.build(look)
	if built == null:
		return false
	if _sprite:
		_sprite.visible = false
	if _mesh:
		_mesh.visible = false
	if _voxel_prop:
		_voxel_prop.visible = false
	_drop_part_rig()
	_part_rig = built
	add_child(_part_rig)
	return true


func _drop_part_rig() -> void:
	if _part_rig and is_instance_valid(_part_rig):
		if _part_rig.get_parent() == self:
			remove_child(_part_rig)
		_part_rig.free()
	_part_rig = null


func repaint_creature() -> void:
	if _part_rig and is_instance_valid(_part_rig) and _VoxelCreature.uses_rig(_visual_lookup_id()):
		_VoxelCreature.repaint(_part_rig)


func _setup_voxel(tint: Color) -> void:
	if _sprite:
		_sprite.visible = false
	if _mesh:
		_mesh.visible = false
	if _voxel_prop == null or not is_instance_valid(_voxel_prop):
		if _voxel_prop:
			_voxel_prop.queue_free()
		_voxel_prop = _VoxelPropBuilder.build_entity(_visual_lookup_id(), tint)
		_voxel_prop.name = "VoxelProp"
		add_child(_voxel_prop)
	else:
		_VoxelPropBuilder.apply_tint(_voxel_prop, tint)
	_voxel_prop.visible = true


func _setup_sprite(registry, tex: Texture2D, tint: Color, height: float) -> void:
	if _sprite == null:
		_sprite = Sprite3D.new()
		_sprite.name = "Sprite3D"
		add_child(_sprite)
	if _mesh:
		_mesh.visible = false
	if _voxel_prop:
		_voxel_prop.visible = false
	_sprite.visible = true
	_sprite.position.y = height * WorldSettings.get_active().voxel_scale * 0.55
	if registry.has_method("apply_to_sprite3d"):
		registry.apply_to_sprite3d(_sprite, tex, tint)
	elif registry.has_method("configure_sprite3d"):
		registry.configure_sprite3d(_sprite, tex, tint, 0.01)
	else:
		_sprite.texture = tex
		_sprite.modulate = tint


func _setup_mesh(tint: Color, radius: float = 0.22, height: float = 0.70) -> void:
	if _sprite:
		_sprite.visible = false
	if _voxel_prop:
		_voxel_prop.visible = false
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		_mesh.name = "MeshInstance3D"
		add_child(_mesh)
	_mesh.visible = true
	var vs: float = WorldSettings.get_active().voxel_scale
	var mesh := CapsuleMesh.new()
	mesh.radius = radius * vs
	mesh.height = height * vs
	_mesh.mesh = mesh
	_mesh.position.y = mesh.height * 0.55
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _mesh.material_override == null:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = tint
		mat.emission_enabled = true
		mat.emission = tint * 0.55
		_mesh.material_override = mat
	elif _mesh.material_override is StandardMaterial3D:
		var mat := _mesh.material_override as StandardMaterial3D
		mat.albedo_color = tint
		mat.emission = tint * 0.55


func _apply_body_scale() -> void:
	var s := 1.0
	if enemy_id == &"origin_warden":
		s = 1.65
	elif enemy_id == &"spawn_elite":
		s = 1.35
	else:
		return
	if _part_rig and is_instance_valid(_part_rig):
		_part_rig.scale = Vector3(s, s, s)
	if _voxel_prop and is_instance_valid(_voxel_prop):
		_voxel_prop.scale = Vector3(s, s, s)
	if _sprite and is_instance_valid(_sprite):
		_sprite.scale = Vector3(s, s, s)


func _bind_special(id: StringName) -> void:
	_special = null
	if id == &"origin_warden":
		_special = _BossBrain.new()
		boss_phase = 1
		add_to_group("origin_boss")
		_ensure_ring()
		_notify_warden(true)
		call_deferred("_register_boss_hud")
	elif id == &"spawn_elite":
		_special = _BossBrain.new()
		_special.elite = true
		_ensure_ring()


func _ensure_ring() -> void:
	if _ring != null and is_instance_valid(_ring):
		return
	_ring = MeshInstance3D.new()
	_ring.name = "TelegraphRing"
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.06
	_ring.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.28, 0.18, 0.5)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring.material_override = mat
	_ring.visible = false
	add_child(_ring)


func _register_boss_hud() -> void:
	if not is_inside_tree():
		return
	var overlay = get_tree().get_first_node_in_group("game_overlay")
	if overlay and overlay.has_method("track_boss"):
		overlay.track_boss(self)


func _notify_warden(alive: bool) -> void:
	if not is_inside_tree():
		return
	var crystal = _crystal
	if crystal == null:
		crystal = get_tree().get_first_node_in_group("crystal_manager")
	if crystal and crystal.has_method("set_origin_warden_alive"):
		crystal.set_origin_warden_alive(alive)


func _bind_scene() -> void:
	if _world == null:
		_world = get_tree().get_first_node_in_group("world")
	if _chunk_manager == null:
		_chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	if _crystal == null:
		_crystal = get_tree().get_first_node_in_group("crystal_manager")


func get_combat_center() -> Vector3:
	return global_position


func get_combat_radius() -> float:
	var voxels := _mesh_radius * 1.2
	if spawn_def:
		voxels = spawn_def.hit_radius
	return maxf(voxels, 0.2) * WorldSettings.get_active().voxel_scale


func _spatial_service() -> Node:
	if _spatial != null and is_instance_valid(_spatial):
		return _spatial
	if not is_inside_tree():
		return null
	_spatial = get_tree().get_first_node_in_group("spatial_query_service")
	return _spatial


func sync_spatial_index() -> void:
	var svc := _spatial_service()
	if svc == null:
		return
	if svc.has_method("register_combatant"):
		svc.register_combatant(self)
	if svc.has_method("notify_moved"):
		svc.notify_moved(self)


func _notify_spatial_moved() -> void:
	var svc := _spatial_service()
	if svc and svc.has_method("notify_moved"):
		svc.notify_moved(self)


func get_combat_defense() -> float:
	return spawn_def.defense if spawn_def else 0.0


func is_combat_alive() -> bool:
	return health > 0.0 and is_inside_tree()


func _target_column_pos() -> Vector3:
	if _target == null:
		return global_position
	if _target.has_method("get_voxel_position"):
		return _target.get_voxel_position()
	return _target.global_position


func _player_column() -> Vector2i:
	if _target != null and is_instance_valid(_target) and _target.has_method("get_voxel_position"):
		var v: Vector3 = _target.get_voxel_position()
		return Vector2i(floori(v.x), floori(v.z))
	if _target != null and is_instance_valid(_target):
		return _EntityNavigation.column_pos(_target.global_position)
	return _EntityNavigation.column_pos(global_position)


func _player_world_pos() -> Vector3:
	if _target == null or not is_instance_valid(_target):
		return global_position
	if _target.has_method("get_voxel_position"):
		var v: Vector3 = _target.get_voxel_position()
		var ws = WorldSettings.get_active()
		return Vector3(ws.column_to_world(v.x), v.y, ws.column_to_world(v.z))
	return _target.global_position


func _is_guardian() -> bool:
	return enemy_id == &"origin_warden" or enemy_id == &"spawn_elite"


func bind_heart(cell: Vector2i) -> void:
	_heart_locked = true
	_locked_heart = cell
	_patrol_anchor = cell
	if brain:
		brain.home_pos = cell
		brain.patrol_anchor = cell
		brain.defend_center = cell
		brain.target_cell = cell


func _heart_cell() -> Vector2i:
	if _heart_locked:
		return _locked_heart
	if brain:
		return brain.home_pos
	return _patrol_anchor


func _refresh_guardian_aggro() -> void:
	if _target == null or not is_instance_valid(_target):
		_guardian_aggro = false
		return
	var heart := _heart_cell()
	var player_to_heart := Vector2(_player_column()).distance_to(Vector2(heart))
	var self_to_heart := Vector2(_EntityNavigation.column_pos(global_position)).distance_to(Vector2(heart))
	if player_to_heart > GUARDIAN_LEASH_COLUMNS or self_to_heart > GUARDIAN_LEASH_COLUMNS:
		_guardian_aggro = false
	elif player_to_heart <= GUARDIAN_AGGRO_COLUMNS:
		_guardian_aggro = true


func _cancel_guardian_attack() -> void:
	if _special == null:
		return
	if _special.windup <= 0.0 and (_ring == null or not _ring.visible):
		return
	_special.windup = 0.0
	_special.action = &""
	_hide_ring()


func _profiler_node() -> Node:
	if _profiler_bound:
		return _profiler
	_profiler_bound = true
	_profiler = get_node_or_null("/root/PerfProfiler")
	return _profiler


func _physics_process(delta: float) -> void:
	var profiler := _profiler_node()
	if profiler and profiler.has_method("begin"):
		profiler.begin("entity_physics")
	if _hit_flash_timer > 0.0:
		_hit_flash_timer = maxf(_hit_flash_timer - delta, 0.0)
		if _hit_flash_timer <= 0.0:
			_clear_flash()

	_age += delta
	_tick_hurt_lock(delta)
	var guardian := _is_guardian()
	if guardian:
		_refresh_guardian_aggro()
	if _special and (not guardian or _guardian_aggro):
		_tick_special(delta)
	elif guardian:
		_cancel_guardian_attack()
	if lifetime > 0.0 and _age >= lifetime:
		if profiler and profiler.has_method("end"):
			profiler.end("entity_physics")
		queue_free()
		return
	if _target == null or not is_instance_valid(_target) or brain == null:
		if profiler and profiler.has_method("end"):
			profiler.end("entity_physics")
		return

	var self_cell := _EntityNavigation.column_pos(global_position)
	var player_cell := self_cell
	if guardian:
		# voxel_position is already column space. column_pos() expects world units.
		player_cell = _player_column()
	else:
		player_cell = _EntityNavigation.column_pos(_target_column_pos())

	var target_pos := _target_column_pos()
	if brain.should_detonate(global_position, target_pos):
		_detonate()
		if profiler and profiler.has_method("end"):
			profiler.end("entity_physics")
		return

	var crystal_sim = _crystal.get_fluid_sim() if _crystal and _crystal.has_method("get_fluid_sim") else null
	var nearby_depth := _max_neighbor_crystal_depth(self_cell)
	var target_cell := brain.tick(delta, self_cell, player_cell, crystal_sim, nearby_depth)
	if guardian and not _guardian_aggro:
		target_cell = _heart_cell()

	if _knock_left > 0.0:
		var step := minf(_knock_left, maxf(move_speed, 6.0) * delta * 2.4)
		var shoved := _EntityNavigation.knockback_step(
			global_position, _knock_dir, step, _world, _chunk_manager, _crystal
		)
		if shoved.distance_squared_to(global_position) < 0.0004:
			_knock_left = 0.0
		else:
			global_position = shoved
			_knock_left = maxf(_knock_left - step, 0.0)
		_notify_spatial_moved()
		if profiler and profiler.has_method("end"):
			profiler.end("entity_physics")
		return

	var nav_t0 := Time.get_ticks_usec()
	global_position = _EntityNavigation.step_toward_cell(
		global_position,
		target_cell,
		move_speed,
		delta,
		_world,
		_chunk_manager,
		_crystal
	)
	_notify_spatial_moved()
	if profiler and profiler.has_method("record_us"):
		profiler.record_us("entity_navigation", Time.get_ticks_usec() - nav_t0)

	var did_attack := false
	var aim_cell := _player_column()
	var aim_pos := _player_world_pos()
	var in_reach := global_position.distance_to(aim_pos) <= 1.8
	if guardian:
		if _guardian_aggro and in_reach and brain.wants_attack(self_cell, aim_cell):
			did_attack = true
			_damage_player(contact_damage, &"", global_position)
			attacked_player.emit(contact_damage)
	elif in_reach and brain.wants_attack(self_cell, aim_cell):
		did_attack = true
		_damage_player(contact_damage, &"", global_position)
		attacked_player.emit(contact_damage)
	_apply_walk_bob(delta, target_cell != self_cell, did_attack)
	if profiler and profiler.has_method("end"):
		profiler.end("entity_physics")


func take_damage(amount: float, source: StringName = &"") -> void:
	if amount <= 0.0 or _hurt_player > 0.0:
		return
	_last_damage_source = source
	_hurt_player = HURT_LOCK
	health = maxf(health - amount, 0.0)
	if _special and max_health > 0.0:
		_special.notify_hp_ratio(health / max_health)
		boss_phase = _special.phase
	_flash_hit()
	combat_damaged.emit(amount, health, source)
	var label := spawn_def.display_name if spawn_def else str(enemy_id)
	_CombatLog.push("%s hit %.1f → %.0f HP" % [label, amount, health])
	if health <= 0.0:
		_on_killed()
	else:
		_sfx("enemy_hurt", global_position)


func _flash_hit() -> void:
	_hit_flash_timer = 0.14
	if not _PlayerSettings.flash_effects_enabled:
		return
	var vis := _active_visual()
	if vis:
		_Juice.set_flash(vis, 1.0)


func _on_killed() -> void:
	var label := spawn_def.display_name if spawn_def else str(enemy_id)
	var cell := _EntityNavigation.column_pos(global_position)
	var player_killed := _last_damage_source != &""
	_CombatLog.push("%s killed" % label)
	killed.emit(enemy_id, cell, player_killed)
	if player_killed and is_inside_tree():
		_CombatRewards.grant_player_kill(get_tree(), enemy_id, label)
		if enemy_id == &"origin_warden":
			_BossBrain.on_warden_killed(get_tree())
		elif enemy_id == &"spawn_elite":
			_BossBrain.on_elite_killed(get_tree(), int(global_position.x))
	elif enemy_id == &"origin_warden":
		_notify_warden(false)
	var death_id := "boss_death" if enemy_id == &"origin_warden" else "enemy_death"
	_sfx(death_id, global_position)
	_release_death_visual()
	queue_free()


func _damage_player(amount: float, source: StringName, origin: Vector3) -> void:
	if _target == null or not is_instance_valid(_target) or not _target.has_method("take_damage"):
		return
	if _target.has_method("set_damage_origin"):
		_target.set_damage_origin(origin)
	if source == &"":
		_target.take_damage(amount)
	else:
		_target.take_damage(amount, source)


func apply_knockback(dir: Vector3, distance: float) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001 or distance <= 0.0:
		return
	_knock_dir = flat.normalized()
	_knock_left = distance


func _tick_hurt_lock(delta: float) -> void:
	if _hurt_player > 0.0:
		_hurt_player = maxf(_hurt_player - delta, 0.0)


func _tick_special(delta: float) -> void:
	if _special == null:
		return
	var dist_v := 99.0
	if _target and is_instance_valid(_target):
		var there := _player_world_pos()
		dist_v = Vector2(there.x - global_position.x, there.z - global_position.z).length()
		dist_v /= maxf(WorldSettings.get_active().voxel_scale, 0.001)
	var intent: Dictionary = _special.tick(delta, dist_v)
	boss_phase = int(intent.get("phase", boss_phase))
	if bool(intent.get("phase_changed", false)):
		_sfx("boss_phase", global_position)
	var act := StringName(str(intent.get("action", "")))
	if bool(intent.get("marker_fresh", false)):
		_ring_anchor = _player_world_pos() if _target else global_position
		_sfx("boss_telegraph", global_position)
		_show_ring(act)
	if bool(intent.get("telegraph", false)):
		_show_ring(act)
	if bool(intent.get("impact", false)):
		_hide_ring()
		_sfx("boss_slam", global_position)
		_Juice.request_hit_stop(0.08, get_tree())
		_Juice.request_shake(0.85)
		_resolve_special(act, int(intent.get("summon", 0)))
	elif int(intent.get("summon", 0)) > 0 and not bool(intent.get("impact", false)):
		_summon_mites(int(intent.get("summon", 0)))


func _show_ring(act: StringName) -> void:
	_ensure_ring()
	if _ring == null:
		return
	var radius := 2.4
	if act == &"burst":
		radius = 4.6
	elif act == &"charge":
		radius = 1.8
	var vs: float = WorldSettings.get_active().voxel_scale
	_ring.global_position = Vector3(_ring_anchor.x, global_position.y + 0.08, _ring_anchor.z)
	_ring.scale = Vector3(radius * vs, 1.0, radius * vs)
	_ring.visible = true
	if _ring.material_override is StandardMaterial3D:
		var mat := _ring.material_override as StandardMaterial3D
		mat.albedo_color = Color(1.0, 0.45, 0.15, 0.55) if act == &"burst" else Color(1.0, 0.22, 0.16, 0.48)


func _hide_ring() -> void:
	if _ring:
		_ring.visible = false


func _resolve_special(act: StringName, summon: int) -> void:
	var vs: float = WorldSettings.get_active().voxel_scale
	if act == &"charge":
		var dir := _ring_anchor - global_position
		var lunged := _EntityNavigation.knockback_step(
			global_position, dir, minf(dir.length(), 6.0 * vs), _world, _chunk_manager, _crystal
		)
		global_position = lunged
		_notify_spatial_moved()
	if _target and _target.has_method("take_damage"):
		var there := _player_world_pos()
		var reach: float = 2.4 * vs
		if act == &"burst":
			reach = 4.6 * vs
		elif act == &"charge":
			reach = 1.8 * vs
		var flat := Vector2(there.x - _ring_anchor.x, there.z - _ring_anchor.z).length()
		if act == &"charge":
			flat = Vector2(there.x - global_position.x, there.z - global_position.z).length()
		if flat <= reach:
			var mult := 1.35 if act == &"burst" else 1.0
			var src := _ring_anchor if act == &"burst" else global_position
			_damage_player(contact_damage * mult, &"boss", src)
	if summon > 0:
		_summon_mites(summon)


func _summon_mites(count: int) -> void:
	if count <= 0 or not is_inside_tree():
		return
	var spawner = get_tree().get_first_node_in_group("crystal_enemy_spawner")
	if spawner == null or not spawner.has_method("spawn_enemy_at_column"):
		return
	var cell := _EntityNavigation.column_pos(global_position)
	var n := mini(count, 3)
	for i in n:
		spawner.spawn_enemy_at_column(&"crystal_mite", cell.x + i - 1, cell.y + 2, cell)


func _detonate() -> void:
	var target_pos := _target_column_pos()
	if _target and _target.has_method("take_damage"):
		var dist := global_position.distance_to(target_pos)
		if dist <= detonate_radius + 0.5:
			_damage_player(contact_damage, &"", global_position)
	detonated.emit(contact_damage)
	_sfx("enemy_death", global_position)
	_release_death_visual()
	queue_free()


func _active_visual() -> Node3D:
	if _part_rig and is_instance_valid(_part_rig) and _part_rig.visible:
		return _part_rig
	if _voxel_prop and is_instance_valid(_voxel_prop) and _voxel_prop.visible:
		return _voxel_prop
	if _sprite and is_instance_valid(_sprite) and _sprite.visible:
		return _sprite
	if _mesh and is_instance_valid(_mesh) and _mesh.visible:
		return _mesh
	return null


func _clear_flash() -> void:
	var vis := _active_visual()
	if vis:
		_Juice.set_flash(vis, 0.0)


func _apply_walk_bob(delta: float, moving: bool, attacking: bool = false) -> void:
	if attacking:
		_attack_hold = 0.42
	if _attack_hold > 0.0:
		locomotion_pose = "attack"
		_attack_hold = maxf(_attack_hold - delta, 0.0)
	elif moving:
		locomotion_pose = "walk"
	else:
		locomotion_pose = "idle"
	var rate := 2.2
	if locomotion_pose == "walk":
		rate = 9.0
	elif locomotion_pose == "attack":
		rate = 8.0
	_bob_phase += delta * rate
	if _part_rig and is_instance_valid(_part_rig) and _part_rig.visible and _VoxelCreature.uses_rig(_visual_lookup_id()):
		_VoxelCreature.play(_part_rig, locomotion_pose, _bob_phase)
		return
	var vis := _active_visual()
	if vis == null or vis != _voxel_prop:
		return
	if _bob_ready:
		vis.position.y = _bob_base_y
		vis.scale = _bob_base_scale
		_bob_ready = false
	_creature_pose.apply(vis, locomotion_pose, _bob_phase)


func _release_death_visual() -> void:
	if not is_inside_tree():
		return
	var vis := _active_visual()
	if vis == null:
		return
	var vfx := get_tree().get_first_node_in_group("combat_visual_feedback")
	if vfx and vfx.has_method("adopt_death_visual"):
		vfx.adopt_death_visual(vis)


func _sfx(id: String, at: Variant = null) -> void:
	if not is_inside_tree():
		return
	if not is_instance_valid(_audio):
		_audio = get_node_or_null("/root/AudioManager")
	if _audio == null or not _audio.has_method("play_sfx"):
		return
	if at is Vector3:
		_audio.play_sfx(id, at)
	else:
		_audio.play_sfx(id)


func _max_neighbor_crystal_depth(cell: Vector2i) -> float:
	if _crystal == null:
		return 0.0
	var best := _crystal.get_depth_at(cell.x, cell.y)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			best = maxf(best, _crystal.get_depth_at(cell.x + dx, cell.y + dz))
	return best