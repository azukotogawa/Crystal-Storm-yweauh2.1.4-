class_name Projectile
extends Node3D
## Pooled arrow / stone / bomb. Gravity, a segment test, then stick, fade, or blast.
## No physics body. Never edits terrain height.

const MAX_LIVE := 32
const STICK_TIME := 1.15

const _CombatHitResolver = preload("res://systems/combat_hit_resolver.gd")
const _WeaponStrike = preload("res://weapons/weapon_strike.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")

static var _pool: Array = []
static var _tracked: Array = []
static var _live: int = 0
static var _arrow_mesh: BoxMesh
static var _stone_mesh: SphereMesh
static var _bomb_mesh: SphereMesh
static var _arrow_mat: StandardMaterial3D
static var _stone_mat: StandardMaterial3D
static var _bomb_mat: StandardMaterial3D
static var _cached_frame: int = -1
static var _cached_nodes: Array = []
static var _cache_origin := Vector3.ZERO

var velocity := Vector3.ZERO
var gravity := 12.0
var damage := 10.0
var crystal_damage := 0.5
var knockback := 1.0
var blast_radius := 0.0
var ttl := 2.8
var hit_radius := 0.3
var source_id: StringName = &"shortbow"
var kind: StringName = &"arrow"
var active := false
var stuck := false
var stick_left := 0.0
var _crystal = null
var _world = null
var _chunk_manager = null
var _mesh: MeshInstance3D
## One fade material per node, created with the node. Impacts reuse it.
var _fade_mat: StandardMaterial3D
## Set while remove_child is parking this node in the pool, so _exit_tree does not drop it.
var _pool_detach: bool = false


func _init() -> void:
	_fade_mat = _new_fade_material()


static func launch(parent: Node, spec: Dictionary) -> bool:
	if parent == null:
		return false
	var node := _take_node(parent)
	if node == null:
		return false
	node._activate(spec)
	return true


static func live_count() -> int:
	return _live


static func _take_node(parent: Node) -> Projectile:
	_prune_pool()
	_recount_live()
	var node: Projectile = null
	if _live >= MAX_LIVE:
		node = _oldest_live(parent)
		if node != null and is_instance_valid(node):
			node._recycle_keep_count()
		else:
			_recount_live()
			node = null
			if _live >= MAX_LIVE:
				return null
	if node == null:
		while not _pool.is_empty():
			var candidate = _pool.pop_back()
			if is_instance_valid(candidate):
				node = candidate
				break
		if node == null:
			node = (load("res://weapons/projectile.gd") as GDScript).new()
	if not is_instance_valid(node):
		return null
	if node.get_parent() != parent:
		if node.get_parent():
			node.get_parent().remove_child(node)
		parent.add_child(node)
	return node


static func _prune_pool() -> void:
	var i := 0
	while i < _pool.size():
		if is_instance_valid(_pool[i]):
			i += 1
		else:
			_pool.remove_at(i)


static func _recount_live() -> void:
	var i := 0
	while i < _tracked.size():
		var entry = _tracked[i]
		if is_instance_valid(entry) and (entry as Projectile).active and (entry as Projectile).is_inside_tree():
			i += 1
		else:
			_tracked.remove_at(i)
	_live = _tracked.size()


static func _oldest_live(parent: Node) -> Projectile:
	var best: Projectile = null
	var best_ttl := INF
	for child in parent.get_children():
		if child is Projectile and (child as Projectile).active:
			var p := child as Projectile
			if p.ttl < best_ttl:
				best_ttl = p.ttl
				best = p
	return best


func _activate(spec: Dictionary) -> void:
	active = true
	stuck = false
	stick_left = 0.0
	visible = true
	kind = StringName(str(spec.get("kind", "arrow")))
	global_position = spec.get("origin", Vector3.ZERO)
	velocity = spec.get("velocity", Vector3.FORWARD)
	gravity = float(spec.get("gravity", 12.0))
	damage = float(spec.get("damage", 10.0))
	crystal_damage = float(spec.get("crystal_damage", 0.5))
	knockback = float(spec.get("knockback", 1.0))
	blast_radius = float(spec.get("blast_radius", 0.0))
	ttl = float(spec.get("ttl", 2.8 if kind != &"bomb" else 1.35))
	hit_radius = float(spec.get("hit_radius", 0.32 if kind != &"bomb" else 0.42))
	source_id = StringName(str(spec.get("source", "shortbow")))
	_crystal = spec.get("crystal")
	_world = spec.get("world")
	_chunk_manager = spec.get("chunk_manager")
	_ensure_mesh()
	_aim_mesh()
	_note_tracked()


