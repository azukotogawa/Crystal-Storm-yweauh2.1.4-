class_name WorldEntity
extends Node3D

const _EntityBrain = preload("res://entities/entity_brain.gd")
const _EntityBrainConfig = preload("res://config/entity_brain_config.gd")
const _EntityNavigation = preload("res://entities/entity_navigation.gd")
const _CombatLog = preload("res://systems/combat_log.gd")
const _GameVisualRegistry = preload("res://systems/game_visual_registry.gd")
const _WorldVisualCoords = preload("res://helpers/world_visual_coords.gd")
const _VoxelPropBuilder = preload("res://helpers/voxel_prop_builder.gd")
const _CrystalCorruption = preload("res://crystal/crystal_corruption.gd")
const _EntityBrainRegistry = preload("res://entities/entity_brain_registry.gd")
const _CombatRewards = preload("res://helpers/combat_rewards.gd")
const _Juice = preload("res://systems/juice.gd")
const _PlayerSettings = preload("res://systems/player_settings.gd")
const _ContactShadow = preload("res://helpers/contact_shadow.gd")
const _CreaturePose = preload("res://entities/creature_pose.gd")
const _VoxelCreature = preload("res://helpers/voxel_creature_builder.gd")
const _VoxelModel = preload("res://helpers/voxel_model_builder.gd")
const _StructureIntegrity = preload("res://helpers/structure_integrity.gd")

signal died(entity: WorldEntity, world_pos: Vector2i)
signal attacked_player(damage: float)
signal combat_damaged(amount: float, remaining_health: float, source: StringName)

@export var entity_kind: StringName = &"rabbit"

var brain: _EntityBrain
var config: _EntityBrainConfig
@export_range(0.0, 1.0, 0.05) var knock_resist: float = 0.0
var health: float = 20.0
var home_cell: Vector2i = Vector2i.ZERO

var _world: InfiniteNoiseWorld
var _chunk_manager: ChunkManager
var _crystal: CrystalManager
var _player: Node3D
var _spatial: Node = null
var _entity_mgr: Node = null
var _profiler: Node = null
var _profiler_bound: bool = false
var _mesh: MeshInstance3D
var _sprite: Sprite3D
var _voxel_prop: Node3D
var _part_rig: Node3D
var _bob_phase: float = 0.0
var _bob_ready: bool = false
var locomotion_pose: String = "idle"
var _attack_hold: float = 0.0
var _visual_frame: int = -1
var _creature_pose: RefCounted = _CreaturePose.new()
var _bob_base_y: float = 0.0
var _bob_base_scale: Vector3 = Vector3.ONE
var _audio: Node
var _dead: bool = false
var _last_damage_source: StringName = &""
var _hit_flash_timer: float = 0.0
var _hurt_player: float = 0.0
const HURT_LOCK := 0.22
var _knock_dir := Vector3.ZERO
var _knock_left := 0.0
var _base_tint: Color = Color(0.72, 0.72, 0.68)
var _convert_elapsed: float = 0.0
var _convert_from_tint: Color = Color(0.72, 0.72, 0.68)
var _convert_started: bool = false
var _placed: bool = false


func _ready() -> void:
	add_to_group("world_entity")
	_bind_scene()
	_hook_visual_registry()
	_ContactShadow.attach(self, 0.06, 1.2)


func setup(
	brain_config: _EntityBrainConfig,
	spawn_cell: Vector2i,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	crystal_manager: CrystalManager,
	defend_center: Vector2i = Vector2i.ZERO,
	tint: Color = Color(0.72, 0.72, 0.68)
) -> void:
	config = brain_config
	entity_kind = brain_config.id
	health = brain_config.max_health
	home_cell = spawn_cell
	_world = world
	_chunk_manager = chunk_manager
	_crystal = crystal_manager
	brain = _EntityBrain.new(brain_config)
	brain.reset_at(spawn_cell, defend_center, spawn_cell)
	brain.bind_identity(brain_config.id, int(world.world_seed) if world != null else 1)
	_base_tint = tint
	if not is_inside_tree():
		push_warning("WorldEntity.setup called before add_child — deferring placement")
		call_deferred("_finish_spawn_placement", spawn_cell, tint)
		return
	_finish_spawn_placement(spawn_cell, tint)


func _finish_spawn_placement(spawn_cell: Vector2i, tint: Color) -> void:
	if not is_inside_tree():
		return
	global_position = _column_world_position(spawn_cell)
	_placed = true
	_ensure_visual(tint)


func _bind_scene() -> void:
	if _world == null:
		_world = get_tree().get_first_node_in_group("world")
	if _chunk_manager == null:
		_chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	if _crystal == null:
		_crystal = get_tree().get_first_node_in_group("crystal_manager")
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")


