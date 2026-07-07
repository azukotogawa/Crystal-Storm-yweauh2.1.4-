class_name CrystalEnemy
extends Node3D

const _StatIds = preload("res://stats/stat_ids.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

@export var move_speed: float = 10.0
@export var contact_damage: float = 22.0
@export var detonate_radius: float = 2.8
@export var lifetime: float = 45.0

var enemy_id: StringName = &"crystal_mite"
var _target: Node3D
var _age: float = 0.0
var _mesh: MeshInstance3D


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.28
	mesh.height = 0.7
	_mesh.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.2, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.1, 0.8)
	_mesh.position.y = 0.4
	add_child(_mesh)
	add_to_group("crystal_enemy")


func setup(id: StringName, target: Node3D, tint: Color = Color(0.72, 0.2, 0.95)) -> void:
	enemy_id = id
	_target = target
	if _mesh:
		var mat := _mesh.material_override as StandardMaterial3D
		if mat == null:
			mat = StandardMaterial3D.new()
			_mesh.material_override = mat
		mat.albedo_color = tint
		mat.emission = tint * 0.6


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	if _target == null or not is_instance_valid(_target):
		return

	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	if dist <= detonate_radius:
		_detonate()
		return
	if dist > 0.05:
		global_position += to_target.normalized() * move_speed * delta
		var ground_y := global_position.y
		if get_tree().get_first_node_in_group("world"):
			var w = get_tree().get_first_node_in_group("world")
			var ws = _WorldSettings.get_active()
			var wx: float = ws.world_to_column(global_position.x)
			var wz: float = ws.world_to_column(global_position.z)
			ground_y = TerrainRamps.walkable_height(w, wx, wz)
		global_position.y = ground_y


func _detonate() -> void:
	if _target and _target.has_method("take_damage"):
		var dist := global_position.distance_to(_target.global_position)
		if dist <= detonate_radius + 0.5:
			_target.take_damage(contact_damage)
	queue_free()