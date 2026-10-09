class_name VfxPool
extends Node3D
## Pooled one-shot CPUParticles3D and a few swing meshes.
## Idle pool does not run _process. LOW keeps the smallest cap.

enum Kind { SHATTER, DUST, SPLASH, SPAWN_DEATH, CORRUPT, CHIP }

const _WorldSettings = preload("res://config/world_settings.gd")
const _PlayerSettings = preload("res://systems/player_settings.gd")

var _cap: int = 10
var _amount: int = 12
var _corrupt_cd: float = 0.22
var _cull: float = 48.0
var _swing_cap: int = 3
var _corrupt_wait: float = 0.0
var _all: Array[CPUParticles3D] = []
var _mesh: BoxMesh
var _mats: Dictionary = {}
var _player: Node3D
var _swings: Array[MeshInstance3D] = []
var _swing_life: PackedFloat32Array = PackedFloat32Array()
var _swing_max: PackedFloat32Array = PackedFloat32Array()
var _swing_busy: int = 0
var _arc_mesh: ArrayMesh
var _spear_mesh: BoxMesh
var _hammer_mesh: TorusMesh
var _swing_mats: Dictionary = {}


func _ready() -> void:
	set_process(false)


func configure_preset(preset: int) -> void:
	var caps: Dictionary = caps_for(preset)
	_cap = int(caps.get("emitters", 10))
	_amount = int(caps.get("amount", 12))
	_corrupt_cd = float(caps.get("corrupt_cd", 0.22))
	_cull = float(caps.get("cull_columns", 48.0))
	_swing_cap = int(caps.get("swings", 3))
	while _all.size() > _cap:
		var extra: CPUParticles3D = _all.pop_back()
		if is_instance_valid(extra):
			extra.queue_free()
	while _swings.size() > _swing_cap:
		var swing: MeshInstance3D = _swings.pop_back()
		if is_instance_valid(swing):
			swing.queue_free()
		if _swing_life.size() > _swings.size():
			_swing_life.resize(_swings.size())
			_swing_max.resize(_swings.size())


static func caps_for(preset: int) -> Dictionary:
	match preset:
		0:
			return {
				"emitters": 4,
				"amount": 6,
				"corrupt_cd": 0.50,
				"cull_columns": 18.0,
				"swings": 1,
			}
		2:
			return {
				"emitters": 16,
				"amount": 20,
				"corrupt_cd": 0.12,
				"cull_columns": 64.0,
				"swings": 4,
			}
		3:
			return {
				"emitters": 2,
				"amount": 4,
				"corrupt_cd": 0.70,
				"cull_columns": 12.0,
				"swings": 1,
			}
		_:
			return {
				"emitters": 10,
				"amount": 12,
				"corrupt_cd": 0.22,
				"cull_columns": 40.0,
				"swings": 3,
			}


func emitter_cap() -> int:
	return _cap


func emitter_count() -> int:
	var n := 0
	for p in _all:
		if is_instance_valid(p):
			n += 1
	return n


func active_count() -> int:
	var n := 0
	for p in _all:
		if is_instance_valid(p) and p.emitting:
			n += 1
	return n


func burst(kind: int, pos: Vector3, tint: Color = Color.WHITE, scale: float = 1.0) -> bool:
	# Shatter and spawn-death are the large bursts. Dust, splash, and corruption stay.
	if _PlayerSettings.reduce_motion and (kind == Kind.SHATTER or kind == Kind.SPAWN_DEATH):
		return false
	if kind == Kind.CORRUPT:
		if _corrupt_wait > 0.0:
			return false
		_corrupt_wait = _corrupt_cd
		set_process(true)
	if _too_far(pos):
		return false
	var p := _take()
	if p == null:
		return false
	_style(p, kind, tint, scale)
	if p.get_parent() != self:
		add_child(p)
	p.global_position = pos
	p.visible = true
	p.restart()
	p.emitting = true
	return true


