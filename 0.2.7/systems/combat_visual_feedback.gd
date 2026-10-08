class_name CombatVisualFeedback
extends Node3D

const _PerformanceQualityConfig = preload("res://config/performance_quality_config.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _GameManager = preload("res://game/game_manager.gd")
const _WorldVisualCoords = preload("res://helpers/world_visual_coords.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _VfxPool = preload("res://systems/vfx_pool.gd")
const _Juice = preload("res://systems/juice.gd")

@export var enabled: bool = true

var _quality: _PerformanceQualityConfig = _PerformanceQualityConfig.create_default()
var _label_pool: Array[Label3D] = []
var _label_slots: Array[Dictionary] = []
var _bursts: Array[Dictionary] = []
var _textures: Dictionary = {}
var _boss_ring: MeshInstance3D
var _victory_flash: MeshInstance3D
var _burst_root: Node3D
var _labels_root: Node3D
var _crystal: CrystalManager
var _game_manager: Node
var _pool: _VfxPool
var _player: Node3D
var _audio: Node
var _dissolve_root: Node3D
var _dissolves: Array[Dictionary] = []
const _DISSOLVE_SEC := 0.4
const _DISSOLVE_CAP := 6


func _enter_tree() -> void:
	add_to_group("combat_visual_feedback")


func _ready() -> void:
	_ensure_visual_roots()
	_ensure_pool()
	_build_label_pool()
	call_deferred("_load_textures")
	_build_indicators()
	call_deferred("_connect_signals")


func _vox(voxels: float) -> float:
	return voxels * _WorldSettings.get_active().voxel_scale


func _ensure_visual_roots() -> void:
	_burst_root = get_node_or_null("Bursts") as Node3D
	if _burst_root == null:
		_burst_root = Node3D.new()
		_burst_root.name = "Bursts"
		add_child(_burst_root)
	_labels_root = get_node_or_null("DamageLabels") as Node3D
	if _labels_root == null:
		_labels_root = Node3D.new()
		_labels_root.name = "DamageLabels"
		add_child(_labels_root)


func apply_performance_config(cfg: _PerformanceQualityConfig) -> void:
	if cfg == null:
		return
	_quality = cfg
	enabled = cfg.combat_visuals_enabled
	_ensure_pool()
	_pool.configure_preset(int(cfg.preset))
	_Juice.set_preset(int(cfg.preset))
	_trim_label_pool(maxi(int(cfg.max_damage_labels), 0))
	if not enabled:
		_clear_active_vfx()
	else:
		reload_textures()


func reload_textures() -> void:
	if not is_inside_tree():
		return
	_textures.clear()
	call_deferred("_load_textures")


func on_chunk_manager_ready(_cm: ChunkManager) -> void:
	# Bind handles once; do not regenerate combat textures on every handoff.
	if _textures.is_empty():
		reload_textures()
	else:
		_apply_textures_to_indicators()


func _await_chunk_manager() -> void:
	while is_inside_tree() and get_tree().get_first_node_in_group("chunk_manager") == null:
		await get_tree().process_frame


func _load_textures() -> void:
	var registry = get_tree().get_first_node_in_group("game_visual_registry")
	if registry and registry.has_method("ensure_textures_ready"):
		await registry.ensure_textures_ready()
	elif registry and registry.has_method("ensure_ready"):
		await registry.ensure_ready()
	await _await_chunk_manager()
	if registry:
		# Bundle is generated once at registry init; preload is a no-op when ready.
		if registry.has_method("preload_game_bundle"):
			registry.preload_game_bundle(false, "CombatVisualFeedback._load_textures")
		_textures = {
			"damage_number": registry.get_combat_texture(&"damage_number"),
			"hit_flash": registry.get_combat_texture(&"hit_flash"),
			"shatter": registry.get_combat_texture(&"shatter"),
			"spawn_boss": registry.get_combat_texture(&"spawn_boss"),
			"spawn_miniboss": registry.get_combat_texture(&"spawn_miniboss"),
			"victory_glow": registry.get_combat_texture(&"victory_glow"),
		}
	else:
		var gen = get_node_or_null("/root/CrystalTextureGenerator")
		if gen and gen.has_method("generate_combat_ui_bundle"):
			_textures = gen.generate_combat_ui_bundle()
	_apply_textures_to_indicators()


func _apply_textures_to_indicators() -> void:
	if _boss_ring and _boss_ring.material_override is StandardMaterial3D and _textures.has("spawn_boss"):
		(_boss_ring.material_override as StandardMaterial3D).albedo_texture = _textures.spawn_boss
	if _victory_flash and _victory_flash.material_override is StandardMaterial3D and _textures.has("victory_glow"):
		(_victory_flash.material_override as StandardMaterial3D).albedo_texture = _textures.victory_glow


func _build_label_pool() -> void:
	_trim_label_pool(_quality.max_damage_labels)


func _clear_active_vfx() -> void:
	for i in _label_slots.size():
		if i < _label_pool.size():
			_label_pool[i].visible = false
		_label_slots[i] = {"active": false, "time": 0.0}
	for b in _bursts:
		var anchor: Node3D = b.get("anchor")
		if is_instance_valid(anchor):
			anchor.queue_free()
	_bursts.clear()
	if _boss_ring:
		_boss_ring.visible = false
	if _victory_flash:
		_victory_flash.visible = false


func _trim_label_pool(count: int) -> void:
	_ensure_visual_roots()
	while _label_pool.size() > count:
		var n: Label3D = _label_pool.pop_back()
		if is_instance_valid(n):
			n.queue_free()
	while _label_pool.size() < count:
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 22
		label.outline_size = 6
		label.modulate = Color(1.0, 0.92, 0.55, 1.0)
		label.visible = false
		_labels_root.add_child(label)
		_label_pool.append(label)
	_label_slots.resize(_label_pool.size())
	for i in _label_pool.size():
		_label_slots[i] = {"active": false, "time": 0.0}


func _build_indicators() -> void:
	_boss_ring = MeshInstance3D.new()
	_boss_ring.name = "BossRing"
	var torus := TorusMesh.new()
	var vs: float = _WorldSettings.get_active().voxel_scale
	torus.inner_radius = 0.45 * vs
	torus.outer_radius = 0.575 * vs
	torus.rings = 8
	torus.ring_segments = 12
	_boss_ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.35, 0.95, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.2, 0.85)
	mat.emission_energy_multiplier = 1.8
	if _textures.has("spawn_boss"):
		mat.albedo_texture = _textures.spawn_boss
	_boss_ring.material_override = mat
	_boss_ring.visible = false
	add_child(_boss_ring)

	_victory_flash = MeshInstance3D.new()
	_victory_flash.name = "VictoryFlash"
	var quad := QuadMesh.new()
	var flash_vs: float = _WorldSettings.get_active().voxel_scale
	quad.size = Vector2(3.0 * flash_vs, 1.5 * flash_vs)
	_victory_flash.mesh = quad
	var vmat := StandardMaterial3D.new()
	vmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vmat.albedo_color = Color(1.0, 0.95, 0.55, 0.0)
	if _textures.has("victory_glow"):
		vmat.albedo_texture = _textures.victory_glow
	_victory_flash.material_override = vmat
	_victory_flash.visible = false
	add_child(_victory_flash)


func _connect_signals() -> void:
	_crystal = get_tree().get_first_node_in_group("crystal_manager")
	_game_manager = get_tree().get_first_node_in_group("game_manager")

	_player = get_tree().get_first_node_in_group("player")
	var player = _player
	if player:
		var weapon = player.get_node_or_null("WeaponController")
		if weapon and weapon.has_signal("entity_hit"):
			if not weapon.entity_hit.is_connected(_on_entity_hit):
				weapon.entity_hit.connect(_on_entity_hit)
		if weapon and weapon.has_signal("attacked"):
			if not weapon.attacked.is_connected(_on_weapon_attacked):
				weapon.attacked.connect(_on_weapon_attacked)

	if _crystal:
		if _crystal.has_signal("spawn_destroyed") and not _crystal.spawn_destroyed.is_connected(_on_spawn_destroyed):
			_crystal.spawn_destroyed.connect(_on_spawn_destroyed)
		if _crystal.has_signal("spawn_damaged") and not _crystal.spawn_damaged.is_connected(_on_spawn_damaged):
			_crystal.spawn_damaged.connect(_on_spawn_damaged)
		if _crystal.has_signal("crystal_mass_hit") and not _crystal.crystal_mass_hit.is_connected(_on_crystal_mass_hit):
			_crystal.crystal_mass_hit.connect(_on_crystal_mass_hit)

	if _game_manager:
		if _game_manager.has_signal("phase_changed") and not _game_manager.phase_changed.is_connected(_on_phase_changed):
			_game_manager.phase_changed.connect(_on_phase_changed)
		if _game_manager.has_signal("run_state_changed") and not _game_manager.run_state_changed.is_connected(_on_run_state_changed):
			_game_manager.run_state_changed.connect(_on_run_state_changed)

	var entity_mgr = get_tree().get_first_node_in_group("entity_manager")
	if entity_mgr and entity_mgr.has_signal("entity_spawned"):
		if not entity_mgr.entity_spawned.is_connected(_on_entity_spawned):
			entity_mgr.entity_spawned.connect(_on_entity_spawned)
		for entity in get_tree().get_nodes_in_group("world_entity"):
			_bind_entity_death(entity)


func _process(delta: float) -> void:
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("combat_vfx")
	_update_labels(delta)
	_update_bursts(delta)
	_update_spawn_marker_flashes(delta)
	_update_boss_ring(delta)
	_update_victory_flash(delta)
	if not _dissolves.is_empty():
		_update_dissolves(delta)
	if profiler and profiler.has_method("end"):
		profiler.end("combat_vfx")


## Brief placement flash for walls / gates / bridges (satisfying build feedback).
func show_place_flash(col_pos: Vector3, build_id: StringName = &"stone_wall") -> void:
	if build_id == &"dig":
		_burst_dig_dust(col_pos)
	if not enabled:
		return
	_ensure_visual_roots()
	var color := Color(0.45, 1.0, 0.55)
	var label := "Wall"
	match build_id:
		&"gate":
			color = Color(0.95, 0.85, 0.35)
			label = "Gate"
		&"bridge":
			color = Color(0.55, 0.8, 1.0)
			label = "Bridge"
		&"wood_wall":
			label = "Wood"
		&"dig":
			color = Color(0.85, 0.55, 0.28)
			label = ""
		&"crystal_front":
			# Sparse pulse on the nearest open crystal edge (readability only).
			color = Color(0.85, 0.35, 1.0)
			label = ""
		_:
			label = "Wall"
	var ws = _WorldSettings.get_active()
	var scale: float = ws.voxel_scale
	var layer: float = ws.layer_height()
	var wx: float = floorf(col_pos.x) + 0.5
	var wz: float = floorf(col_pos.z) + 0.5
	var y: float = col_pos.y + layer * 0.35
	var anchor := Node3D.new()
	_burst_root.add_child(anchor)
	anchor.global_position = _WorldVisualCoords.column_to_world_pos(wx, y, wz)
	var mesh_i := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(scale * 0.95, layer * 0.35, scale * 0.95)
	mesh_i.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.55)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.6
	mat.no_depth_test = true
	mesh_i.material_override = mat
	anchor.add_child(mesh_i)
	var tag: Label3D = null
	if not label.is_empty():
		tag = Label3D.new()
		tag.text = label
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.font_size = 18
		tag.outline_size = 4
		tag.modulate = color
		tag.position = Vector3(0.0, layer * 0.55, 0.0)
		anchor.add_child(tag)
	var life: float = 0.28
	var vel := Vector3(0.0, 1.2, 0.0)
	if build_id == &"dig":
		life = 0.32
		vel = Vector3(0.0, 0.8, 0.0)
	elif build_id == &"crystal_front":
		life = 0.55
		vel = Vector3(0.0, 0.35, 0.0)
		box.size = Vector3(scale * 1.35, layer * 0.55, scale * 1.35)
		mesh_i.mesh = box
		mat.albedo_color = Color(color.r, color.g, color.b, 0.42)
		mat.emission_energy_multiplier = 2.4
	_bursts.append({
		"anchor": anchor,
		"sprite": null,
		"vel": vel,
		"life": life,
		"place": true,
		"mesh": mesh_i,
		"tag": tag,
	})
	if build_id == &"dig":
		_spawn_break_shards(anchor.global_position, color, 3)


