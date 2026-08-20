extends SceneTree
## World Borders sprint: oceans stop player, mountains block, crystal stays in bounds,
## map edge styling is intentional.
## Usage: godot --headless -s scripts/verify_world_borders.gd


const _WorldBorder = preload("res://helpers/world_border.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _CrystalSimSnapshot = preload("res://crystal/crystal_sim_snapshot.gd")
const _TopographicalMapBuilder = preload("res://systems/topographical_map_builder.gd")
const _TopographicalMapConfig = preload("res://config/topographical_map_config.gd")


var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	_test_playable_rect()
	_test_ocean_stops_player()
	_test_mountains_block()
	_test_crystal_bounds()
	_test_map_edge_style()
	_test_border_height_intentional()

	if _failed == 0:
		print("All world border tests OK")
		quit(0)
	else:
		push_error("verify_world_borders: %d failure(s)" % _failed)
		quit(1)


func _test_playable_rect() -> void:
	if not _WorldBorder.is_playable(0.0, 0.0):
		_fail("origin must be playable")
	if not _WorldBorder.is_playable(float(_WorldBorder.PLAYABLE_HALF_X), 0.0):
		_fail("edge cell on half-x must still be playable")
	if _WorldBorder.is_playable(float(_WorldBorder.PLAYABLE_HALF_X) + 2.0, 0.0):
		_fail("past ocean edge must not be playable")
	if _WorldBorder.is_playable(0.0, float(_WorldBorder.PLAYABLE_HALF_Z) + 2.0):
		_fail("past mountain edge must not be playable")
	else:
		print("OK playable rectangle half=%d" % _WorldBorder.PLAYABLE_HALF_X)


func _test_ocean_stops_player() -> void:
	# Any ocean tile blocks regardless of zone.
	if not _WorldBorder.blocks_player_at(0.0, 0.0, _VoxelTypes.OCEAN):
		_fail("OCEAN tile must stop player even inside playable (coast/sea)")
	if not _WorldBorder.blocks_player_at(0.0, 0.0, _VoxelTypes.OCEAN2):
		_fail("OCEAN2 must stop player")
	if not _WorldBorder.blocks_player_at(0.0, 0.0, _VoxelTypes.OCEAN3):
		_fail("OCEAN3 must stop player")

	# Border ocean band blocks early in transition (not only deep abyss).
	var ocean_x: float = float(_WorldBorder.PLAYABLE_HALF_X) + 40.0
	if not _WorldBorder.blocks_player_movement(ocean_x, 0.0):
		_fail("ocean border transition should block player at +40")
	if _WorldBorder.blocks_player_movement(float(_WorldBorder.PLAYABLE_HALF_X) - 8.0, 0.0):
		_fail("interior near ocean edge should remain walkable")
	else:
		print("OK oceans stop player (tiles + border band)")


func _test_mountains_block() -> void:
	var mtn_z: float = float(_WorldBorder.PLAYABLE_HALF_Z) + 30.0
	if not _WorldBorder.blocks_player_movement(0.0, mtn_z):
		_fail("mountain border transition should block at +30")
	# Border mountain tiles block when in border zone
	if not _WorldBorder.blocks_player_at(0.0, mtn_z, _VoxelTypes.MOUNTAIN3):
		_fail("border mountain tile must block traversal")
	# Interior highland mountain remains walkable (not border zone)
	if _WorldBorder.blocks_player_at(10.0, 10.0, _VoxelTypes.MOUNTAIN):
		_fail("interior mountain tile must not hard-block")
	else:
		print("OK mountains block at border, interior climbable")


func _test_crystal_bounds() -> void:
	if _WorldBorder.allows_crystal(float(_WorldBorder.PLAYABLE_HALF_X) + 1.0, 0.0):
		_fail("crystal must not be allowed outside playable X")
	if _WorldBorder.allows_crystal(0.0, float(_WorldBorder.PLAYABLE_HALF_Z) + 1.0):
		_fail("crystal must not be allowed outside playable Z")
	if not _WorldBorder.allows_crystal(0.0, 0.0):
		_fail("crystal allowed at origin")

	var snap := _CrystalSimSnapshot.new()
	snap.sim_loaded_chunks_only = false
	if snap.is_cell_active(Vector2i(_WorldBorder.PLAYABLE_HALF_X + 5, 0)):
		_fail("snapshot must inactive cells outside playable")
	if not snap.is_cell_active(Vector2i(3, 4)):
		_fail("snapshot must active interior cells when loaded-only off")
	else:
		print("OK crystal respects playable boundaries")


func _test_map_edge_style() -> void:
	var rim_in: float = _WorldBorder.map_edge_rim_strength(
		float(_WorldBorder.PLAYABLE_HALF_X) - 2.0, 0.0, 8.0
	)
	var rim_out: float = _WorldBorder.map_edge_rim_strength(
		float(_WorldBorder.PLAYABLE_HALF_X) + 20.0, 0.0, 8.0
	)
	var rim_center: float = _WorldBorder.map_edge_rim_strength(0.0, 0.0, 8.0)
	if rim_center > 0.05:
		_fail("map center should not have edge rim")
	if rim_in < 0.4:
		_fail("near playable edge rim should be strong in=%.3f" % rim_in)
	if rim_out < 0.55:
		_fail("outside border rim should be strong out=%.3f" % rim_out)

	# Builder applies border style without crash
	var cfg := _TopographicalMapConfig.create_default()
	var c_ocean: Color = _TopographicalMapBuilder._apply_border_map_style(
		Color(0.5, 0.7, 0.3), _WorldBorder.PLAYABLE_HALF_X + 50, 0, _VoxelTypes.OCEAN2, cfg
	)
	var c_center: Color = _TopographicalMapBuilder._apply_border_map_style(
		Color(0.5, 0.7, 0.3), 0, 0, _VoxelTypes.GRASSLAND, cfg
	)
	if is_equal_approx(c_ocean.r, c_center.r) and is_equal_approx(c_ocean.b, c_center.b):
		_fail("ocean border map color should differ from interior")
	else:
		print("OK map edge rim intentional ocean_b=%.2f center_b=%.2f" % [c_ocean.b, c_center.b])


func _test_border_height_intentional() -> void:
	var playable_h := 40.0
	var ocean_info: Dictionary = _WorldBorder.zone_info(float(_WorldBorder.PLAYABLE_HALF_X) + 80.0, 0.0)
	var ocean_h: float = _WorldBorder.apply_border_height(
		float(_WorldBorder.PLAYABLE_HALF_X) + 80.0, 0.0, playable_h, ocean_info
	)
	var mtn_info: Dictionary = _WorldBorder.zone_info(0.0, float(_WorldBorder.PLAYABLE_HALF_Z) + 80.0)
	var mtn_h: float = _WorldBorder.apply_border_height(
		0.0, float(_WorldBorder.PLAYABLE_HALF_Z) + 80.0, playable_h, mtn_info
	)
	if ocean_h >= playable_h - 2.0:
		_fail("ocean border height should sink below interior got %.1f" % ocean_h)
	if mtn_h <= playable_h + 5.0:
		_fail("mountain border height should rise above interior got %.1f" % mtn_h)
	else:
		print("OK border heights ocean=%.1f mountain=%.1f (intentional edge)" % [ocean_h, mtn_h])