func refresh_visual() -> void:
	if _dead:
		return
	_bind_scene()
	if brain != null and not _placed:
		global_position = _column_world_position(home_cell)
		_placed = true
	_ensure_visual(_base_tint)


func _column_world_position(cell: Vector2i) -> Vector3:
	var col_x := float(cell.x) + 0.5
	var col_z := float(cell.y) + 0.5
	var registry = get_tree().get_first_node_in_group("game_visual_registry")
	if registry != null and registry.has_method("column_sprite_position") \
			and _world != null and _chunk_manager != null:
		var use_voxel: bool = bool(registry.get("entity_voxel_models_enabled"))
		var height_off: float = 0.0
		if not use_voxel:
			var tex: Texture2D = _resolve_entity_texture(registry)
			if tex != null and registry.has_method("entity_anchor_height_offset"):
				height_off = registry.entity_anchor_height_offset(tex)
			elif tex != null and registry.has_method("sprite_half_height"):
				height_off = registry.sprite_half_height(tex)
		return registry.column_sprite_position(_world, _chunk_manager, _crystal, col_x, col_z, height_off)
	var spawn_pos := _WorldVisualCoords.column_to_world_pos(col_x, 0.0, col_z)
	return _EntityNavigation.snap_to_ground(spawn_pos, _world, _chunk_manager, _crystal)


func _ensure_visual(tint: Color) -> void:
	_base_tint = tint
	if _VoxelCreature.uses_rig(entity_kind) and _ensure_part_rig(tint):
		return
	if _VoxelModel.USE_GRID_PARTS and _ensure_grid_model(tint):
		return
	_drop_part_rig()
	var registry = get_tree().get_first_node_in_group("game_visual_registry")
	if registry != null and bool(registry.get("entity_voxel_models_enabled")):
		_ensure_voxel_model(tint)
		return
	var use_sprite: bool = registry != null and bool(registry.entity_sprites_enabled)
	var tex: Texture2D = _resolve_entity_texture(registry) if use_sprite else null
	if use_sprite and tex != null:
		_ensure_sprite(registry, tex, tint)
	else:
		_ensure_mesh(tint)


func _ensure_grid_model(_tint: Color) -> bool:
	var parts: Array = _VoxelModel.parts_for(entity_kind)
	if parts.is_empty():
		return false
	var cube := 1.0
	if parts[0] is Dictionary and (parts[0] as Dictionary).has("cube"):
		cube = float((parts[0] as Dictionary)["cube"])
	var built: Node3D = _VoxelModel.build_rig(parts, _VoxelModel.palette_for(entity_kind), cube)
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


func _ensure_part_rig(_tint: Color) -> bool:
	if not _VoxelCreature.uses_rig(entity_kind):
		return false
	var built: Node3D = _VoxelCreature.build(entity_kind)
	if built == null:
		return false
	if _sprite:
		_sprite.visible = false
	if _mesh:
		_mesh.visible = false
	_free_voxel_prop()
	_drop_part_rig()
	_part_rig = built
	add_child(_part_rig)
	return true


func repaint_creature() -> void:
	if _part_rig and is_instance_valid(_part_rig) and _VoxelCreature.uses_rig(entity_kind):
		_VoxelCreature.repaint(_part_rig)


func _free_voxel_prop() -> void:
	if _voxel_prop and is_instance_valid(_voxel_prop):
		_voxel_prop.queue_free()
	_voxel_prop = null


func _drop_part_rig() -> void:
	if _part_rig and is_instance_valid(_part_rig):
		if _part_rig.get_parent() == self:
			remove_child(_part_rig)
		_part_rig.free()
	_part_rig = null


func _hook_visual_registry() -> void:
	var registry = get_tree().get_first_node_in_group("game_visual_registry")
	if registry == null:
		return
	if registry.has_method("is_ready") and registry.is_ready():
		call_deferred("refresh_visual")
		return
	if registry.has_signal("visuals_ready") and not registry.visuals_ready.is_connected(_on_registry_visuals_ready):
		registry.visuals_ready.connect(_on_registry_visuals_ready, CONNECT_ONE_SHOT)
	if registry.has_signal("post_bootstrap_refreshed") \
			and not registry.post_bootstrap_refreshed.is_connected(_on_registry_visuals_ready):
		registry.post_bootstrap_refreshed.connect(_on_registry_visuals_ready, CONNECT_ONE_SHOT)


func _on_registry_visuals_ready() -> void:
	refresh_visual()