func show_swing(item_id: String, origin: Vector3, forward: Vector3) -> void:
	var style := _swing_style(item_id)
	if style == "":
		return
	var flat := Vector3(forward.x, 0.0, forward.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3(0.0, 0.0, 1.0)
	flat = flat.normalized()
	var slot := _take_swing()
	if slot < 0:
		return
	var mesh_i := _swings[slot]
	var vs: float = _WorldSettings.get_active().voxel_scale
	mesh_i.material_override = _swing_material(style)
	var life := 0.12
	match style:
		"spear":
			mesh_i.mesh = _spear()
			mesh_i.global_position = origin + flat * (1.15 * vs) + Vector3(0.0, vs * 0.35, 0.0)
			mesh_i.rotation = Vector3(0.0, atan2(flat.x, flat.z), 0.0)
			mesh_i.scale = Vector3(0.08 * vs, 0.08 * vs, 2.4 * vs)
			life = 0.10
		"hammer":
			mesh_i.mesh = _hammer()
			mesh_i.global_position = origin + flat * (0.9 * vs) + Vector3(0.0, vs * 0.08, 0.0)
			mesh_i.rotation = Vector3.ZERO
			mesh_i.scale = Vector3(vs * 0.85, 1.0, vs * 0.85)
			life = 0.18
		"pick":
			mesh_i.mesh = _arc()
			mesh_i.global_position = origin + Vector3(0.0, vs * 0.45, 0.0)
			mesh_i.rotation = Vector3(0.0, atan2(flat.x, flat.z), 0.0)
			mesh_i.scale = Vector3.ONE * (vs * 0.85)
			life = 0.10
		_:
			mesh_i.mesh = _arc()
			mesh_i.global_position = origin + Vector3(0.0, vs * 0.55, 0.0)
			mesh_i.rotation = Vector3(0.0, atan2(flat.x, flat.z), 0.0)
			mesh_i.scale = Vector3.ONE * (vs * 1.25)
			life = 0.13
	mesh_i.visible = true
	var swing_mat := mesh_i.material_override as StandardMaterial3D
	if swing_mat:
		var tint := swing_mat.albedo_color
		tint.a = 0.85
		swing_mat.albedo_color = tint
	_swing_life[slot] = life
	_swing_max[slot] = life
	_swing_busy += 1
	set_process(true)


func _process(delta: float) -> void:
	if _corrupt_wait > 0.0:
		_corrupt_wait = maxf(_corrupt_wait - delta, 0.0)
	if _swing_busy > 0:
		var still := 0
		for i in _swings.size():
			if i >= _swing_life.size():
				break
			var life := _swing_life[i]
			if life <= 0.0:
				continue
			life -= delta
			_swing_life[i] = life
			var mesh_i := _swings[i]
			if life <= 0.0:
				mesh_i.visible = false
				continue
			still += 1
			var k := clampf(life / maxf(_swing_max[i], 0.001), 0.0, 1.0)
			var mat := mesh_i.material_override as StandardMaterial3D
			if mat:
				var c := mat.albedo_color
				c.a = 0.15 + 0.7 * k
				mat.albedo_color = c
			if mesh_i.mesh == _hammer_mesh:
				var grow := 1.0 + (1.0 - k) * 0.55
				var base: float = float(_WorldSettings.get_active().voxel_scale) * 0.85
				mesh_i.scale = Vector3(base * grow, 1.0, base * grow)
		_swing_busy = still
	if _swing_busy <= 0 and _corrupt_wait <= 0.0:
		set_process(false)


func _too_far(pos: Vector3) -> bool:
	if not is_instance_valid(_player):
		var tree := get_tree()
		_player = tree.get_first_node_in_group("player") as Node3D if tree else null
	if _player == null:
		return false
	var limit: float = _cull * float(_WorldSettings.get_active().voxel_scale)
	return _player.global_position.distance_squared_to(pos) > limit * limit


func _take() -> CPUParticles3D:
	for p in _all:
		if is_instance_valid(p) and not p.emitting:
			return p
	if _all.size() >= _cap:
		return null
	var made := _make()
	_all.append(made)
	return made


func _make() -> CPUParticles3D:
	_ensure_mesh()
	var p := CPUParticles3D.new()
	p.name = "PooledBurst"
	p.mesh = _mesh
	p.one_shot = true
	p.explosiveness = 0.92
	p.local_coords = true
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3.0, 3.0, 3.0))
	p.finished.connect(_on_particle_finished.bind(p))
	return p


func _on_particle_finished(p: CPUParticles3D) -> void:
	if not is_instance_valid(p):
		return
	p.emitting = false
	p.visible = false
	if p.get_parent() == self:
		remove_child(p)