## Short ring at a world-space impact. Radius matches the combat hitbox when known.
func show_hit_marker(world_pos: Vector3, tint: Color = Color(1.0, 0.85, 0.4), radius: float = 0.45) -> void:
	if not enabled:
		return
	_ensure_visual_roots()
	if _bursts.size() >= _quality.max_burst_sprites:
		return
	var anchor := Node3D.new()
	anchor.name = "HitMarker"
	_burst_root.add_child(anchor)
	var lift: float = _WorldSettings.get_active().voxel_scale * 0.04
	anchor.global_position = world_pos + Vector3(0.0, lift, 0.0)
	var mesh_i := MeshInstance3D.new()
	var torus := TorusMesh.new()
	var r := maxf(radius, _WorldSettings.get_active().voxel_scale * 0.1)
	torus.inner_radius = r * 0.72
	torus.outer_radius = r
	torus.rings = 6
	torus.ring_segments = 10
	mesh_i.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.75)
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 2.2
	mat.no_depth_test = true
	mesh_i.material_override = mat
	anchor.add_child(mesh_i)
	_bursts.append({
		"anchor": anchor,
		"sprite": null,
		"vel": Vector3.ZERO,
		"life": 0.24,
		"place": true,
		"mesh": mesh_i,
		"hit_marker": true,
	})