func _process(delta: float) -> void:
	if not active:
		return
	integrate(delta, _nodes_for_frame())


## Semi-implicit step. Probe calls this directly. Returns "fly", "entity", "crystal", "terrain", or "blast".
func integrate(delta: float, nodes: Array = []) -> String:
	if not active:
		return "idle"
	if stuck:
		stick_left -= delta
		if _mesh and _mesh.material_override is StandardMaterial3D:
			var mat := _mesh.material_override as StandardMaterial3D
			var color := mat.albedo_color
			color.a = clampf(stick_left / STICK_TIME, 0.0, 1.0)
			mat.albedo_color = color
		if stick_left <= 0.0:
			_recycle()
		return "stuck"
	var prev := global_position
	velocity.y -= gravity * delta
	var nxt := prev + velocity * delta
	ttl -= delta
	var hit := _trace(prev, nxt, nodes)
	var hit_kind := str(hit.get("kind", "fly"))
	if hit_kind == "entity":
		_damage_entity(hit.get("node"), nxt)
		if kind == &"bomb":
			_explode(nxt)
		else:
			_recycle()
		return "entity"
	if hit_kind == "crystal":
		if kind == &"bomb":
			_explode(hit.get("pos", nxt))
		else:
			_damage_crystal_cell(hit.get("cell", Vector2i.ZERO))
			_stick_at(hit.get("pos", nxt))
		return "crystal"
	if hit_kind == "terrain":
		if kind == &"bomb":
			_explode(hit.get("pos", nxt))
		else:
			_stick_at(hit.get("pos", nxt))
		return "terrain"
	global_position = nxt
	_aim_mesh()
	if ttl <= 0.0:
		if kind == &"bomb":
			_explode(global_position)
			return "blast"
		_recycle()
		return "timeout"
	return "fly"


func _nodes_for_frame() -> Array:
	if not is_inside_tree():
		return []
	var frame := Engine.get_process_frames()
	if frame == _cached_frame and global_position.distance_squared_to(_cache_origin) < 4096.0:
		return _cached_nodes
	_cached_frame = frame
	_cache_origin = global_position
	_cached_nodes = _CombatHitResolver._combat_nodes(self, global_position, 48.0)
	return _cached_nodes


func _trace(a: Vector3, b: Vector3, nodes: Array) -> Dictionary:
	var entity_t := INF
	var entity: Node = null
	var ab := b - a
	var ab_len2 := ab.length_squared()
	for node in nodes:
		if not is_instance_valid(node):
			continue
		if node.has_method("is_combat_alive") and not bool(node.is_combat_alive()):
			continue
		var center: Vector3 = node.global_position
		if node.has_method("get_combat_center"):
			center = node.get_combat_center()
		var radius := hit_radius
		if node.has_method("get_combat_radius"):
			radius += float(node.get_combat_radius()) * 0.65
		var t := 0.0
		if ab_len2 > 0.0001:
			t = clampf((center - a).dot(ab) / ab_len2, 0.0, 1.0)
		var closest := a + ab * t
		if closest.distance_squared_to(center) > radius * radius:
			continue
		if t < entity_t:
			entity_t = t
			entity = node
	var terrain_t := INF
	var terrain_pos := b
	var ground := _ground_y(b)
	if ground < 9000.0 and b.y <= ground and a.y >= ground - 0.15:
		var drop := a.y - b.y
		var t := 0.0 if absf(drop) < 0.0001 else clampf((a.y - ground) / drop, 0.0, 1.0)
		terrain_t = t
		terrain_pos = a.lerp(b, t)
		terrain_pos.y = ground
	var crystal_t := INF
	var crystal_cell := Vector2i.ZERO
	var crystal_pos := b
	if _crystal != null and _crystal.has_method("get_depth_at"):
		var sample := b if terrain_t >= 1.0 else terrain_pos
		var cell := _column_of(sample)
		var depth := float(_crystal.get_depth_at(cell.x, cell.y))
		if depth >= 0.04:
			var feet := _ground_y(sample)
			var top: float = feet + maxf(depth, 0.35) * _WorldSettings.get_active().voxel_scale
			var y := sample.y
			if y <= top + 0.4 and y >= feet - 0.2:
				crystal_t = 0.45 if terrain_t >= 1.0 else minf(terrain_t, 0.45)
				crystal_cell = cell
				crystal_pos = sample
				crystal_pos.y = clampf(y, feet, top)
	if entity != null and entity_t <= terrain_t and entity_t <= crystal_t:
		return {"kind": "entity", "node": entity}
	if crystal_cell != Vector2i.ZERO and crystal_t <= terrain_t:
		return {"kind": "crystal", "cell": crystal_cell, "pos": crystal_pos}
	if terrain_t < INF:
		return {"kind": "terrain", "pos": terrain_pos}
	return {"kind": "fly"}