func _style(p: CPUParticles3D, kind: int, tint: Color, scale: float) -> void:
	var count := _amount
	var life := 0.36
	var speed := 2.2
	var grav := Vector3(0.0, -3.0, 0.0)
	var spread := 55.0
	var direction := Vector3(0.0, 1.0, 0.0)
	var color := tint
	match kind:
		Kind.SHATTER:
			count = _amount
			life = 0.42
			speed = 3.4 * scale
			color = tint if tint.a > 0.1 else Color(0.9, 0.45, 1.0)
		Kind.DUST:
			count = maxi(3, int(_amount * 0.65))
			life = 0.32
			speed = 1.4
			grav = Vector3(0.0, -1.2, 0.0)
			color = Color(0.72, 0.55, 0.32)
		Kind.SPLASH:
			count = maxi(3, int(_amount * 0.55))
			life = 0.28
			speed = 2.0
			grav = Vector3(0.0, -4.5, 0.0)
			color = Color(0.55, 0.78, 0.95)
		Kind.SPAWN_DEATH:
			count = mini(28, _amount * 2)
			life = 0.55
			speed = 4.2
			spread = 80.0
			color = Color(1.0, 0.4, 0.95)
		Kind.CORRUPT:
			count = maxi(2, int(_amount * 0.4))
			life = 0.5
			speed = 0.7
			grav = Vector3(0.0, 0.4, 0.0)
			spread = 30.0
			color = Color(0.62, 0.28, 0.95, 0.8)
		Kind.CHIP:
			count = maxi(4, int(_amount * 0.55))
			life = 0.34
			speed = 2.1 * scale
			grav = Vector3(0.0, -2.4, 0.0)
			color = tint if tint.a > 0.05 else Color(0.72, 0.55, 0.32)
		_:
			pass
	p.amount = count
	p.lifetime = life
	p.direction = direction
	p.spread = spread
	p.gravity = grav
	p.initial_velocity_min = speed * 0.45
	p.initial_velocity_max = speed
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.85
	p.color = color
	p.mesh = _mesh
	var mat: StandardMaterial3D = _mats.get(kind)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		# Fixed white. Per-burst tint lives on p.color so in-flight bursts stay put.
		mat.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
		_mats[kind] = mat
	p.material_override = mat


func _ensure_mesh() -> void:
	if _mesh != null:
		return
	_mesh = BoxMesh.new()
	var chip: float = _WorldSettings.get_active().voxel_scale * 0.08
	_mesh.size = Vector3(chip, chip, chip)


func _swing_style(item_id: String) -> String:
	match item_id:
		"spear":
			return "spear"
		"crystal_hammer":
			return "hammer"
		"stone_pick":
			return "pick"
		"wooden_sword":
			return "sword"
		_:
			return ""


func _take_swing() -> int:
	for i in _swings.size():
		if i < _swing_life.size() and _swing_life[i] <= 0.0:
			return i
	if _swings.size() >= _swing_cap:
		return -1
	var mesh_i := MeshInstance3D.new()
	mesh_i.name = "SwingArc"
	mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_i.visible = false
	add_child(mesh_i)
	_swings.append(mesh_i)
	_swing_life.resize(_swings.size())
	_swing_max.resize(_swings.size())
	_swing_life[_swings.size() - 1] = 0.0
	_swing_max[_swings.size() - 1] = 0.12
	return _swings.size() - 1


func _arc() -> ArrayMesh:
	if _arc_mesh != null:
		return _arc_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 6
	var arc := deg_to_rad(78.0)
	var start := -arc * 0.5
	var inner := 0.28
	var outer := 1.0
	for i in steps:
		var a0 := start + arc * float(i) / float(steps)
		var a1 := start + arc * float(i + 1) / float(steps)
		var i0 := Vector3(sin(a0) * inner, 0.0, cos(a0) * inner)
		var o0 := Vector3(sin(a0) * outer, 0.06, cos(a0) * outer)
		var i1 := Vector3(sin(a1) * inner, 0.0, cos(a1) * inner)
		var o1 := Vector3(sin(a1) * outer, 0.06, cos(a1) * outer)
		st.add_vertex(i0)
		st.add_vertex(o0)
		st.add_vertex(o1)
		st.add_vertex(i0)
		st.add_vertex(o1)
		st.add_vertex(i1)
	_arc_mesh = st.commit()
	return _arc_mesh


func _spear() -> BoxMesh:
	if _spear_mesh == null:
		_spear_mesh = BoxMesh.new()
		_spear_mesh.size = Vector3(1.0, 1.0, 1.0)
	return _spear_mesh


func _hammer() -> TorusMesh:
	if _hammer_mesh == null:
		_hammer_mesh = TorusMesh.new()
		_hammer_mesh.inner_radius = 0.55
		_hammer_mesh.outer_radius = 0.78
		_hammer_mesh.rings = 6
		_hammer_mesh.ring_segments = 10
	return _hammer_mesh


func _swing_material(style: String) -> StandardMaterial3D:
	var existing: StandardMaterial3D = _swing_mats.get(style)
	if existing != null:
		return existing
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	match style:
		"spear":
			mat.albedo_color = Color(0.65, 0.9, 1.0, 0.85)
			mat.emission = Color(0.45, 0.8, 1.0)
		"hammer":
			mat.albedo_color = Color(1.0, 0.55, 0.2, 0.8)
			mat.emission = Color(1.0, 0.4, 0.15)
		"pick":
			mat.albedo_color = Color(0.85, 0.7, 0.4, 0.75)
			mat.emission = Color(0.7, 0.5, 0.25)
		_:
			mat.albedo_color = Color(1.0, 0.92, 0.55, 0.8)
			mat.emission = Color(1.0, 0.85, 0.4)
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 1.5
	_swing_mats[style] = mat
	return mat
