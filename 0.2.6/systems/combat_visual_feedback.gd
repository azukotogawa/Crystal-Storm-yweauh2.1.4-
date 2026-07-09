class_name CombatVisualFeedback
extends Node3D

const _PerformanceQualityConfig = preload("res://config/performance_quality_config.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _GameManager = preload("res://game/game_manager.gd")
const _WorldVisualCoords = preload("res://helpers/world_visual_coords.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")

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


func _enter_tree() -> void:
	add_to_group("combat_visual_feedback")


func _ready() -> void:
	_ensure_visual_roots()
	_build_label_pool()
	call_deferred("_load_textures")
	_build_indicators()
	call_deferred("_connect_signals")


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
	reload_textures()


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
		if registry.has_method("preload_game_bundle"):
			registry.preload_game_bundle()
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
	torus.inner_radius = 0.9
	torus.outer_radius = 1.15
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
	quad.size = Vector2(6.0, 3.0)
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

	var player = get_tree().get_first_node_in_group("player")
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
	_update_labels(delta)
	_update_bursts(delta)
	_update_spawn_marker_flashes(delta)
	_update_boss_ring(delta)
	_update_victory_flash(delta)


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


func _column_to_world(col: Vector3) -> Vector3:
	var ws = _WorldSettings.get_active()
	return Vector3(ws.column_to_world(col.x), col.y, ws.column_to_world(col.z))


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
	_spawn_burst(pos + Vector3(0.0, 0.5, 0.0), Color(0.85, 0.55, 0.35), 3)


func _on_weapon_attacked(item_id: String, hit_pos: Vector3) -> void:
	if not enabled:
		return
	var def := _ItemTypes.get_def(item_id)
	if def.is_empty():
		return
	var kind := int(def.get("weapon_kind", _ItemTypes.WeaponKind.MELEE))
	match kind:
		_ItemTypes.WeaponKind.MELEE, _ItemTypes.WeaponKind.DIG:
			_spawn_burst(hit_pos + Vector3(0.0, 0.35, 0.0), Color(1.0, 0.88, 0.45), 2)
		_ItemTypes.WeaponKind.RANGED:
			_spawn_burst(hit_pos + Vector3(0.0, 0.45, 0.0), Color(0.65, 0.82, 1.0), 1)


func _on_entity_hit(target: Node, damage: float, _item_id: String) -> void:
	if target == null:
		return
	var col: Vector3 = target.global_position
	if target.has_method("get_combat_center"):
		col = target.get_combat_center()
	show_damage_column(col, damage, Color(1.0, 0.55, 0.45))
	if target.has_method("_flash_hit"):
		target._flash_hit()
	if "health" in target and float(target.health) <= 0.0 and target.is_in_group("crystal_enemy"):
		_spawn_burst(_column_to_world(col) + Vector3(0.0, 0.5, 0.0), Color(1.0, 0.55, 0.95), 3)


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
		anchor.global_position += Vector3(b.vel) * delta
		b.vel = Vector3(b.vel) + Vector3(0.0, -2.5, 0.0) * delta
		var fade := clampf(life / 0.5, 0.0, 1.0)
		if is_instance_valid(sprite):
			sprite.modulate.a = fade
			if sprite.material_override is StandardMaterial3D:
				(sprite.material_override as StandardMaterial3D).albedo_color.a = fade
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