func _resolve_entity_texture(registry) -> Texture2D:
	if registry == null:
		return null
	if registry.has_method("get_sprite_texture"):
		return registry.get_sprite_texture(str(entity_kind))
	if registry.has_method("get_entity_texture"):
		return registry.get_entity_texture(entity_kind)
	return null


func _ensure_voxel_model(tint: Color) -> void:
	if _sprite:
		_sprite.visible = false
	if _mesh:
		_mesh.visible = false
	if _voxel_prop == null or not is_instance_valid(_voxel_prop):
		if _voxel_prop:
			_voxel_prop.queue_free()
		_voxel_prop = _VoxelPropBuilder.build_entity(entity_kind, tint)
		_voxel_prop.name = "VoxelProp"
		add_child(_voxel_prop)
	else:
		_VoxelPropBuilder.apply_tint(_voxel_prop, tint)
	_voxel_prop.visible = true


func _ensure_sprite(registry, tex: Texture2D, tint: Color) -> void:
	if _voxel_prop:
		_voxel_prop.visible = false
	if _sprite == null:
		_sprite = Sprite3D.new()
		_sprite.name = "Sprite3D"
		add_child(_sprite)
	_sprite.position.y = 0.0
	if _mesh:
		_mesh.visible = false
	_sprite.visible = true
	if registry.has_method("apply_to_sprite3d"):
		registry.apply_to_sprite3d(_sprite, tex, tint)
	elif registry.has_method("configure_sprite3d"):
		registry.configure_sprite3d(_sprite, tex, tint)
	else:
		_sprite.texture = tex
		_sprite.modulate = tint


func _ensure_mesh(tint: Color) -> void:
	if _voxel_prop:
		_voxel_prop.visible = false
	if _sprite:
		_sprite.visible = false
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		_mesh.name = "MeshInstance3D"
		var mesh := CapsuleMesh.new()
		var ws = WorldSettings.get_active()
		mesh.radius = ws.small_creature_radius()
		mesh.height = ws.small_creature_height()
		_mesh.mesh = mesh
		_mesh.position.y = mesh.height * 0.5
		add_child(_mesh)
	_mesh.visible = true
	if _mesh.material_override == null:
		_mesh.material_override = StandardMaterial3D.new()
	if _mesh.material_override is StandardMaterial3D:
		(_mesh.material_override as StandardMaterial3D).albedo_color = tint


func get_combat_center() -> Vector3:
	var center := global_position
	if _part_rig and is_instance_valid(_part_rig) and _part_rig.visible:
		var rig_h := float(_part_rig.get_meta("model_height", 0.0))
		if rig_h > 0.01:
			center.y += rig_h * 0.42
			return center
	if _voxel_prop and is_instance_valid(_voxel_prop):
		var h := _VoxelPropBuilder.model_height(_voxel_prop)
		if h > 0.01:
			center.y += h * 0.42
	elif _mesh and is_instance_valid(_mesh):
		center.y += WorldSettings.get_active().small_creature_height() * 0.5
	return center


func get_combat_radius() -> float:
	## Brain hit_radius is authored at voxel_scale 2. It tracks the world knob.
	var authored := config.hit_radius if config else 0.35
	return authored * (WorldSettings.get_active().voxel_scale / 2.0)


func get_combat_defense() -> float:
	return config.defense if config else 0.0


func is_combat_alive() -> bool:
	return not _dead and health > 0.0


func _profiler_node() -> Node:
	if _profiler_bound:
		return _profiler
	_profiler_bound = true
	_profiler = get_node_or_null("/root/PerfProfiler")
	return _profiler


func _entity_manager() -> Node:
	if _entity_mgr != null and is_instance_valid(_entity_mgr):
		return _entity_mgr
	if not is_inside_tree():
		return null
	var found := get_tree().get_first_node_in_group("entity_manager")
	if found:
		_entity_mgr = found
	return found