func _ground_y(at: Vector3) -> float:
	if _world != null and _world.has_method("get_surface_height"):
		var ws = _WorldSettings.get_active()
		return float(_world.get_surface_height(ws.world_to_column(at.x), ws.world_to_column(at.z)))
	return 10000.0


func _column_of(at: Vector3) -> Vector2i:
	var ws = _WorldSettings.get_active()
	return Vector2i(floori(ws.world_to_column(at.x)), floori(ws.world_to_column(at.z)))


func _damage_entity(node, at: Vector3) -> void:
	if node == null or not is_instance_valid(node):
		return
	_CombatHitResolver.apply_damage(node, damage, source_id)
	if node.has_method("apply_knockback"):
		var center: Vector3 = node.global_position
		if node.has_method("get_combat_center"):
			center = node.get_combat_center()
		node.apply_knockback(center - global_position, knockback)
	_ping(at)


func _damage_crystal_cell(cell: Vector2i) -> void:
	if _crystal == null:
		return
	if _crystal.has_method("damage_crystal_at"):
		_crystal.damage_crystal_at(cell, crystal_damage)
	if _crystal.has_method("damage_spawn_at_world"):
		_crystal.damage_spawn_at_world(cell, damage, 1.6)


func _explode(at: Vector3) -> void:
	global_position = at
	var cell := _column_of(at)
	var cells := _WeaponStrike.blast_cells(cell, blast_radius if blast_radius > 0.0 else 2.5)
	_WeaponStrike.apply_crystal_cells(_crystal, cells, crystal_damage)
	if _crystal != null and _crystal.has_method("damage_spawn_at_world"):
		_crystal.damage_spawn_at_world(cell, damage, blast_radius if blast_radius > 0.0 else 2.5)
	var radius_w: float = (blast_radius if blast_radius > 0.0 else 2.5) * _WorldSettings.get_active().voxel_scale
	var nodes: Array = _nodes_for_frame() if is_inside_tree() else []
	for node in _WeaponStrike.enemies_in_radius(at, radius_w, nodes):
		_CombatHitResolver.apply_damage(node, damage, source_id)
		if node.has_method("apply_knockback"):
			var center: Vector3 = node.global_position
			if node.has_method("get_combat_center"):
				center = node.get_combat_center()
			node.apply_knockback(center - at, knockback)
	_ping(at)
	_recycle()


func _stick_at(at: Vector3) -> void:
	global_position = at
	stuck = true
	stick_left = STICK_TIME
	velocity = Vector3.ZERO
	_ensure_mesh()
	_use_fade_material()
	_ping(at)


func _ping(at: Vector3) -> void:
	if not is_inside_tree():
		return
	var vfx = get_tree().get_first_node_in_group("combat_visual_feedback")
	var audio := get_node_or_null("/root/AudioManager")
	if kind == &"bomb":
		if vfx and vfx.has_method("burst_bomb"):
			vfx.burst_bomb(at)
		if audio and audio.has_method("play_sfx"):
			audio.play_sfx("bomb_explode", at)
	else:
		if vfx and vfx.has_method("show_hit_marker"):
			vfx.show_hit_marker(at)
		if audio and audio.has_method("play_sfx"):
			var impact := "impact_arrow" if kind == &"arrow" else "impact_stone"
			audio.play_sfx(impact, at)
	if _water_at(at):
		if vfx and vfx.has_method("splash_at"):
			vfx.splash_at(at)
		elif audio and audio.has_method("play_sfx"):
			audio.play_sfx("water_splash", at)


func _water_at(at: Vector3) -> bool:
	if _world == null or not _world.has_method("get_tile_type"):
		return false
	var cell := _column_of(at)
	return _CrystalTypes.is_water_tile(int(_world.get_tile_type(float(cell.x) + 0.5, float(cell.y) + 0.5)))


