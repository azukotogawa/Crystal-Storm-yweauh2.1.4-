extends SceneTree

const _Loader = preload("res://helpers/crystal_voxel_loader.gd")
const _Body = preload("res://player/player_body_mesh.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _View = preload("res://systems/held_item_view.gd")

const _DIR := "res://assets/voxel/items/"
const _MODELS := [
	"pickaxe", "axe", "shovel", "wooden_sword", "spear", "shortbow", "sling", "crystal_hammer", "crystal_shard",
]
const _HELD := {
	"pickaxe": "stone_pick",
	"axe": "axe",
	"shovel": "shovel",
	"wooden_sword": "wooden_sword",
	"spear": "spear",
	"shortbow": "shortbow",
	"sling": "sling",
	"crystal_hammer": "crystal_hammer",
	"crystal_shard": "crystal_shard",
}

var _failed := false
var _allowed := {}


class _Host extends Node3D:
	var player_mesh: MeshInstance3D


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed = true
	print("FAIL %s" % msg)


func _run() -> void:
	_load_palette()
	var ws = _WorldSettings.get_active()
	var need_h: float = ws.player_height() * 0.85
	var quads_line := ""
	for name in _MODELS:
		var path: String = _DIR + name + ".json"
		var model: CrystalVoxelModel = _Loader.load_model(path)
		if model == null:
			_fail("load %s" % name)
			continue
		if model.vpb != 16 or model.base_cell != 2 or model.scale_mode != "terrain_block":
			_fail("%s grid" % name)
		if model.palette.size() > 16:
			_fail("%s palette size" % name)
		for col in model.palette:
			var key := "%d,%d,%d" % [int(round(col.r * 255.0)), int(round(col.g * 255.0)), int(round(col.b * 255.0))]
			if not _allowed.has(key):
				_fail("%s color %s" % [name, key])
		var cells: Array = model.cells_for("")
		var occ := {}
		var min_y := 9999
		var max_y := -1
		for cell in cells:
			var c: Vector4i = cell
			if c.x < 0 or c.y < 0 or c.z < 0 or c.x >= model.size.x or c.y >= model.size.y or c.z >= model.size.z:
				_fail("%s cell outside size" % name)
			occ[Vector3i(c.x, c.y, c.z)] = true
			min_y = mini(min_y, c.y)
			max_y = maxi(max_y, c.y)
		var interior := 0
		for key in occ.keys():
			var at: Vector3i = key
			var n6 := 0
			for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				if occ.has(at + d):
					n6 += 1
			if n6 == 6:
				interior += 1
			var origin := Vector3i(at.x - posmod(at.x, 2), at.y - posmod(at.y, 2), at.z - posmod(at.z, 2))
			var full := true
			for dy in 2:
				for dz in 2:
					for dx in 2:
						if not occ.has(origin + Vector3i(dx, dy, dz)):
							full = false
			if not full and n6 == 6:
				_fail("%s buried detail" % name)
		if interior > 0:
			_fail("%s interior %d" % [name, interior])
		var near := false
		for key2 in occ.keys():
			var p: Vector3i = key2
			if Vector3(p).distance_to(model.pivot) <= 1.75:
				near = true
				break
		if not near:
			_fail("%s pivot is not on the grip" % name)
		var built := _Loader.rig_for(path)
		var quads := int(built.get("quads", 0))
		var mesh: ArrayMesh = built.get("mesh", null)
		if mesh == null or mesh.get_surface_count() != 1:
			_fail("%s mesh surfaces" % name)
		elif quads > 500:
			_fail("%s quads %d" % [name, quads])
		var span: float = float(max_y - min_y + 1) * ws.voxel_scale / float(model.vpb)
		if name != "crystal_shard" and span < need_h:
			_fail("%s height %.2f" % [name, span])
		quads_line += "%s=%d " % [name, quads]
		print("QUAD %s voxels=%d quads=%d height=%.2f" % [name, cells.size(), quads, span])
	print("QUADS %s" % quads_line.strip_edges())
	await _check_hand(ws)
	if _failed:
		print("HELD VOXEL ITEMS FAIL")
		quit(1)
		return
	print("HELD VOXEL ITEMS OK")
	quit(0)


func _load_palette() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/voxel/palette.json"))
	for entry in parsed.get("colors", []):
		var rgb = entry.get("rgb", [])
		_allowed["%d,%d,%d" % [int(rgb[0]), int(rgb[1]), int(rgb[2])]] = true


func _check_hand(ws) -> void:
	var player := _Host.new()
	var body := MeshInstance3D.new()
	body.name = "MeshInstance3D"
	player.add_child(body)
	root.add_child(player)
	player.player_mesh = body
	await process_frame
	_Body.apply_to(body, ws.player_height(), ws.player_radius())
	var socket := body.get_node_or_null("PlayerRig/held_item") as Node3D
	if socket == null:
		_fail("player hand socket missing")
		return
	var view := _View.new()
	player.add_child(view)
	await process_frame
	for name in _MODELS:
		var item_id := str(_HELD[name])
		view.show_item(item_id)
		var held := view._item as MeshInstance3D
		if held == null or not (held.mesh is ArrayMesh):
			_fail("%s did not attach a voxel mesh" % item_id)
			continue
		if held.get_parent() != socket:
			_fail("%s parent %s" % [item_id, held.get_parent().name if held.get_parent() else "none"])
		elif held.position.length() > 0.02:
			_fail("%s grip offset %s" % [item_id, held.position])
		else:
			print("GRIP %s on held_item" % item_id)
	view.show_item("herb")
	if view._item.mesh is ArrayMesh:
		_fail("herb should stay a flat-icon stand-in box")
	else:
		print("OK herb keeps the box stand-in")