func _physics_process(delta: float) -> void:
	var profiler := _profiler_node()
	if profiler and profiler.has_method("begin"):
		profiler.begin("entity_physics")
	var entity_mgr := _entity_manager()
	if entity_mgr and int(entity_mgr.get("physics_skip_frames")) > 0:
		if Engine.get_physics_frames() % (int(entity_mgr.physics_skip_frames) + 1) != 0:
			if profiler and profiler.has_method("end"):
				profiler.end("entity_physics")
			return

	if _hit_flash_timer > 0.0:
		_hit_flash_timer = maxf(_hit_flash_timer - delta, 0.0)
		if _hit_flash_timer <= 0.0:
			_reset_hit_tint()
	if _hurt_player > 0.0:
		_hurt_player = maxf(_hurt_player - delta, 0.0)

	if _dead or brain == null or config == null:
		if profiler and profiler.has_method("end"):
			profiler.end("entity_physics")
		return
	_bind_scene()

	var self_cell := _EntityNavigation.column_pos(global_position)
	if _chunk_manager and _chunk_manager.has_method("is_world_cell_loaded"):
		if not _chunk_manager.is_world_cell_loaded(self_cell.x, self_cell.y):
			if profiler and profiler.has_method("end"):
				profiler.end("entity_physics")
			return
	var player_cell := self_cell
	if _player:
		player_cell = _EntityNavigation.column_pos(
			_player.global_position if not _player.has_method("get_voxel_position")
			else _player.get_voxel_position()
		)

	var crystal_sim = _crystal.get_fluid_sim() if _crystal and _crystal.has_method("get_fluid_sim") else null
	var nearby_depth := _max_neighbor_crystal_depth(self_cell)
	var min_depth := 0.04
	if _crystal and _crystal.sim_config:
		min_depth = _crystal.sim_config.min_depth
	advance_crystal_conversion(delta, nearby_depth >= min_depth)
	var target_cell := brain.tick(delta, self_cell, player_cell, crystal_sim, nearby_depth)
	if _chunk_manager and _chunk_manager.has_method("is_world_cell_loaded"):
		if not _chunk_manager.is_world_cell_loaded(target_cell.x, target_cell.y):
			target_cell = self_cell

	if _knock_left > 0.0:
		var step := minf(_knock_left, maxf(config.move_speed, 6.0) * delta * 2.4)
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
		config.move_speed,
		delta,
		_world,
		_chunk_manager,
		_crystal
	)
	_notify_spatial_moved()
	if profiler and profiler.has_method("record_us"):
		profiler.record_us("entity_navigation", Time.get_ticks_usec() - nav_t0)

	var did_attack := false
	var aim_cell := _aim_cell()
	if _player and brain.wants_attack(self_cell, aim_cell):
		var player_pos := _aim_world()
		if global_position.distance_to(player_pos) <= WorldSettings.get_active().creature_contact_range():
			did_attack = true
			if _player.has_method("set_damage_origin"):
				_player.set_damage_origin(global_position)
			if _player.has_method("take_damage"):
				_player.take_damage(config.contact_damage)
			attacked_player.emit(config.contact_damage)
	_StructureIntegrity.chip_enemy(self_cell, config.contact_damage, did_attack, brain, self)
	_apply_walk_bob(delta, target_cell != self_cell, did_attack)
	if profiler and profiler.has_method("end"):
		profiler.end("entity_physics")


func advance_crystal_conversion(delta: float, in_crystal: bool) -> void:
	if _dead or config == null:
		return
	var hostile := _CrystalCorruption.hostile_for_animal(str(entity_kind))
	if hostile == "":
		return
	if not in_crystal:
		_convert_elapsed = maxf(_convert_elapsed - delta, 0.0)
		return
	var seconds := 3.5
	if _crystal != null and _crystal.sim_config != null:
		seconds = maxf(float(_crystal.sim_config.animal_convert_seconds), 0.2)
	if not _convert_started:
		_convert_started = true
		_convert_from_tint = _base_tint
	_convert_elapsed += delta
	var t := clampf(_convert_elapsed / seconds, 0.0, 1.0)
	var crystal_tint := Color(0.62, 0.28, 0.95, 1.0)
	_base_tint = _convert_from_tint.lerp(crystal_tint, t)
	if _hit_flash_timer <= 0.0:
		_paint_tint(_base_tint)
	if t < 1.0:
		return
	_EntityBrainRegistry.ensure_builtins()
	var next = _EntityBrainRegistry.get_def(StringName(hostile))
	if next == null:
		return
	var cell := brain.home_pos if brain else home_cell
	config = next
	entity_kind = next.id
	health = next.max_health
	brain = _EntityBrain.new(next)
	brain.reset_at(cell, cell, cell)
	brain.bind_identity(next.id, int(_world.world_seed) if _world != null else 1)
	_base_tint = crystal_tint
	_convert_elapsed = 0.0
	_convert_started = false
	if _voxel_prop and is_instance_valid(_voxel_prop):
		_voxel_prop.queue_free()
		_voxel_prop = null
	if _sprite and is_instance_valid(_sprite):
		_sprite.queue_free()
		_sprite = null
	if is_inside_tree():
		_ensure_visual(crystal_tint)