func _recycle() -> void:
	active = false
	stuck = false
	visible = false
	_crystal = null
	_world = null
	_chunk_manager = null
	if _mesh:
		_apply_shared_material()
	_pool_detach = true
	if get_parent():
		get_parent().remove_child(self)
	_pool_detach = false
	_forget_tracked()
	if is_instance_valid(self) and _pool.size() < MAX_LIVE:
		_pool.append(self)
	else:
		queue_free()


func _recycle_keep_count() -> void:
	# Reuse a live slot. The node stays tracked; _activate does not add it twice.
	active = false
	stuck = false
	_crystal = null
	_world = null
	_chunk_manager = null
	if _mesh:
		_apply_shared_material()


func _exit_tree() -> void:
	if _pool_detach:
		return
	# Parent scene freed this shot. Drop it before the next run pops a dead node.
	active = false
	_forget_tracked()
	var pool_i := _pool.find(self)
	if pool_i >= 0:
		_pool.remove_at(pool_i)


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	var pool_i := _pool.find(self)
	if pool_i >= 0:
		_pool.remove_at(pool_i)
	_forget_tracked()


func _note_tracked() -> void:
	if _tracked.find(self) < 0:
		_tracked.append(self)
	_live = _tracked.size()


func _forget_tracked() -> void:
	var live_i := _tracked.find(self)
	if live_i >= 0:
		_tracked.remove_at(live_i)
	_live = _tracked.size()


func _use_fade_material() -> void:
	if _fade_mat == null:
		_fade_mat = _new_fade_material()
	var source := _shared_material_for_kind()
	var color := source.albedo_color
	color.a = 1.0
	_fade_mat.albedo_color = color
	if _mesh:
		_mesh.material_override = _fade_mat


func _ensure_mesh() -> void:
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		_mesh.name = "ProjectileMesh"
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mesh)
	_mesh.visible = true
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match kind:
		&"stone":
			_mesh.mesh = _shared_stone_mesh()
		&"bomb":
			_mesh.mesh = _shared_bomb_mesh()
		_:
			_mesh.mesh = _shared_arrow_mesh()
	_apply_shared_material()


func _apply_shared_material() -> void:
	if _mesh == null:
		return
	_mesh.material_override = _shared_material_for_kind()


func _shared_material_for_kind() -> StandardMaterial3D:
	match kind:
		&"stone":
			return _shared_stone_mat()
		&"bomb":
			return _shared_bomb_mat()
		_:
			return _shared_arrow_mat()


func _aim_mesh() -> void:
	if not is_inside_tree() or _mesh == null or kind == &"stone" or kind == &"bomb":
		return
	if velocity.length_squared() < 0.04:
		return
	var look := global_position + velocity
	if absf(velocity.normalized().dot(Vector3.UP)) > 0.98:
		return
	look_at(look, Vector3.UP)


static func _shared_arrow_mesh() -> BoxMesh:
	if _arrow_mesh == null:
		_arrow_mesh = BoxMesh.new()
		_arrow_mesh.size = Vector3(0.08, 0.08, 0.85)
	return _arrow_mesh


static func _shared_stone_mesh() -> SphereMesh:
	if _stone_mesh == null:
		_stone_mesh = SphereMesh.new()
		_stone_mesh.radius = 0.16
		_stone_mesh.height = 0.32
	return _stone_mesh


static func _shared_bomb_mesh() -> SphereMesh:
	if _bomb_mesh == null:
		_bomb_mesh = SphereMesh.new()
		_bomb_mesh.radius = 0.28
		_bomb_mesh.height = 0.56
	return _bomb_mesh


static func _shared_arrow_mat() -> StandardMaterial3D:
	if _arrow_mat == null:
		_arrow_mat = _unshaded(Color(0.72, 0.48, 0.22))
	return _arrow_mat


static func _shared_stone_mat() -> StandardMaterial3D:
	if _stone_mat == null:
		_stone_mat = _unshaded(Color(0.55, 0.56, 0.58))
	return _stone_mat


static func _shared_bomb_mat() -> StandardMaterial3D:
	if _bomb_mat == null:
		_bomb_mat = _unshaded(Color(0.72, 0.25, 0.95))
	return _bomb_mat


static func _unshaded(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func _new_fade_material() -> StandardMaterial3D:
	var mat := _unshaded(Color(1, 1, 1, 1))
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat
