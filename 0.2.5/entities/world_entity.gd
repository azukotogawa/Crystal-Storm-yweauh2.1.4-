class_name WorldEntity
extends Node3D

const _EntityBrain = preload("res://entities/entity_brain.gd")
const _EntityBrainConfig = preload("res://config/entity_brain_config.gd")
const _EntityNavigation = preload("res://entities/entity_navigation.gd")
const _CombatLog = preload("res://systems/combat_log.gd")

signal died(entity: WorldEntity, world_pos: Vector2i)
signal attacked_player(damage: float)
signal combat_damaged(amount: float, remaining_health: float, source: StringName)

@export var entity_kind: StringName = &"rabbit"

var brain: _EntityBrain
var config: _EntityBrainConfig
var health: float = 20.0
var home_cell: Vector2i = Vector2i.ZERO

var _world: InfiniteNoiseWorld
var _chunk_manager: ChunkManager
var _crystal: CrystalManager
var _player: Node3D
var _mesh: MeshInstance3D
var _dead: bool = false
var _last_damage_source: StringName = &""
var _hit_flash_timer: float = 0.0
var _base_tint: Color = Color(0.72, 0.72, 0.68)


func _ready() -> void:
	add_to_group("world_entity")
	_bind_scene()


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
	_base_tint = tint
	_ensure_mesh(tint)
	global_position = _EntityNavigation.snap_to_ground(
		Vector3(float(spawn_cell.x) + 0.5, 0.0, float(spawn_cell.y) + 0.5),
		_world, _chunk_manager, _crystal
	)


func _bind_scene() -> void:
	if _world == null:
		_world = get_tree().get_first_node_in_group("world")
	if _chunk_manager == null:
		_chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	if _crystal == null:
		_crystal = get_tree().get_first_node_in_group("crystal_manager")
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")


func _ensure_mesh(tint: Color) -> void:
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.22
		mesh.height = 0.55
		_mesh.mesh = mesh
		_mesh.position.y = 0.35
		add_child(_mesh)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	_mesh.material_override = mat


func get_combat_center() -> Vector3:
	return global_position


func get_combat_radius() -> float:
	return config.hit_radius if config else 0.35


func get_combat_defense() -> float:
	return config.defense if config else 0.0


func is_combat_alive() -> bool:
	return not _dead and health > 0.0


func _physics_process(delta: float) -> void:
	if _hit_flash_timer > 0.0:
		_hit_flash_timer = maxf(_hit_flash_timer - delta, 0.0)
		if _hit_flash_timer <= 0.0 and _mesh and _mesh.material_override is StandardMaterial3D:
			(_mesh.material_override as StandardMaterial3D).albedo_color = _base_tint

	if _dead or brain == null or config == null:
		return
	_bind_scene()

	var self_cell := _EntityNavigation.column_pos(global_position)
	var player_cell := self_cell
	if _player:
		player_cell = _EntityNavigation.column_pos(
			_player.global_position if not _player.has_method("get_voxel_position")
			else _player.get_voxel_position()
		)

	var crystal_sim = _crystal.get_fluid_sim() if _crystal and _crystal.has_method("get_fluid_sim") else null
	var nearby_depth := _max_neighbor_crystal_depth(self_cell)
	var target_cell := brain.tick(delta, self_cell, player_cell, crystal_sim, nearby_depth)

	global_position = _EntityNavigation.step_toward_cell(
		global_position,
		target_cell,
		config.move_speed,
		delta,
		_world,
		_chunk_manager,
		_crystal
	)

	if _player and brain.wants_attack(self_cell, player_cell):
		var player_pos: Vector3 = (
			_player.get_voxel_position() if _player.has_method("get_voxel_position")
			else _player.global_position
		)
		if global_position.distance_to(player_pos) <= 1.6:
			if _player.has_method("take_damage"):
				_player.take_damage(config.contact_damage)
			attacked_player.emit(config.contact_damage)


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
	if _dead or amount <= 0.0:
		return
	_last_damage_source = source
	health = maxf(health - amount, 0.0)
	_flash_hit()
	combat_damaged.emit(amount, health, source)
	var label := config.display_name if config else str(entity_kind)
	_CombatLog.push("%s hit %.1f → %.0f HP" % [label, amount, health])
	if health <= 0.0:
		_die()


func _flash_hit() -> void:
	_hit_flash_timer = 0.14
	if _mesh and _mesh.material_override is StandardMaterial3D:
		(_mesh.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.35, 0.35)


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
	queue_free()


func _max_neighbor_crystal_depth(cell: Vector2i) -> float:
	if _crystal == null:
		return 0.0
	var best := _crystal.get_depth_at(cell.x, cell.y)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			best = maxf(best, _crystal.get_depth_at(cell.x + dx, cell.y + dz))
	return best