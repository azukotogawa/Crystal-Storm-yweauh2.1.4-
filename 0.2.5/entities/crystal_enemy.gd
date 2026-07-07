class_name CrystalEnemy
extends Node3D

const _EntityBrain = preload("res://entities/entity_brain.gd")
const _EntityBrainRegistry = preload("res://entities/entity_brain_registry.gd")
const _EntityNavigation = preload("res://entities/entity_navigation.gd")
const _EnemySpawnDef = preload("res://config/enemy_spawn_def.gd")
const _CombatLog = preload("res://systems/combat_log.gd")

signal detonated(damage: float)
signal attacked_player(damage: float)
signal combat_damaged(amount: float, remaining_health: float, source: StringName)

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
var health: float = 24.0
var _age: float = 0.0
var _mesh: MeshInstance3D
var _patrol_anchor: Vector2i = Vector2i.ZERO
var _last_damage_source: StringName = &""
var _hit_flash_timer: float = 0.0
var _base_tint: Color = Color(0.72, 0.2, 0.95)
var _mesh_radius: float = 0.28


func _ready() -> void:
	add_to_group("crystal_enemy")
	_bind_scene()


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
		_setup_mesh(spawn_config.tint, spawn_config.mesh_radius, spawn_config.mesh_height)
	else:
		_setup_mesh(Color(0.72, 0.2, 0.95))

	health = max_health


func _setup_mesh(tint: Color, radius: float = 0.28, height: float = 0.7) -> void:
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		add_child(_mesh)
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	_mesh.mesh = mesh
	_mesh.position.y = height * 0.55
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint * 0.55
	_mesh.material_override = mat
	_base_tint = tint
	_mesh_radius = radius


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
	if spawn_def:
		return spawn_def.hit_radius
	return maxf(_mesh_radius * 1.2, 0.35)


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


func _physics_process(delta: float) -> void:
	if _hit_flash_timer > 0.0:
		_hit_flash_timer = maxf(_hit_flash_timer - delta, 0.0)
		if _hit_flash_timer <= 0.0 and _mesh and _mesh.material_override is StandardMaterial3D:
			(_mesh.material_override as StandardMaterial3D).albedo_color = _base_tint

	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	if _target == null or not is_instance_valid(_target) or brain == null:
		return

	var self_cell := _EntityNavigation.column_pos(global_position)
	var player_cell := self_cell
	player_cell = _EntityNavigation.column_pos(_target_column_pos())

	var target_pos := _target_column_pos()
	if brain.should_detonate(global_position, target_pos):
		_detonate()
		return

	var crystal_sim = _crystal.get_fluid_sim() if _crystal and _crystal.has_method("get_fluid_sim") else null
	var nearby_depth := _max_neighbor_crystal_depth(self_cell)
	var target_cell := brain.tick(delta, self_cell, player_cell, crystal_sim, nearby_depth)

	global_position = _EntityNavigation.step_toward_cell(
		global_position,
		target_cell,
		move_speed,
		delta,
		_world,
		_chunk_manager,
		_crystal
	)

	if brain.wants_attack(self_cell, player_cell):
		if global_position.distance_to(target_pos) <= 1.8:
			if _target.has_method("take_damage"):
				_target.take_damage(contact_damage)
			attacked_player.emit(contact_damage)


func take_damage(amount: float, source: StringName = &"") -> void:
	if amount <= 0.0:
		return
	_last_damage_source = source
	health = maxf(health - amount, 0.0)
	_flash_hit()
	combat_damaged.emit(amount, health, source)
	var label := spawn_def.display_name if spawn_def else str(enemy_id)
	_CombatLog.push("%s hit %.1f → %.0f HP" % [label, amount, health])
	if health <= 0.0:
		_on_killed()


func _flash_hit() -> void:
	_hit_flash_timer = 0.14
	if _mesh and _mesh.material_override is StandardMaterial3D:
		(_mesh.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.55, 0.95)


func _on_killed() -> void:
	var label := spawn_def.display_name if spawn_def else str(enemy_id)
	_CombatLog.push("%s killed" % label)
	queue_free()


func _detonate() -> void:
	var target_pos := _target_column_pos()
	if _target and _target.has_method("take_damage"):
		var dist := global_position.distance_to(target_pos)
		if dist <= detonate_radius + 0.5:
			_target.take_damage(contact_damage)
	detonated.emit(contact_damage)
	queue_free()


func _max_neighbor_crystal_depth(cell: Vector2i) -> float:
	if _crystal == null:
		return 0.0
	var best := _crystal.get_depth_at(cell.x, cell.y)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			best = maxf(best, _crystal.get_depth_at(cell.x + dx, cell.y + dz))
	return best