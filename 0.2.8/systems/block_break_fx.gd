class_name BlockBreakFx
extends Node3D

const POP_SLOTS := 4
const POP_SEC := 0.16
const STAGES := 3

const _PlayerSettings = preload("res://systems/player_settings.gd")
const _VfxPool = preload("res://systems/vfx_pool.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

var _crack: MeshInstance3D
var _crack_mat: ShaderMaterial
var _pops: Array[MeshInstance3D] = []
var _pop_life: PackedFloat32Array = PackedFloat32Array()
var _pop_base: float = 1.0
var _pool: _VfxPool
var _stage: int = 0
var _breaks: int = 0
var _built: bool = false


func _ready() -> void:
	_ensure()
	set_process(false)


func has_live() -> bool:
	for life in _pop_life:
		if life > 0.0:
			return true
	return false


static func stage_for_progress(progress: float) -> int:
	if progress <= 0.001:
		return 0
	if progress < 0.34:
		return 1
	if progress < 0.67:
		return 2
	if progress < 1.0:
		return 3
	return 4


func current_stage() -> int:
	return _stage


func set_progress(world_pos: Vector3, progress: float, tint: Color = Color(0.45, 0.32, 0.2)) -> int:
	_ensure()
	var stage := stage_for_progress(progress)
	_stage = stage
	if not _PlayerSettings.crack_overlay_enabled or stage <= 0 or progress >= 1.0:
		_crack.visible = false
		return stage
	_crack.visible = true
	_crack.global_position = world_pos
	var shown := mini(stage, STAGES)
	_crack_mat.set_shader_parameter("stage", float(shown))
	_crack_mat.set_shader_parameter("progress", clampf(progress, 0.0, 1.0))
	_crack_mat.set_shader_parameter("crack_tint", Color(tint.r * 0.25, tint.g * 0.22, tint.b * 0.2, 0.9))
	return stage


func notify_break(world_pos: Vector3, tint: Color = Color(0.55, 0.42, 0.28)) -> bool:
	_ensure()
	_stage = 4
	_crack.visible = false
	var pool := _pool_node()
	var spawned: bool = pool.burst(_VfxPool.Kind.CHIP, world_pos, tint, 0.85)
	if spawned:
		_breaks += 1
	return spawned


func notify_place(world_pos: Vector3, tint: Color = Color(0.45, 0.78, 0.42)) -> void:
	_ensure()
	var slot := _take_pop()
	var mesh := _pops[slot]
	var mat := mesh.material_override as StandardMaterial3D
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.55)
	mesh.global_position = world_pos
	mesh.visible = true
	if _PlayerSettings.reduce_motion:
		mesh.scale = Vector3.ONE * _pop_base
		_pop_life[slot] = 0.04
		return
	mesh.scale = Vector3.ONE * (_pop_base * 0.25)
	_pop_life[slot] = POP_SEC


func tick(delta: float) -> void:
	for i in _pops.size():
		var life := _pop_life[i]
		if life <= 0.0:
			continue
		life = maxf(life - delta, 0.0)
		_pop_life[i] = life
		var mesh := _pops[i]
		if life <= 0.0:
			mesh.visible = false
			mesh.scale = Vector3.ONE * _pop_base
			continue
		if _PlayerSettings.reduce_motion:
			mesh.scale = Vector3.ONE * _pop_base
			continue
		var u := 1.0 - clampf(life / POP_SEC, 0.0, 1.0)
		var s: float
		if u < 0.62:
			s = lerpf(0.25, 1.12, u / 0.62)
		else:
			s = lerpf(1.12, 1.0, (u - 0.62) / 0.38)
		mesh.scale = Vector3.ONE * (_pop_base * s)


func pop_scale() -> float:
	var best := 0.0
	for mesh in _pops:
		if mesh.visible:
			best = maxf(best, mesh.scale.x)
	return best


func break_count() -> int:
	return _breaks


func emitter_count() -> int:
	if _pool == null:
		return 0
	return _pool.emitter_count()


func emitter_cap() -> int:
	return _pool_node().emitter_cap()


static func tint_for_tile(tile: int) -> Color:
	if tile >= _VoxelTypes.SNOW and tile <= _VoxelTypes.SNOW3:
		return Color(0.92, 0.94, 0.96)
	if tile >= _VoxelTypes.DESERT and tile <= _VoxelTypes.DESERT3:
		return Color(0.82, 0.72, 0.42)
	if tile == _VoxelTypes.DIRT or tile == _VoxelTypes.DIRT2:
		return Color(0.45, 0.32, 0.18)
	if tile == _VoxelTypes.STONE or tile == _VoxelTypes.STONE2 or tile == _VoxelTypes.CAVE_STONE:
		return Color(0.48, 0.49, 0.52)
	if tile >= _VoxelTypes.MOUNTAIN and tile <= _VoxelTypes.MOUNTAIN7:
		return Color(0.5, 0.5, 0.53)
	if tile == _VoxelTypes.CRYSTAL or tile == _VoxelTypes.CRYSTAL_VEIN:
		return Color(0.72, 0.4, 0.95)
	return Color(0.36, 0.55, 0.28)


static func tint_for_column(world, col: Vector3) -> Color:
	if world == null or not world.has_method("get_tile_type"):
		return Color(0.55, 0.42, 0.28)
	var tile := int(world.get_tile_type(col.x, col.z))
	return tint_for_tile(tile)


func _take_pop() -> int:
	for i in _pops.size():
		if _pop_life[i] <= 0.0:
			return i
	return 0


func _pool_node() -> _VfxPool:
	if _pool != null and is_instance_valid(_pool):
		return _pool
	var parent := get_parent()
	if parent and "_pool" in parent and parent._pool is _VfxPool:
		_pool = parent._pool
		return _pool
	_pool = _VfxPool.new()
	_pool.name = "BreakChips"
	add_child(_pool)
	return _pool


func _ensure() -> void:
	if _built:
		return
	var ws = _WorldSettings.get_active()
	var vs: float = ws.voxel_scale
	var layer: float = ws.layer_height()
	_pop_base = vs
	_crack = MeshInstance3D.new()
	_crack.name = "CrackOverlay"
	var box := BoxMesh.new()
	box.size = Vector3(vs * 1.04, layer * 1.04, vs * 1.04)
	_crack.mesh = box
	_crack_mat = ShaderMaterial.new()
	_crack_mat.shader = preload("res://shaders/block_crack.gdshader")
	_crack_mat.render_priority = 120
	_crack_mat.set_shader_parameter("stage", 1.0)
	_crack_mat.set_shader_parameter("progress", 0.4)
	_crack.material_override = _crack_mat
	_crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_crack.visible = false
	add_child(_crack)
	var pop_mesh := BoxMesh.new()
	pop_mesh.size = Vector3(vs * 0.96, layer * 0.96, vs * 0.96)
	for i in POP_SLOTS:
		var mesh := MeshInstance3D.new()
		mesh.name = "PlacePop%d" % i
		mesh.mesh = pop_mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.45, 0.8, 0.4, 0.45)
		mesh.material_override = mat
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.visible = false
		add_child(mesh)
		_pops.append(mesh)
		_pop_life.push_back(0.0)
	_built = true