func _spawn_break_shards(world_pos: Vector3, tint: Color, count: int) -> void:
	var chip: float = _WorldSettings.get_active().voxel_scale * 0.22
	for i in count:
		if _bursts.size() >= _quality.max_burst_sprites:
			return
		var anchor := Node3D.new()
		anchor.name = "BreakShard"
		_burst_root.add_child(anchor)
		var spread := float(i) - float(count - 1) * 0.5
		anchor.global_position = world_pos + Vector3(spread * chip * 0.35, chip * 0.15, 0.0)
		var mesh_i := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(chip, chip * 0.7, chip * 0.85)
		mesh_i.mesh = box
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.92)
		mat.emission_enabled = true
		mat.emission = tint
		mat.emission_energy_multiplier = 1.4
		mesh_i.material_override = mat
		anchor.add_child(mesh_i)
		_bursts.append({
			"anchor": anchor,
			"sprite": null,
			"vel": Vector3(spread * 1.6, 1.8 + float(i) * 0.25, spread * 0.4),
			"life": 0.45,
			"place": false,
			"mesh": mesh_i,
			"break_shard": true,
			"spin": 4.0 + float(i),
		})


func show_damage_column(col_pos: Vector3, amount: float, color: Color = Color(1.0, 0.9, 0.5)) -> void:
	if not enabled or amount <= 0.0:
		return
	var ws = _WorldSettings.get_active()
	var world_pos := Vector3(
		ws.column_to_world(col_pos.x),
		col_pos.y + ws.player_height() * 0.6,
		ws.column_to_world(col_pos.z)
	)
	_show_damage_at(world_pos, amount, color)


