extends SceneTree
## Regression: TargetHighlight shows red attack box via camera-forward resolve (no mouse).


const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _SmokeProbeHelpers = preload("res://scripts/smoke_probe_helpers.gd")
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var highlight_src := (load("res://player/target_highlight.gd") as GDScript).source_code
	if "resolve_action" not in highlight_src:
		push_error("target_highlight must call resolve_action")
		failed = true
	else:
		print("OK target_highlight uses resolve_action")

	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		push_error("main scene load failed")
		_ProbeExit.finish_tree(self, 1, "Forward highlight FAILED")
		return

	var game: Node = main_packed.instantiate()
	root.add_child(game)

	var player: Node = null
	var chunk_manager: ChunkManager = null
	var world: InfiniteNoiseWorld = null
	var weapon: Node = null

	for _attempt in 600:
		player = get_first_node_in_group("player")
		chunk_manager = get_first_node_in_group("chunk_manager")
		world = get_first_node_in_group("world")
		weapon = player.get_node_or_null("WeaponController") if player else null
		if (
			player != null and chunk_manager != null and world != null and weapon != null
			and bool(player.get("world_ready"))
		):
			break
		await process_frame

	if player == null:
		push_error("bootstrap timeout")
		_ProbeExit.finish_tree(self, 1, "Forward highlight FAILED")
		return

	for _w in 60:
		await process_frame

	var highlight: Node = player.get_node_or_null("TargetHighlight")
	if highlight == null:
		push_error("player missing TargetHighlight child")
		failed = true
	else:
		var inv = player.get("inventory")
		if inv:
			inv.set_slot(0, "wooden_sword", 1)
		if weapon.has_method("set_active_hotbar_index"):
			weapon.set_active_hotbar_index(0)
		var sword_def: Dictionary = _ItemTypes.get_def("wooden_sword")
		var sword_range: float = float(sword_def.get("range", 2.0)) if sword_def else 2.0
		var player_col := Vector2i(
			floori(float(player.get("voxel_position").x)),
			floori(float(player.get("voxel_position").z))
		)
		var solid_cells: Array[Vector2i] = []
		for radius in range(1, 10):
			for dx in range(-radius, radius + 1):
				for dz in range(-radius, radius + 1):
					if maxi(absi(dx), absi(dz)) != radius:
						continue
					var wx: int = player_col.x + dx
					var wz: int = player_col.y + dz
					if _ActionTargeting._is_solid_column(world, chunk_manager, wx, wz):
						solid_cells.append(Vector2i(wx, wz))
		var highlight_ok := false
		for cell in solid_cells:
			_SmokeProbeHelpers.position_player_for_forward_dig(
				player, world, chunk_manager, cell.x, cell.y, sword_range, &"attack"
			)
			_SmokeProbeHelpers.clear_mouse_offscreen(player)
			for _w in 12:
				await process_frame
			var atk_info: Dictionary = _ActionTargeting.resolve_action(
				player, world, chunk_manager, sword_range, false
			)
			if not atk_info.get("valid", false) or atk_info.get("mode", &"") != &"attack":
				continue
			for _w in 4:
				await process_frame
			var box: MeshInstance3D = highlight.get_node_or_null("TargetBox") as MeshInstance3D
			if box == null or not box.visible:
				continue
			if not (box.material_override is StandardMaterial3D):
				continue
			var mat_col: Color = (box.material_override as StandardMaterial3D).albedo_color
			if mat_col.r < 0.75 or mat_col.g > 0.45:
				continue
			print(
				"OK forward attack highlight visible cell=%s color=%s"
				% [atk_info.get("cell"), mat_col]
			)
			highlight_ok = true
			break
		if not highlight_ok:
			push_error("forward attack highlight never became visible red without mouse")
			failed = true

	if failed:
		_ProbeExit.finish_tree(self, 1, "Forward highlight FAILED")
		return
	_ProbeExit.finish_tree(self, 0, "All forward highlight tests OK")