extends Node3D

const _Prop = preload("res://world/torch_prop.gd")
const _Scene = preload("res://scenes/torch_prop.tscn")
const _InputGate = preload("res://helpers/gameplay_input.gd")
const _Terrain = preload("res://helpers/terrain_lighting.gd")

const MAX_TORCHES := 8
const PLACE_STEP := 2.0
const USE_REACH := 4.5
const ITEM_ID := "torch"

var _block_place := false
var _block_interact := false
var _block_attack := false


func _ready() -> void:
	add_to_group("torch_field")
	process_priority = 0


func _process(_delta: float) -> void:
	_block_place = false
	_block_interact = false
	_block_attack = false
	if _InputGate.blocks_world():
		return
	var held := _held_id()
	if Input.is_action_just_pressed("build_place") and held == ITEM_ID:
		if _try_place():
			_block_place = true
	if Input.is_action_just_pressed("interact"):
		if _try_toggle():
			_block_interact = true
	if Input.is_action_just_pressed("attack") and held == ITEM_ID:
		_block_attack = true
		_try_pickup()
	_sync_shader()


func blocks_place() -> bool:
	return _block_place


func blocks_interact() -> bool:
	return _block_interact


func blocks_attack() -> bool:
	return _block_attack


func torch_count() -> int:
	var n := 0
	for child in get_children():
		if child is _Prop:
			n += 1
	return n


func lit_count() -> int:
	var n := 0
	for child in get_children():
		if child is _Prop and bool(child.lit):
			n += 1
	return n


func nearest_torch() -> Node3D:
	var host := _host()
	if host == null:
		return null
	var origin: Vector3 = host.global_position
	var best: Node3D = null
	var best_d := USE_REACH
	for child in get_children():
		if not (child is _Prop):
			continue
		var d := origin.distance_to((child as Node3D).global_position)
		if d <= best_d:
			best_d = d
			best = child
	return best


func _try_place() -> bool:
	if torch_count() >= MAX_TORCHES:
		return false
	var host := _host()
	var inv = _inventory()
	if host == null or inv == null:
		return false
	if not inv.has_method("consume_item") or not inv.consume_item(ITEM_ID, 1):
		return false
	var aim := _aim(host)
	var at: Vector3 = host.global_position + aim * PLACE_STEP
	for child in get_children():
		if child is _Prop and (child as Node3D).global_position.distance_to(at) < 1.2:
			inv.add_item(ITEM_ID, 1)
			return false
	var node := _Scene.instantiate() as Node3D
	if node == null:
		inv.add_item(ITEM_ID, 1)
		return false
	add_child(node)
	node.global_position = at
	return true


func _try_toggle() -> bool:
	var node := nearest_torch()
	if node == null or not node.has_method("toggle"):
		return false
	if bool(node.lit) or lit_count() < MAX_TORCHES:
		node.toggle()
		return true
	return false


func _try_pickup() -> bool:
	var node := nearest_torch()
	if node == null:
		return false
	var inv = _inventory()
	if inv != null and inv.has_method("add_item"):
		inv.add_item(ITEM_ID, 1)
	node.queue_free()
	return true


func _sync_shader() -> void:
	_Terrain.ensure_globals()
	var slots: Array[Vector4] = []
	for child in get_children():
		if not (child is _Prop):
			continue
		if slots.size() >= MAX_TORCHES:
			break
		var prop := child as Node3D
		var energy := 0.0
		if prop.has_method("light_energy"):
			energy = float(prop.light_energy())
		var p := prop.global_position
		slots.append(Vector4(p.x, p.y, p.z, energy))
	while slots.size() < MAX_TORCHES:
		slots.append(Vector4.ZERO)
	for i in MAX_TORCHES:
		RenderingServer.global_shader_parameter_set("torch_%d" % i, slots[i])
	RenderingServer.global_shader_parameter_set("torch_count", float(lit_count()))


func _held_id() -> String:
	var weapon := get_tree().get_first_node_in_group("weapon_controller") if is_inside_tree() else null
	if weapon != null and weapon.has_method("get_active_item"):
		var slot = weapon.get_active_item()
		if slot == null:
			return ""
		return str(slot.id)
	return ""


func _inventory():
	var weapon := get_tree().get_first_node_in_group("weapon_controller") if is_inside_tree() else null
	if weapon != null and "inventory" in weapon and weapon.inventory != null:
		return weapon.inventory
	var host := _host()
	if host != null and "inventory" in host:
		return host.inventory
	return null


func _host() -> Node3D:
	if not is_inside_tree():
		return null
	var nodes := get_tree().get_nodes_in_group("player")
	if nodes.is_empty():
		return null
	return nodes[0] as Node3D


func _aim(host: Node) -> Vector3:
	if host.has_method("get_torch_aim"):
		var aimed: Vector3 = host.get_torch_aim()
		aimed.y = 0.0
		if aimed.length_squared() > 0.0001:
			return aimed.normalized()
	var cam := host.get_node_or_null("Camera3D")
	if cam is Camera3D:
		var forward := -(cam as Camera3D).global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.0001:
			return forward.normalized()
	return Vector3(0.0, 0.0, -1.0)