func _show_damage_at(world_pos: Vector3, amount: float, color: Color) -> void:
	for i in _label_slots.size():
		if _label_slots[i].active:
			continue
		var label: Label3D = _label_pool[i]
		label.text = "%.0f" % amount
		label.modulate = color
		label.global_position = world_pos
		label.visible = true
		_label_slots[i] = {"active": true, "time": _quality.damage_number_lifetime}
		return


func _spawn_burst(world_pos: Vector3, tint: Color, count: int = -1) -> void:
	if not enabled:
		return
	_ensure_visual_roots()
	var n: int = count if count > 0 else mini(4, _quality.max_burst_sprites)
	var registry = get_tree().get_first_node_in_group("game_visual_registry")
	for _i in n:
		if _bursts.size() >= _quality.max_burst_sprites:
			break
		var anchor := Node3D.new()
		anchor.name = "Burst"
		_burst_root.add_child(anchor)
		anchor.global_position = world_pos + Vector3(randf_range(-0.2, 0.2), 0.2, randf_range(-0.2, 0.2))

		var sprite := Sprite3D.new()
		sprite.name = "Sprite3D"
		anchor.add_child(sprite)
		var tex: Texture2D = _textures.get("shatter") if _textures.has("shatter") else null
		if tex == null and registry and registry.has_method("get_combat_texture"):
			tex = registry.get_combat_texture(&"shatter")
		if registry and registry.has_method("apply_to_sprite3d"):
			registry.apply_to_sprite3d(sprite, tex, tint)
		elif registry and registry.has_method("configure_sprite3d"):
			registry.configure_sprite3d(sprite, tex, tint)
		else:
			sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sprite.texture = tex
			sprite.modulate = tint
			if registry and registry.has_method("sprite_pixel_size"):
				sprite.pixel_size = registry.sprite_pixel_size()
			else:
				sprite.pixel_size = _WorldSettings.get_active().voxel_scale * 0.015

		var vel := Vector3(randf_range(-1.2, 1.2), randf_range(1.5, 3.0), randf_range(-1.2, 1.2))
		_bursts.append({
			"anchor": anchor,
			"sprite": sprite,
			"vel": vel,
			"life": randf_range(0.35, 0.65),
		})