func export_save_state() -> Dictionary:
	var tint := _base_tint
	if _mesh and _mesh.material_override is StandardMaterial3D:
		tint = (_mesh.material_override as StandardMaterial3D).albedo_color
	return {
		"brain_id": str(entity_kind),
		"world_pos": [home_cell.x, home_cell.y],
		"defend_center": [brain.defend_center.x, brain.defend_center.y] if brain else [home_cell.x, home_cell.y],
		"health": health,
		"x": global_position.x,
		"y": global_position.y,
		"z": global_position.z,
		"tint": [tint.r, tint.g, tint.b, tint.a],
	}


func take_damage(amount: float, source: StringName = &"") -> void:
	if _dead or amount <= 0.0 or _hurt_player > 0.0:
		return
	_last_damage_source = source
	_hurt_player = HURT_LOCK
	health = maxf(health - amount, 0.0)
	_flash_hit()
	combat_damaged.emit(amount, health, source)
	var label := config.display_name if config else str(entity_kind)
	_CombatLog.push("%s hit %.1f → %.0f HP" % [label, amount, health])
	if health <= 0.0:
		_die()
	else:
		_sfx("enemy_hurt", global_position)


func apply_knockback(dir: Vector3, distance: float) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001 or distance <= 0.0:
		return
	_knock_dir = flat.normalized()
	_knock_left = distance


func _flash_hit() -> void:
	_hit_flash_timer = 0.14
	if not _PlayerSettings.flash_effects_enabled:
		return
	var vis := _active_visual()
	if vis:
		_Juice.set_flash(vis, 1.0)


func _paint_tint(color: Color) -> void:
	if _voxel_prop and is_instance_valid(_voxel_prop) and _voxel_prop.visible:
		for child in _voxel_prop.get_children():
			if child is MeshInstance3D and (child as MeshInstance3D).material_override is StandardMaterial3D:
				((child as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = color
		return
	if _sprite and is_instance_valid(_sprite) and _sprite.visible:
		_sprite.modulate = color
		return
	if _mesh and is_instance_valid(_mesh) and _mesh.material_override is StandardMaterial3D:
		(_mesh.material_override as StandardMaterial3D).albedo_color = color


func _reset_hit_tint() -> void:
	var vis := _active_visual()
	if vis:
		_Juice.set_flash(vis, 0.0)


func _spatial_service() -> Node:
	if _spatial != null and is_instance_valid(_spatial):
		return _spatial
	if not is_inside_tree():
		return null
	_spatial = get_tree().get_first_node_in_group("spatial_query_service")
	return _spatial


func _notify_spatial_moved() -> void:
	var svc := _spatial_service()
	if svc and svc.has_method("notify_moved"):
		svc.notify_moved(self)


func _die() -> void:
	if _dead:
		return
	_dead = true
	var cell := _EntityNavigation.column_pos(global_position)
	var player_killed := _last_damage_source != &""
	if config.feeds_crystal_on_death and not player_killed and _crystal and _crystal.has_method("grant_feed_power"):
		_crystal.grant_feed_power(config.crystal_feed_power)
	if _crystal and _crystal.has_method("get_evolution"):
		var evo = _crystal.get_evolution()
		if evo and not player_killed:
			evo.record_absorption(&"animal")
	_CombatLog.push("%s died" % (config.display_name if config else str(entity_kind)))
	died.emit(self, cell)
	if player_killed and is_inside_tree():
		var label := config.display_name if config else str(entity_kind)
		_CombatRewards.grant_player_kill(get_tree(), entity_kind, label)
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


## Player voxel_position is column X/Z. Do not run it through column_pos.
func _aim_cell() -> Vector2i:
	if _player != null and is_instance_valid(_player) and _player.has_method("get_voxel_position"):
		var v: Vector3 = _player.get_voxel_position()
		return Vector2i(floori(v.x), floori(v.z))
	if _player != null and is_instance_valid(_player):
		return _EntityNavigation.column_pos(_player.global_position)
	return _EntityNavigation.column_pos(global_position)


func _aim_world() -> Vector3:
	if _player != null and is_instance_valid(_player) and _player.has_method("get_voxel_position"):
		var v: Vector3 = _player.get_voxel_position()
		var ws = WorldSettings.get_active()
		return Vector3(ws.column_to_world(v.x), v.y, ws.column_to_world(v.z))
	if _player != null and is_instance_valid(_player):
		return _player.global_position
	return global_position


func _process(delta: float) -> void:
	if _dead:
		return
	if _visual_frame == Engine.get_process_frames():
		return
	_apply_walk_bob(delta, false, false)


func _apply_walk_bob(delta: float, moving: bool, attacking: bool = false) -> void:
	_visual_frame = Engine.get_process_frames()
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
	if _part_rig and is_instance_valid(_part_rig) and _part_rig.visible and _VoxelCreature.uses_rig(entity_kind):
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