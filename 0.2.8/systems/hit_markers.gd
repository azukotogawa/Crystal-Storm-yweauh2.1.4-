class_name HitMarkers
extends Node3D

enum Result { HIT = 0, MISS = 1, BLOCKED = 2 }

const POOL := 6
const LIFE := 0.22

const _PlayerSettings = preload("res://systems/player_settings.gd")

var _slots: Array[Node3D] = []
var _rings: Array[MeshInstance3D] = []
var _crosses: Array[MeshInstance3D] = []
var _mats: Array[StandardMaterial3D] = []
var _life: PackedFloat32Array = PackedFloat32Array()
var _built: bool = false
var _busy: int = 0


func _ready() -> void:
	_ensure()
	set_process(false)


func has_live() -> bool:
	return _busy > 0


func show_at(world_pos: Vector3, result: int, radius: float, external: bool = false) -> Node3D:
	if not _PlayerSettings.hit_markers_enabled:
		return null
	_ensure()
	var slot := _take()
	var root := _slots[slot]
	var gen := int(root.get_meta("gen", 0)) + 1
	root.set_meta("gen", gen)
	root.global_position = world_pos
	root.visible = true
	var r := maxf(radius, 0.08)
	var ring := _rings[slot]
	var cross := _crosses[slot]
	var mat := _mats[slot]
	var tint := color_for(result)
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.8)
	if result == Result.BLOCKED:
		ring.visible = false
		cross.visible = true
		cross.scale = Vector3(r * 1.4, 1.0, r * 1.4)
	else:
		ring.visible = true
		cross.visible = false
		var torus := ring.mesh as TorusMesh
		torus.inner_radius = r * 0.72
		torus.outer_radius = r
		ring.scale = Vector3.ONE
		if result == Result.MISS:
			ring.scale = Vector3(0.72, 1.0, 0.72)
	_life[slot] = -1.0 if external else LIFE
	_busy += 1
	return root


func release(anchor: Node3D) -> void:
	if anchor == null or not is_instance_valid(anchor):
		return
	var slot := int(anchor.get_meta("slot", -1))
	if slot < 0 or slot >= _slots.size():
		return
	if not anchor.visible and _life[slot] == 0.0:
		return
	anchor.visible = false
	_life[slot] = 0.0
	_busy = maxi(_busy - 1, 0)


func tick(delta: float) -> void:
	if _busy <= 0:
		return
	var still := 0
	for i in _slots.size():
		var life := _life[i]
		if life < 0.0:
			if _slots[i].visible:
				still += 1
			continue
		if life <= 0.0:
			continue
		life -= delta
		var mat := _mats[i]
		var fade := clampf(life / LIFE, 0.0, 1.0)
		var c := mat.albedo_color
		c.a = 0.8 * fade
		mat.albedo_color = c
		if life <= 0.0:
			_slots[i].visible = false
			_life[i] = 0.0
		else:
			_life[i] = life
			still += 1
	_busy = still


func color_for(result: int) -> Color:
	match result:
		Result.MISS:
			return Color(0.62, 0.66, 0.74)
		Result.BLOCKED:
			return Color(0.95, 0.28, 0.22)
		_:
			return Color(1.0, 0.84, 0.32)


func slot_tint(slot_root: Node3D) -> Color:
	if slot_root == null:
		return Color.BLACK
	var slot := int(slot_root.get_meta("slot", -1))
	if slot < 0 or slot >= _mats.size():
		return Color.BLACK
	return _mats[slot].albedo_color


func visible_count() -> int:
	var n := 0
	for s in _slots:
		if s.visible:
			n += 1
	return n


func _take() -> int:
	for i in _slots.size():
		if not _slots[i].visible:
			return i
	var oldest := 0
	var best := 1000.0
	for i in _life.size():
		if _life[i] >= 0.0 and _life[i] < best:
			best = _life[i]
			oldest = i
	_slots[oldest].visible = false
	return oldest


func _ensure() -> void:
	if _built:
		return
	for i in POOL:
		var root := Node3D.new()
		root.name = "HitSlot%d" % i
		root.set_meta("slot", i)
		root.set_meta("gen", 0)
		root.visible = false
		var torus := TorusMesh.new()
		torus.inner_radius = 0.2
		torus.outer_radius = 0.28
		torus.rings = 6
		torus.ring_segments = 10
		var ring := MeshInstance3D.new()
		ring.name = "Ring"
		ring.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = color_for(Result.HIT)
		mat.no_depth_test = true
		ring.material_override = mat
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ring)
		var cross := MeshInstance3D.new()
		cross.name = "Cross"
		var box := BoxMesh.new()
		box.size = Vector3(0.55, 0.08, 0.12)
		cross.mesh = box
		cross.material_override = mat
		cross.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cross.visible = false
		cross.rotation = Vector3(0.0, PI * 0.25, 0.0)
		root.add_child(cross)
		add_child(root)
		_slots.append(root)
		_rings.append(ring)
		_crosses.append(cross)
		_mats.append(mat)
		_life.push_back(0.0)
	_built = true