func _on_entity_spawned(entity: Node) -> void:
	_bind_entity_death(entity)


func _bind_entity_death(entity: Node) -> void:
	if entity == null or not entity.has_signal("died"):
		return
	if entity.died.is_connected(_on_world_entity_died):
		return
	entity.died.connect(_on_world_entity_died)


func _on_world_entity_died(entity: Node, _world_pos: Vector2i) -> void:
	if entity == null:
		return
	var pos: Vector3 = entity.global_position
	_spawn_burst(pos + Vector3(0.0, _vox(0.25), 0.0), Color(0.85, 0.55, 0.35), 3)


func _on_weapon_attacked(item_id: String, hit_pos: Vector3) -> void:
	if not enabled:
		return
	var def := _ItemTypes.get_def(item_id)
	if def.is_empty():
		return
	var kind := int(def.get("weapon_kind", _ItemTypes.WeaponKind.MELEE))
	match kind:
		_ItemTypes.WeaponKind.MELEE, _ItemTypes.WeaponKind.DIG:
			show_hit_marker(hit_pos + Vector3(0.0, _vox(0.075), 0.0), Color(1.0, 0.88, 0.45), _vox(0.21))
			_spawn_burst(hit_pos + Vector3(0.0, _vox(0.175), 0.0), Color(1.0, 0.88, 0.45), 2)
			_show_swing(item_id, hit_pos)
		_ItemTypes.WeaponKind.RANGED:
			show_hit_marker(hit_pos + Vector3(0.0, _vox(0.1), 0.0), Color(0.65, 0.82, 1.0), _vox(0.18))
			_spawn_burst(hit_pos + Vector3(0.0, _vox(0.225), 0.0), Color(0.65, 0.82, 1.0), 1)


func _on_entity_hit(target: Node, damage: float, _item_id: String) -> void:
	if target == null:
		return
	var world_pos: Vector3 = target.global_position
	if target.has_method("get_combat_center"):
		world_pos = target.get_combat_center()
	var radius := _vox(0.225)
	if target.has_method("get_combat_radius"):
		radius = maxf(float(target.get_combat_radius()), _vox(0.125))
	_show_damage_at(world_pos + Vector3(0.0, _vox(0.3), 0.0), damage, Color(1.0, 0.55, 0.45))
	show_hit_marker(world_pos, Color(1.0, 0.45, 0.35), radius)
	if target.has_method("_flash_hit"):
		target._flash_hit()
	var weight := _Juice.weight_for_item(_item_id, damage)
	_Juice.request_hit_stop(_Juice.seconds_for_weight(weight), get_tree())
	_Juice.request_shake(0.42 if weight >= 0.9 else 0.1)
	_sfx("hit_heavy" if weight >= 0.9 else "hit_light", world_pos)
	if "health" in target and float(target.health) <= 0.0 and target.is_in_group("crystal_enemy"):
		_spawn_burst(world_pos + Vector3(0.0, _vox(0.25), 0.0), Color(1.0, 0.55, 0.95), 3)


func _on_crystal_mass_hit(world_pos: Vector3, amount: float, broken: bool) -> void:
	var world_hit := _WorldVisualCoords.column_to_world_pos(world_pos.x, world_pos.y, world_pos.z)
	var heavy := broken or amount >= 1.5
	if heavy:
		_pool_burst(_VfxPool.Kind.SHATTER, world_hit, Color(0.9, 0.45, 1.0), 1.15 if broken else 0.85)
		_sfx("crystal_shatter" if broken else "crystal_crackle", world_hit)
		if broken:
			_Juice.request_shake(0.22)
	else:
		_sfx("crystal_crackle", world_hit)
	if not enabled:
		return
	var tint := Color(0.78, 0.35, 1.0)
	# Depth chips are fractions of a layer. Integer damage numbers would read as 0.
	var text := "BREAK" if broken else "-%.1f" % amount
	_show_text_at(world_pos + Vector3(0.0, _vox(0.35), 0.0), text, tint)
	show_hit_marker(world_pos, tint, _vox(0.28))
	if broken:
		_spawn_break_shards(world_pos, Color(0.9, 0.45, 1.0), 5)
		_spawn_burst(world_pos + Vector3(0.0, _vox(0.2), 0.0), tint, 4)
	else:
		_spawn_burst(world_pos + Vector3(0.0, _vox(0.15), 0.0), tint, 2)


