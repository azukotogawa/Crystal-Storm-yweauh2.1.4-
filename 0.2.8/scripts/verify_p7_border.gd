extends SceneTree

const _B = preload("res://helpers/world_border.gd")
const _Body = preload("res://player/player_body_mesh.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _VoxelFloorProbe = preload("res://player/voxel_floor_probe.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const DT := 1.0 / 60.0
var _bad := 0


class _Driver extends Player:
	func _ready() -> void:
		pass


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_TerrainEdits.reset()
	var world := InfiniteNoiseWorld.new()
	world.world_seed = 12349
	var hx := float(_B.PLAYABLE_HALF_X)
	var hz := float(_B.PLAYABLE_HALF_Z)
	var sides := {
		"+x": [Vector2(1, 0), Vector2(hx, 37.0)],
		"-x": [Vector2(-1, 0), Vector2(-hx, -211.0)],
		"+z": [Vector2(0, 1), Vector2(149.0, hz)],
		"-z": [Vector2(0, -1), Vector2(-83.0, -hz)],
		"c++": [Vector2(0.7071, 0.7071), Vector2(hx, hz)],
		"c+-": [Vector2(0.7071, -0.7071), Vector2(hx, -hz)],
		"c-+": [Vector2(-0.7071, 0.7071), Vector2(-hx, hz)],
		"c--": [Vector2(-0.7071, -0.7071), Vector2(-hx, -hz)],
	}
	for k in sides:
		var dir: Vector2 = sides[k][0]
		var edge: Vector2 = sides[k][1]
		var row := []
		var first_block := INF
		var holes := 0
		var seen_block := false
		for d in range(-16, 400, 2):
			var p := edge + dir * float(d)
			var h := world.get_surface_height_uncached(p.x, p.y)
			var t := world.get_tile_type_uncached(p.x, p.y)
			var blk := _B.blocks_player_at(p.x, p.y, t)
			if d < 0 and blk and not _B.is_playable(p.x, p.y):
				pass
			if blk and first_block == INF:
				first_block = float(d)
			if seen_block and not blk:
				holes += 1
			seen_block = seen_block or blk
			if d in [-16, 0, 16, 40, 120, 240, 384]:
				row.append("d%d:h%.0f/%s%s" % [d, h, _B.border_biome_name(p.x, p.y) if not _B.is_playable(p.x, p.y) else "in", "/X" if blk else ""])
		var ok := first_block <= 40.0 and holes == 0
		if not ok:
			_bad += 1
		print("P7_H_EDGE %s first_block=%.0f holes=%d %s %s" % [k, first_block, holes, " ".join(row), "OK" if ok else "BAD"])
	var player := _make_player(world)
	var probe_dirs := {}
	for a in ["move_right", "move_left", "move_forward", "move_back"]:
		_place(player, Vector2(20.5, 20.5))
		var s := player.voxel_position
		Input.action_press(a)
		_tick(player, 20)
		Input.action_release(a)
		_tick(player, 10)
		var dv := Vector2(player.voxel_position.x - s.x, player.voxel_position.z - s.z)
		probe_dirs[a] = dv.normalized().round()
	var walks := []
	for a in probe_dirs:
		walks.append([[a], probe_dirs[a]])
	walks.append([["move_right", "move_forward"], probe_dirs["move_right"] + probe_dirs["move_forward"]])
	walks.append([["move_left", "move_back"], probe_dirs["move_left"] + probe_dirs["move_back"]])
	for w in walks:
		var acts: Array = w[0]
		var dir: Vector2 = w[1]
		var start := Vector2(dir.x * (hx - 12.0), dir.y * (hz - 12.0))
		if absf(dir.x) < 0.5:
			start.x = 61.0
		if absf(dir.y) < 0.5:
			start.y = -47.0
		_place(player, start)
		for a in acts:
			Input.action_press(a)
		Input.action_press("sprint")
		var max_out := 0.0
		var last := Vector2.ZERO
		var still := 0
		for i in 900:
			_tick(player, 1)
			var p := Vector2(player.voxel_position.x, player.voxel_position.z)
			max_out = maxf(max_out, _B.outside_distance(p.x, p.y))
			still = still + 1 if p.distance_to(last) < 0.002 else 0
			last = p
		for a in acts:
			Input.action_release(a)
		Input.action_release("sprint")
		var walked := last.distance_to(start)
		var ok := walked > 8.0 and max_out <= 40.0 and still >= 60
		if not ok:
			_bad += 1
		print("P7_H_WALK %s dir=%s start=%s end=(%.1f,%.1f) walked=%.1f max_outside=%.1f stopped_frames=%d %s" % ["+".join(acts), dir, start, last.x, last.y, walked, max_out, still, "OK" if ok else "BAD"])
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for z in range(-96, 96, 3):
		for x in range(-96, 96, 3):
			ctx.update(PackedFloat32Array([world.get_surface_height_uncached(float(x), float(z)), float(world.get_tile_type_uncached(float(x), float(z)))]).to_byte_array())
	print("P7_H_HASH seed=12349 inner_hash=%s" % ctx.finish().hex_encode().substr(0, 16))
	print("P7_H_RESULT bad=%d %s" % [_bad, "OK" if _bad == 0 else "BAD"])
	quit(0 if _bad == 0 else 1)


func _place(player: Player, p: Vector2) -> void:
	var feet: float = player._floor_probe.sample_walkable_feet(p.x, p.y)
	player.voxel_position = Vector3(p.x, feet, p.y)
	player.velocity = Vector3.ZERO
	player.current_state = player.State.IDLE


func _make_player(world) -> Player:
	var probe := _VoxelFloorProbe.new()
	var chunks := ChunkManager.new()
	chunks.world = world
	probe.configure(world, chunks, null)
	var player := _Driver.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	player.add_child(mesh)
	player.player_mesh = mesh
	var ws = _WorldSettings.get_active()
	_Body.apply_to(mesh, ws.player_height(), ws.player_radius())
	player.world = world
	player.chunk_manager = chunks
	player._floor_probe = probe
	player.world_ready = true
	player.locked_yaw_degrees = 0.0
	player.set_physics_process(false)
	player.set_process(false)
	root.add_child(player)
	return player


func _tick(player: Player, frames: int) -> void:
	for _i in frames:
		player._process(DT)
		player._physics_process(DT)