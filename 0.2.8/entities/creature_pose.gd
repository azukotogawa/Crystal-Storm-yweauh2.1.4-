extends RefCounted

const _LEG_L := "LegL"
const _LEG_R := "LegR"
const IDLE_LIFT := 0.22
const WALK_LEG := 1.15
const WALK_STEP := 0.62
const WALK_LIFT := 0.14
const WALK_BOB := 0.06
const ATTACK_LEG := 0.9
const ATTACK_LUNGE := 0.55

var _root_id: int = 0
var _parts: Array = []


func apply(root: Node3D, pose: String, phase: float) -> void:
	if root == null:
		return
	_bind(root)
	var swing := sin(phase)
	for part in _parts:
		var mi: MeshInstance3D = part.mi
		if not is_instance_valid(mi):
			continue
		var pos: Vector3 = part.pos
		var rot := Vector3.ZERO
		var kind := str(part.kind)
		var reach := float(part.reach)
		var side := float(part.side)
		if pose == "attack":
			if kind == "body" or kind == "top":
				pos.z -= reach
			elif kind == "leg":
				rot.x = side * ATTACK_LEG
		elif pose == "walk":
			if kind == "leg":
				var kick := swing * side
				rot.x = kick * WALK_LEG
				pos.z += kick * WALK_STEP
				pos.y += absf(swing) * WALK_LIFT
			elif kind == "top":
				pos.y += absf(sin(phase * 2.0)) * WALK_BOB
		elif kind == "top" or kind == "body":
			pos.y += swing * IDLE_LIFT
		mi.position = pos
		mi.rotation = rot


func _bind(root: Node3D) -> void:
	var id := root.get_instance_id()
	if id == _root_id and not _parts.is_empty():
		return
	_root_id = id
	_parts.clear()
	var boxes: Array[MeshInstance3D] = []
	for child in root.get_children():
		if child is MeshInstance3D and str(child.name) != _LEG_L and str(child.name) != _LEG_R:
			boxes.append(child)
	if boxes.is_empty():
		return
	var body: MeshInstance3D = boxes[0]
	var top: MeshInstance3D = boxes[0]
	var best := -1.0
	var top_y := -1.0e9
	for mi in boxes:
		var mesh := mi.mesh as BoxMesh
		var vol := 1.0
		if mesh:
			vol = mesh.size.x * mesh.size.y * mesh.size.z
		if vol > best:
			best = vol
			body = mi
		if mi.position.y >= top_y:
			top_y = mi.position.y
			top = mi
	var body_mesh := body.mesh as BoxMesh
	var body_h := body_mesh.size.y if body_mesh else 1.0
	var hip_y: float = body.position.y - body_h * 0.5
	var reach: float = maxf(body_h * 0.45, ATTACK_LUNGE)
	_add_legs(root, body, hip_y)
	for mi in boxes:
		var kind := "extra"
		if mi == body:
			kind = "body"
		elif mi == top:
			kind = "top"
		_parts.append({
			"mi": mi,
			"pos": mi.position,
			"kind": kind,
			"side": 1.0,
			"reach": reach,
		})
	for child in root.get_children():
		if str(child.name) == _LEG_L or str(child.name) == _LEG_R:
			var side := -1.0 if str(child.name) == _LEG_L else 1.0
			_parts.append({
				"mi": child,
				"pos": (child as Node3D).position,
				"kind": "leg",
				"side": side,
				"reach": reach,
			})


func _add_legs(root: Node3D, body: MeshInstance3D, hip_y: float) -> void:
	if root.get_node_or_null(_LEG_L) != null:
		return
	var u := maxf(hip_y, 0.45)
	var leg_h := maxf(minf(hip_y, u) * 0.9, 0.35)
	var size := Vector3(u * 0.28, leg_h, u * 0.28)
	var y := hip_y - leg_h * 0.45
	var spread := maxf(u * 0.22, 0.18)
	var color := Color(0.42, 0.3, 0.26)
	var mat := body.material_override as StandardMaterial3D
	if mat:
		color = mat.albedo_color.darkened(0.2)
	_leg(root, _LEG_L, Vector3(-spread, y, 0.1), size, color)
	_leg(root, _LEG_R, Vector3(spread, y, -0.1), size, color)


func _leg(root: Node3D, leg_name: String, center: Vector3, size: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.name = leg_name
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = center
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.disable_receive_shadows = false
	mat.roughness = 0.92
	mi.material_override = mat
	root.add_child(mi)