func _show_text_at(world_pos: Vector3, text: String, color: Color) -> void:
	for i in _label_slots.size():
		if _label_slots[i].active:
			continue
		var label: Label3D = _label_pool[i]
		label.text = text
		label.modulate = color
		label.global_position = world_pos
		label.visible = true
		_label_slots[i] = {"active": true, "time": _quality.damage_number_lifetime}
		return


func _on_spawn_damaged(spawn: CrystalSpawnPoint, amount: float) -> void:
	if spawn == null:
		return
	var pos := _spawn_world_pos(spawn)
	_show_damage_at(pos + Vector3(0.0, 2.0, 0.0), amount, Color(0.95, 0.55, 1.0))
	_pulse_spawn_marker(spawn, false)


func _on_spawn_destroyed(spawn: CrystalSpawnPoint) -> void:
	if spawn == null:
		return
	var pos := _spawn_world_pos(spawn)
	var tint := Color(1.0, 0.35, 0.95) if spawn.is_boss else Color(0.75, 0.4, 1.0)
	_spawn_burst(pos + Vector3(0.0, 1.5, 0.0), tint, 6 if spawn.is_boss else 4)
	_pool_burst(_VfxPool.Kind.SPAWN_DEATH, pos + Vector3(0.0, _vox(0.4), 0.0), tint, 1.4 if spawn.is_boss else 1.0)
	_sfx("spawn_destroyed", pos)
	_Juice.request_shake(0.7 if spawn.is_boss else 0.35)
	if spawn.is_boss:
		_boss_ring.visible = false


func _on_phase_changed(phase: int) -> void:
	if phase == _GameManager.Phase.ASSAULT:
		_update_boss_ring_target()


func _on_run_state_changed(state: int) -> void:
	if state == _GameManager.RunState.WON:
		_play_victory_flash()


func _play_victory_flash() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player:
		_victory_flash.global_position = player.global_position + Vector3(0.0, 2.5, -4.0)
	_victory_flash.visible = true
	if _victory_flash.material_override is StandardMaterial3D:
		(_victory_flash.material_override as StandardMaterial3D).albedo_color.a = 0.85
	_victory_flash.set_meta("flash_time", 2.5)


func _spawn_world_pos(spawn: CrystalSpawnPoint) -> Vector3:
	var col_x := float(spawn.world_pos.x) + 0.5
	var col_z := float(spawn.world_pos.y) + 0.5
	var world_node = get_tree().get_first_node_in_group("world") as InfiniteNoiseWorld
	var chunk_mgr = get_tree().get_first_node_in_group("chunk_manager")
	var y := 0.0
	if world_node:
		var entry = null
		if chunk_mgr and chunk_mgr.has_method("get_ramp_entry_at_world"):
			entry = chunk_mgr.get_ramp_entry_at_world(col_x, col_z)
		if entry != null:
			y = TerrainRamps.walkable_height_from_entry(world_node, col_x, col_z, entry)
		else:
			y = TerrainRamps.walkable_height(world_node, col_x, col_z)
	return _WorldVisualCoords.column_to_world_pos(col_x, y, col_z)


func _pulse_spawn_marker(spawn: CrystalSpawnPoint, _destroyed: bool) -> void:
	if _crystal == null or spawn == null:
		return
	if not _crystal.has_method("get_spawn_marker"):
		return
	var marker: Node3D = _crystal.get_spawn_marker(spawn.id)
	if marker == null or not marker.material_override is StandardMaterial3D:
		return
	var mat := (marker.material_override as StandardMaterial3D).duplicate()
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 1.0)
	mat.emission_energy_multiplier = 2.0
	if _textures.has("hit_flash"):
		mat.albedo_texture = _textures.hit_flash
	marker.material_override = mat
	marker.set_meta("flash_time", 0.2)


func _update_boss_ring_target() -> void:
	if _crystal == null or not _crystal.has_method("get_spawn_progress"):
		return
	var prog: Dictionary = _crystal.get_spawn_progress()
	if not bool(prog.get("boss_active", false)):
		_boss_ring.visible = false
		return
	for spawn in _crystal.get_active_spawns():
		if spawn.is_boss:
			_boss_ring.global_position = _spawn_world_pos(spawn) + Vector3(0.0, 2.8, 0.0)
			_boss_ring.visible = true
			return


func _update_labels(delta: float) -> void:
	for i in _label_slots.size():
		if not _label_slots[i].active:
			continue
		var slot: Dictionary = _label_slots[i]
		slot.time = float(slot.time) - delta
		var label: Label3D = _label_pool[i]
		label.global_position.y += delta * 1.2
		label.modulate.a = clampf(float(slot.time) / _quality.damage_number_lifetime, 0.0, 1.0)
		if slot.time <= 0.0:
			label.visible = false
			slot.active = false
		_label_slots[i] = slot


func _update_bursts(delta: float) -> void:
	var kept: Array[Dictionary] = []
	for b in _bursts:
		var anchor: Node3D = b.get("anchor")
		var sprite: Sprite3D = b.get("sprite")
		if not is_instance_valid(anchor):
			continue
		var life: float = float(b.life) - delta
		if life <= 0.0:
			anchor.queue_free()
			continue
		var vel: Vector3 = b.get("vel", Vector3.ZERO)
		anchor.global_position += vel * delta
		if not bool(b.get("place", false)):
			b.vel = vel + Vector3(0.0, -2.5, 0.0) * delta
		else:
			b.vel = vel * 0.92
		var fade := clampf(life / 0.5, 0.0, 1.0)
		if is_instance_valid(sprite):
			sprite.modulate.a = fade
			if sprite.material_override is StandardMaterial3D:
				(sprite.material_override as StandardMaterial3D).albedo_color.a = fade
		var mesh_i: MeshInstance3D = b.get("mesh")
		if is_instance_valid(mesh_i) and mesh_i.material_override is StandardMaterial3D:
			var mat := mesh_i.material_override as StandardMaterial3D
			mat.albedo_color.a = 0.55 * fade
			mat.emission_energy_multiplier = 1.6 * fade
		if bool(b.get("break_shard", false)) and is_instance_valid(mesh_i):
			var spin := float(b.get("spin", 4.0))
			mesh_i.rotate_y(spin * delta)
			mesh_i.rotate_x(spin * 0.55 * delta)
			var shrink := clampf(life / 0.45, 0.2, 1.0)
			mesh_i.scale = Vector3.ONE * shrink
		if bool(b.get("hit_marker", false)) and is_instance_valid(mesh_i):
			var grow := 1.0 + (1.0 - clampf(life / 0.24, 0.0, 1.0)) * 0.35
			mesh_i.scale = Vector3(grow, 1.0, grow)
		var tag: Label3D = b.get("tag")
		if is_instance_valid(tag):
			tag.modulate.a = fade
		b.life = life
		kept.append(b)
	_bursts = kept


func _update_spawn_marker_flashes(delta: float) -> void:
	if _crystal == null or not _crystal.has_method("get_spawn_marker_ids"):
		return
	for sid in _crystal.get_spawn_marker_ids():
		var marker: Node3D = _crystal.get_spawn_marker(sid)
		if marker == null or not marker.has_meta("flash_time"):
			continue
		var t: float = float(marker.get_meta("flash_time")) - delta
		marker.set_meta("flash_time", t)
		if t <= 0.0:
			marker.remove_meta("flash_time")
			if marker.material_override is StandardMaterial3D:
				(marker.material_override as StandardMaterial3D).emission_energy_multiplier = 0.0


func _update_boss_ring(delta: float) -> void:
	if not _boss_ring.visible:
		return
	_boss_ring.rotate_y(delta * 1.4)
	var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.004)
	if _boss_ring.material_override is StandardMaterial3D:
		var m := _boss_ring.material_override as StandardMaterial3D
		m.albedo_color.a = 0.45 + pulse * 0.35


func _update_victory_flash(delta: float) -> void:
	if not _victory_flash.visible:
		return
	var t: float = float(_victory_flash.get_meta("flash_time", 0.0)) - delta
	_victory_flash.set_meta("flash_time", t)
	if _victory_flash.material_override is StandardMaterial3D:
		(_victory_flash.material_override as StandardMaterial3D).albedo_color.a = clampf(t / 2.0, 0.0, 0.9)
	if t <= 0.0:
		_victory_flash.visible = false


func _ensure_pool() -> void:
	if _pool != null and is_instance_valid(_pool):
		return
	_pool = _VfxPool.new()
	_pool.name = "VfxPool"
	add_child(_pool)
	if _dissolve_root == null:
		_dissolve_root = Node3D.new()
		_dissolve_root.name = "DeathDissolves"
		add_child(_dissolve_root)


func _burst_dig_dust(col_pos: Vector3) -> void:
	var ws = _WorldSettings.get_active()
	var y: float = col_pos.y + ws.layer_height() * 0.2
	var pos := _WorldVisualCoords.column_to_world_pos(floorf(col_pos.x) + 0.5, y, floorf(col_pos.z) + 0.5)
	_pool_burst(_VfxPool.Kind.DUST, pos, Color(0.72, 0.55, 0.32))


func splash_at(world_pos: Vector3) -> void:
	_pool_burst(_VfxPool.Kind.SPLASH, world_pos, Color(0.55, 0.78, 0.95))
	_sfx("water_splash", world_pos)


func burst_bomb(world_pos: Vector3) -> void:
	_pool_burst(_VfxPool.Kind.SHATTER, world_pos, Color(0.85, 0.45, 1.0), 1.35)
	_pool_burst(_VfxPool.Kind.DUST, world_pos, Color(0.7, 0.55, 0.8), 1.0)
	_Juice.request_hit_stop(0.08, get_tree())
	_Juice.request_shake(0.62)


func pulse_corruption(cell: Vector2i, world_y: float) -> void:
	var pos := _WorldVisualCoords.column_to_world_pos(float(cell.x) + 0.5, world_y + _vox(0.2), float(cell.y) + 0.5)
	if _pool_burst(_VfxPool.Kind.CORRUPT, pos, Color(0.62, 0.28, 0.95), 0.7):
		_sfx("corruption_spread", pos)


func _pool_burst(kind: int, pos: Vector3, tint: Color, scale: float = 1.0) -> bool:
	_ensure_pool()
	return _pool.burst(kind, pos, tint, scale)


func _show_swing(item_id: String, hit_pos: Vector3) -> void:
	_ensure_pool()
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	var origin := hit_pos
	if _player:
		origin = _player.global_position + Vector3(0.0, _vox(0.7), 0.0)
	var forward := hit_pos - origin
	if forward.length() > 48.0 and _player and "locked_yaw_degrees" in _player:
		var yaw := deg_to_rad(float(_player.locked_yaw_degrees))
		forward = Vector3(sin(yaw), 0.0, cos(yaw))
	_pool.show_swing(item_id, origin, forward)


func adopt_death_visual(visual: Node3D) -> void:
	if visual == null or not is_instance_valid(visual):
		return
	_ensure_pool()
	var parent := visual.get_parent()
	var xf := visual.global_transform
	if parent:
		parent.remove_child(visual)
	if _dissolves.size() >= _DISSOLVE_CAP:
		visual.queue_free()
		return
	_dissolve_root.add_child(visual)
	visual.global_transform = xf
	_prime_fade(visual)
	_dissolves.append({
		"node": visual,
		"life": _DISSOLVE_SEC,
		"scale": visual.scale,
	})


func _prime_fade(node: Node) -> void:
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		var mat := gi.material_override
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for child in node.get_children():
		_prime_fade(child)


func _set_fade(node: Node, alpha: float) -> void:
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		var mat := gi.material_override
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			var c := sm.albedo_color
			c.a = alpha
			sm.albedo_color = c
		elif node is Sprite3D:
			var spr := node as Sprite3D
			var mod := spr.modulate
			mod.a = alpha
			spr.modulate = mod
	for child in node.get_children():
		_set_fade(child, alpha)


func _update_dissolves(delta: float) -> void:
	var kept: Array[Dictionary] = []
	for entry in _dissolves:
		var node: Node3D = entry.get("node")
		if not is_instance_valid(node):
			continue
		var life := float(entry.get("life", 0.0)) - delta
		if life <= 0.0:
			node.queue_free()
			continue
		var k := clampf(life / _DISSOLVE_SEC, 0.0, 1.0)
		var base: Vector3 = entry.get("scale", Vector3.ONE)
		node.scale = base * maxf(k, 0.05)
		_set_fade(node, k)
		entry["life"] = life
		kept.append(entry)
	_dissolves = kept


func _sfx(id: String, at: Variant = null) -> void:
	if not is_instance_valid(_audio):
		_audio = get_node_or_null("/root/AudioManager")
	if _audio == null or not _audio.has_method("play_sfx"):
		return
	if at is Vector3:
		_audio.play_sfx(id, at)
	else:
		_audio.play_sfx(id)