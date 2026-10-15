extends SceneTree

const _Blueprints = preload("res://helpers/structure_blueprints.gd")
const _Registry = preload("res://building/building_registry.gd")
const _Edits = preload("res://world/terrain_edits.gd")
const _Weapon = preload("res://weapons/weapon_controller.gd")
const _Highlight = preload("res://player/target_highlight.gd")
const _Features = preload("res://world/feature_registry.gd")
const _Crafting = preload("res://helpers/structure_crafting.gd")
const _Inventory = preload("res://inventory/inventory.gd")
const _Placeable = preload("res://helpers/placeable_catalog.gd")
const _Items = preload("res://helpers/item_types.gd")
const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _Chunks = preload("res://chunks/chunk_manager.gd")
const _Panel = preload("res://ui/inventory_panel.gd")
const _Settings = preload("res://config/world_settings.gd")
const _Integrity = preload("res://helpers/structure_integrity.gd")
const _WorldState = preload("res://world/world_state.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL " + msg)


func _run() -> void:
	_Registry.reset()
	_Registry.ensure_builtins()
	if not _Blueprints.LARGE_STRUCTURES:
		_fail("LARGE_STRUCTURES must default true")
	_test_wall_tiles()
	_test_segment()
	_test_corner()
	_test_gate()
	_test_stairs()
	_test_tower()
	_test_unknown()
	_test_snap_and_rotation()
	_test_ghost_validity()
	_test_ghost_uses_build_highlight()
	_test_craft_then_place()
	_test_damage_and_repair()
	if _failed == 0:
		print("All structure blueprint tests OK")
		quit(0)
	else:
		push_error("verify_structure_blueprints: %d failure(s)" % _failed)
		quit(1)


func _test_wall_tiles() -> void:
	var stone = _Registry.get_def(&"stone_wall")
	var wood = _Registry.get_def(&"wood_wall")
	if stone == null or wood == null:
		_fail("stone and wood walls must stay registered")
		return
	var src := (_Edits as GDScript).source_code
	var at := src.find("func build_wall")
	var end := src.find("\nstatic func ", at + 10)
	var body := src.substr(at, maxi(end - at, 0))
	if "ws.build_tile[key] = tile_id" not in body:
		_fail("build_wall must keep storing the passed wall tile")
		return
	if int(stone.tile_id) == int(wood.tile_id):
		_fail("stone and wood walls must keep different tiles")
		return
	print("OK build_wall still stores the stone and wood wall tiles")


func _test_segment() -> void:
	var bp := _Blueprints.get_blueprint(_Blueprints.WALL_SEGMENT)
	if not _expect_box(bp, "wall_segment", 3, 2, 1, 6):
		return
	var stone = _Registry.get_def(&"stone_wall")
	if not _expect_cost(bp, stone, 6):
		return
	print("OK wall segment is 3x2x1 of the stone wall tile")


func _test_corner() -> void:
	var bp := _Blueprints.get_blueprint(_Blueprints.WALL_CORNER)
	if not _expect_box(bp, "wall_corner", 2, 2, 2, 6):
		return
	var seen := {}
	for cell in bp["cells"]:
		seen[Vector3i(int(cell["x"]), int(cell["y"]), int(cell["z"]))] = true
	if seen.has(Vector3i(1, 0, 1)) or seen.has(Vector3i(1, 1, 1)):
		_fail("wall corner must leave the inner column empty")
		return
	if not seen.has(Vector3i(0, 0, 0)) or not seen.has(Vector3i(1, 0, 0)) or not seen.has(Vector3i(0, 0, 1)):
		_fail("wall corner must occupy the L at the bottom")
		return
	var stone = _Registry.get_def(&"stone_wall")
	if not _expect_cost(bp, stone, 6):
		return
	print("OK wall corner is a 2x2x2 L of the stone wall tile")


func _test_gate() -> void:
	var bp := _Blueprints.get_blueprint(_Blueprints.GATE)
	if not _expect_box(bp, "gate", 3, 2, 1, 4):
		return
	var seen := {}
	for cell in bp["cells"]:
		seen[Vector3i(int(cell["x"]), int(cell["y"]), int(cell["z"]))] = str(cell.get("build", ""))
	if seen.get(Vector3i(0, 0, 0), "") != "stone_wall" or seen.get(Vector3i(2, 1, 0), "") != "stone_wall":
		_fail("gate posts must be stone walls")
		return
	if seen.has(Vector3i(1, 0, 0)):
		_fail("gate opening must not be a stacked wall cell")
		return
	var passages: Array = bp.get("passages", [])
	if passages.size() != 1 or str(passages[0].get("role", "")) != "passage" or str(passages[0].get("build", "")) != "gate":
		_fail("gate blueprint must keep one passage on the existing gate")
		return
	var gate = _Registry.get_def(&"gate")
	if int(passages[0].get("tile", -1)) != int(gate.tile_id):
		_fail("gate passage must use the gate tile")
		return
	var recipe: Array = bp.get("recipe", [])
	if recipe.size() != 2 or str(recipe[1].get("id", "")) != str(gate.material_id) or int(recipe[1].get("count", 0)) != int(gate.material_count):
		_fail("gate recipe must add the gate material to the stone posts")
		return
	print("OK gate blueprint is two stone posts and the authored gate passage")


func _test_stairs() -> void:
	var bp := _Blueprints.get_blueprint(_Blueprints.STAIRS)
	if not _expect_box(bp, "stairs", 3, 3, 1, 6):
		return
	var heights := [0, 0, 0]
	for cell in bp["cells"]:
		if str(cell.get("build", "")) != "stairs":
			_fail("stairs cells must use the stairs build")
			return
		heights[int(cell["x"])] += 1
	if heights != [1, 2, 3]:
		_fail("stairs must rise one layer per column, got %s" % heights)
		return
	var stone = _Registry.get_def(&"stone_wall")
	if not _expect_cost(bp, stone, 6):
		return
	print("OK stairs rise 1, 2, then 3 on the stone tile")


func _test_tower() -> void:
	var bp := _Blueprints.get_blueprint(_Blueprints.SMALL_TOWER)
	if not _expect_box(bp, "small_tower", 2, 3, 2, 12):
		return
	for cell in bp["cells"]:
		if str(cell.get("build", "")) != "small_tower":
			_fail("tower cells must use the small tower build")
			return
	var stone = _Registry.get_def(&"stone_wall")
	if not _expect_cost(bp, stone, 12):
		return
	print("OK small tower is a solid 2x3x2")


func _test_unknown() -> void:
	var ids := _Blueprints.ids()
	if ids.size() != 5 or _Blueprints.WALL_SEGMENT not in ids or _Blueprints.WALL_CORNER not in ids:
		_fail("blueprint ids must list the wall pieces, the gate, the stairs, and the small tower")
		return
	if _Blueprints.GATE not in ids or _Blueprints.STAIRS not in ids or _Blueprints.SMALL_TOWER not in ids:
		_fail("blueprint ids must list the wall pieces, the gate, the stairs, and the small tower")
		return
	if not _Blueprints.get_blueprint(&"tower").is_empty():
		_fail("an unnamed tower must stay empty")
		return
	print("OK the five structure blueprints are listed")


func _test_snap_and_rotation() -> void:
	var snapped := _Weapon.snap_blueprint_anchor(Vector3(3.2, 9.8, -0.01))
	if snapped != Vector2i(3, -1):
		_fail("ghost anchor %s did not snap to the grid cell" % snapped)
		return
	var edge := _Weapon.snap_blueprint_anchor(Vector3(-0.1, 0.0, 4.0))
	if edge != Vector2i(-1, 4):
		_fail("negative ghost anchor %s did not snap down to the cell" % edge)
		return
	var cell := Vector3i(2, 1, 0)
	if _Weapon.rotate_blueprint_cell(cell, 0) != cell:
		_fail("quarter 0 must keep the cell")
		return
	if _Weapon.rotate_blueprint_cell(cell, 1) != Vector3i(0, 1, -2):
		_fail("quarter 1 must turn the wall 90 degrees")
		return
	if _Weapon.rotate_blueprint_cell(cell, 2) != Vector3i(-2, 1, 0):
		_fail("quarter 2 must turn the wall 180 degrees")
		return
	if _Weapon.rotate_blueprint_cell(cell, 3) != Vector3i(0, 1, 2):
		_fail("quarter 3 must turn the wall 270 degrees")
		return
	if _Weapon.rotate_blueprint_cell(cell, 4) != cell:
		_fail("four quarter turns must restore the cell")
		return
	var weapon = _Weapon.new()
	weapon.rotate_selected_blueprint(1)
	weapon.rotate_selected_blueprint(1)
	if weapon.blueprint_quarter != 2:
		_fail("selected blueprint quarter is %d, want 2" % weapon.blueprint_quarter)
		weapon.free()
		return
	weapon.cycle_selected_blueprint(1)
	if weapon.selected_blueprint_id() != _Blueprints.WALL_CORNER or weapon.blueprint_quarter != 0:
		_fail("cycling the blueprint must select the corner and clear the turn")
		weapon.free()
		return
	weapon.free()
	print("OK ghost snaps to the grid and turns in 90 degree steps")


func _test_ghost_validity() -> void:
	_Edits.reset()
	_Features.reset()
	var ground := _FlatGround.new()
	var column := Vector3(5.4, 0.0, 7.8)
	var flat: Dictionary = _Weapon.ghost_preview(_Blueprints.WALL_SEGMENT, column, 0, ground)
	if flat.get("anchor") != Vector2i(5, 7) or int(flat.get("quarter", -1)) != 0:
		_fail("flat ghost anchor %s quarter %s" % [flat.get("anchor"), flat.get("quarter")])
		return
	if not bool(flat.get("valid", false)) or not _reasons(flat, "ok", 6):
		_fail("flat wall segment must be valid, got %s" % _reason_map(flat))
		return
	var turned: Dictionary = _Weapon.ghost_preview(_Blueprints.WALL_SEGMENT, column, 1, ground)
	if not _has_cell(turned, Vector3i(5, 1, 5)) or _has_cell(turned, Vector3i(7, 1, 7)):
		_fail("quarter turn must swing the segment onto the anchor column, got %s" % _cells_of(turned))
		return
	var corner: Dictionary = _Weapon.ghost_preview(_Blueprints.WALL_CORNER, column, 1, ground)
	if _has_cell(corner, Vector3i(6, 1, 6)):
		_fail("turned corner must keep the inner column empty")
		return
	if corner.get("cells", []).size() != 6:
		_fail("turned corner lost cells")
		return
	_Edits.dig(6, 7, 1)
	var hole: Dictionary = _Weapon.ghost_preview(_Blueprints.WALL_SEGMENT, column, 0, ground)
	if bool(hole.get("valid", false)) or not _reason_at(hole, Vector3i(6, 1, 7), "unsupported"):
		_fail("a dug neighbor must tint unsupported, got %s" % _reason_map(hole))
		_Edits.reset()
		return
	if not _reason_at(hole, Vector3i(5, 1, 7), "ok") or not _reason_at(hole, Vector3i(6, 2, 7), "unsupported"):
		_fail("only the dug column is unsupported, got %s" % _reason_map(hole))
		_Edits.reset()
		return
	_Edits.reset()
	_Edits.set_build_tile_only(7, 7, 3)
	var built: Dictionary = _Weapon.ghost_preview(_Blueprints.WALL_SEGMENT, column, 0, ground)
	if bool(built.get("valid", false)) or not _reason_at(built, Vector3i(7, 1, 7), "blocked"):
		_fail("an existing build tile must tint blocked, got %s" % _reason_map(built))
		_Edits.reset()
		return
	if not _reason_at(built, Vector3i(5, 1, 7), "ok"):
		_fail("an open column must stay valid beside a blocked one")
		_Edits.reset()
		return
	_Edits.reset()
	_Features.register_feature(5, 7, 0, {"build_id": "stone_wall"})
	var occupied: Dictionary = _Weapon.ghost_preview(_Blueprints.WALL_SEGMENT, column, 0, ground)
	if not _reason_at(occupied, Vector3i(5, 1, 7), "blocked") or not _reason_at(occupied, Vector3i(5, 2, 7), "blocked"):
		_fail("a built feature must block that column, got %s" % _reason_map(occupied))
		_Features.reset()
		return
	_Features.reset()
	var abroad: Dictionary = _Weapon.ghost_preview(_Blueprints.WALL_SEGMENT, Vector3(5000.2, 0.0, 0.2), 0, ground)
	if bool(abroad.get("valid", false)) or not _reasons(abroad, "blocked", 6):
		_fail("outside the border the ghost must be blocked, got %s" % _reason_map(abroad))
		return
	print("OK ghost validity tints blocked cells and unsupported ground")


func _test_ghost_uses_build_highlight() -> void:
	var good: Color = _Highlight.structure_ghost_tint(true)
	var bad: Color = _Highlight.structure_ghost_tint(false)
	if good.g <= 0.75 or good.r >= 0.55:
		_fail("valid ghost tint %s must match the green build highlight" % good)
		return
	if bad.r <= bad.g or bad.r < 0.8:
		_fail("invalid ghost tint %s must match the blocked build highlight" % bad)
		return
	var weapon_src := (_Weapon as GDScript).source_code
	var highlight_src := (_Highlight as GDScript).source_code
	if "func ghost_preview" not in weapon_src or "show_structure_ghost" not in weapon_src:
		_fail("weapon controller must preview the selected blueprint")
		return
	if "func show_structure_ghost" not in highlight_src or "structure_ghost_tint" not in highlight_src:
		_fail("structure ghost must reuse the build highlight tint")
		return
	var show_at := highlight_src.find("func show_structure_ghost")
	var show_end := highlight_src.find("\nfunc ", show_at + 10)
	var show_body := highlight_src.substr(show_at, maxi(show_end - show_at, 0))
	if "structure_ghost_tint" not in show_body:
		_fail("structure ghost marks must take the build highlight tint")
		return
	print("OK structure ghost reuses the build highlight tint")


func _test_craft_then_place() -> void:
	_Edits.reset()
	_Features.reset()
	_Items.reset()
	_Items.ensure_builtins()
	var panel_src := (_Panel as GDScript).source_code
	if "CraftRow" not in panel_src or "structure_crafting.gd" not in panel_src:
		_fail("inventory must offer a craft row for the blueprints")
		return
	if "Craft_wall_segment" not in panel_src or "Craft_wall_corner" not in panel_src:
		_fail("inventory craft row must name the wall segment and the wall corner")
		return
	if "Craft_gate" not in panel_src or "Craft_stairs" not in panel_src or "Craft_small_tower" not in panel_src:
		_fail("inventory craft row must name the gate, the stairs, and the small tower")
		return
	var menu := _Placeable.entries()
	if menu.find("wall_segment") < 0 or menu.find("wall_corner") < 0:
		_fail("build menu must list the wall segment and the wall corner")
		return
	if menu.find("stairs") < 0 or menu.find("small_tower") < 0 or menu.find("gate") < 0:
		_fail("build menu must list the gate, the stairs, and the small tower")
		return
	if _Placeable.display_name("wall_segment") != "Wall Segment" or _Placeable.display_name("wall_corner") != "Wall Corner":
		_fail("build menu names must be Wall Segment and Wall Corner")
		return
	if _Placeable.display_name("stairs") != "Stairs" or _Placeable.display_name("small_tower") != "Small Tower" or _Placeable.display_name("gate") != "Gate":
		_fail("build menu names must be Gate, Stairs, and Small Tower")
		return
	var weapon = _Weapon.new()
	weapon.place_index = menu.find("wall_segment")
	if weapon.get_place_label() != "Wall Segment":
		_fail("build menu selection must read Wall Segment")
		weapon.free()
		return
	weapon.free()
	var inv = _Inventory.new()
	var seg := _Blueprints.get_blueprint(_Blueprints.WALL_SEGMENT)
	var cor := _Blueprints.get_blueprint(_Blueprints.WALL_CORNER)
	var seg_cost := int(seg.get("cost", {}).get("count", 0))
	var cor_cost := int(cor.get("cost", {}).get("count", 0))
	inv.add_item("stone", seg_cost - 1)
	if _Crafting.craft(inv, _Blueprints.WALL_SEGMENT):
		_fail("a short stone stack must not craft a wall segment")
		return
	if inv.count_item("stone") != seg_cost - 1 or inv.count_item("wall_segment") != 0:
		_fail("a refused craft must leave the inventory unchanged")
		return
	inv.add_item("stone", 1)
	if not _Crafting.craft(inv, _Blueprints.WALL_SEGMENT):
		_fail("wall segment craft must spend the blueprint cost")
		return
	inv.add_item("stone", cor_cost)
	if not _Crafting.craft(inv, _Blueprints.WALL_CORNER):
		_fail("wall corner craft must spend the blueprint cost")
		return
	if inv.count_item("stone") != 0:
		_fail("crafting both pieces must spend every stone from the blueprint costs")
		return
	var hot_seg = inv.get_hotbar_item(0)
	var hot_cor = inv.get_hotbar_item(1)
	if hot_seg == null or str(hot_seg.id) != "wall_segment" or int(hot_seg.count) != 1:
		_fail("crafted wall segment must sit on the hotbar")
		return
	if hot_cor == null or str(hot_cor.id) != "wall_corner" or int(hot_cor.count) != 1:
		_fail("crafted wall corner must sit on the hotbar")
		return
	var editor = _TerrainEditor.new()
	var world = _FlatWorld.new()
	var chunks = _Chunks.new()
	editor.world = world
	editor.chunk_manager = chunks
	var placed_seg := editor.try_place_blueprint(Vector3(4.2, 0.0, 6.2), inv, _Blueprints.WALL_SEGMENT, 0)
	if not placed_seg or int(editor.last_place_batch.get("placed_count", 0)) != 6:
		_fail("crafted wall segment did not place: %s" % editor.last_fail_reason)
		_release_place(editor, world, chunks)
		return
	if inv.count_item("wall_segment") != 0 or inv.count_item("wall_corner") != 1 or inv.count_item("stone") != 0:
		_fail("placing the segment must spend the crafted piece and not the stone")
		_release_place(editor, world, chunks)
		return
	if not _raised_run(4, 6, 3):
		_fail("placed wall segment must raise three columns by two layers")
		_release_place(editor, world, chunks)
		return
	var placed_cor := editor.try_place_blueprint(Vector3(8.2, 0.0, 6.2), inv, _Blueprints.WALL_CORNER, 0)
	if not placed_cor or int(editor.last_place_batch.get("placed_count", 0)) != 6:
		_fail("crafted wall corner did not place: %s" % editor.last_fail_reason)
		_release_place(editor, world, chunks)
		return
	if inv.count_item("wall_corner") != 0 or inv.count_item("stone") != 0:
		_fail("placing the corner must spend the crafted piece and not the stone")
		_release_place(editor, world, chunks)
		return
	if _layers_at(8, 6) != 2 or _layers_at(9, 6) != 2 or _layers_at(8, 7) != 2:
		_fail("placed wall corner must raise the L")
		_release_place(editor, world, chunks)
		return
	if _layers_at(9, 7) != 0:
		_fail("placed wall corner must leave the inner column empty")
		_release_place(editor, world, chunks)
		return
	if not _place_gate_stairs_tower(editor, world):
		_release_place(editor, world, chunks)
		return
	_release_place(editor, world, chunks)
	_Edits.reset()
	_Features.reset()
	print("OK crafted wall segment and wall corner place from the hotbar")


func _place_gate_stairs_tower(editor, world) -> bool:
	_Edits.reset()
	_Features.reset()
	var inv = _Inventory.new()
	inv.add_item("stone", 40)
	inv.add_item("wood", 8)
	var placed_gate: bool = editor.try_place_blueprint(Vector3(4.2, 0.0, 12.2), inv, _Blueprints.GATE, 0)
	if not placed_gate or int(editor.last_place_batch.get("placed_count", 0)) != 4:
		_fail("gate blueprint did not place its posts: %s" % editor.last_fail_reason)
		return false
	if _layers_at(4, 12) != 2 or _layers_at(6, 12) != 2 or _layers_at(5, 12) != 0:
		_fail("gate posts must rise two layers and the opening must stay at ground")
		return false
	var opening: Dictionary = _Features.get_feature(5, 12)
	if str(opening.get("build_id", "")) != "gate" or not bool(opening.get("is_passage", false)) or str(opening.get("visual_id", "")) != "gate":
		_fail("gate opening must keep the gate visual")
		return false
	var post: Dictionary = _Features.get_feature(4, 12)
	if str(post.get("build_id", "")) != "stone_wall" or str(post.get("visual_id", "")) != "stone_wall":
		_fail("gate posts must keep the stone wall visual")
		return false
	var placed_stairs: bool = editor.try_place_blueprint(Vector3(4.2, 0.0, 16.2), inv, _Blueprints.STAIRS, 0)
	if not placed_stairs or int(editor.last_place_batch.get("placed_count", 0)) != 6:
		_fail("stairs blueprint did not place: %s" % editor.last_fail_reason)
		return false
	if _layers_at(4, 16) != 1 or _layers_at(5, 16) != 2 or _layers_at(6, 16) != 3:
		_fail("stairs must leave layers 1, 2, and 3")
		return false
	var step: Dictionary = _Features.get_feature(6, 16)
	if str(step.get("build_id", "")) != "stairs" or str(step.get("visual_id", "")) != "stairs":
		_fail("stairs columns must use the stairs visual")
		return false
	var placed_tower: bool = editor.try_place_blueprint(Vector3(10.2, 0.0, 16.2), inv, _Blueprints.SMALL_TOWER, 0)
	if not placed_tower or int(editor.last_place_batch.get("placed_count", 0)) != 12:
		_fail("small tower blueprint did not place: %s" % editor.last_fail_reason)
		return false
	if _layers_at(10, 16) != 3 or _layers_at(11, 16) != 3 or _layers_at(10, 17) != 3 or _layers_at(11, 17) != 3:
		_fail("small tower must raise a 2x2 by three layers")
		return false
	var crown: Dictionary = _Features.get_feature(11, 17)
	if str(crown.get("build_id", "")) != "small_tower" or str(crown.get("visual_id", "")) != "small_tower":
		_fail("small tower columns must use the tower visual")
		return false
	print("OK gate, stairs, and small tower place from their blueprints")
	return true


func _test_damage_and_repair() -> void:
	_Edits.reset()
	_Features.reset()
	_Integrity.reset()
	var editor = _TerrainEditor.new()
	var world = _FlatWorld.new()
	var chunks = _Chunks.new()
	editor.world = world
	editor.chunk_manager = chunks
	var inv = _Inventory.new()
	inv.add_item("stone", 20)
	if not editor.try_place_blueprint(Vector3(4.2, 0.0, 6.2), inv, _Blueprints.WALL_SEGMENT, 0):
		_fail("damage test could not place a wall segment: %s" % editor.last_fail_reason)
		_release_place(editor, world, chunks)
		return
	var rec := _Integrity.record_at(Vector2i(4, 6))
	if int(rec.get("structure_hp", 0)) != 48 or int(rec.get("structure_max", 0)) != 48:
		_fail("wall segment HP is %s/%s, want 48/48" % [rec.get("structure_hp"), rec.get("structure_max")])
		_release_place(editor, world, chunks)
		return
	if not editor.try_place_blueprint(Vector3(10.2, 0.0, 6.2), inv, _Blueprints.WALL_SEGMENT, 0):
		_fail("damage test could not place the second wall: %s" % editor.last_fail_reason)
		_release_place(editor, world, chunks)
		return
	var enemy: Dictionary = _Integrity.damage_around(Vector2i(3, 6), 10.0, null)
	if not bool(enemy.get("hit", false)) or bool(enemy.get("destroyed", false)) or int(enemy.get("hp", 0)) != 38:
		_fail("an adjacent enemy hit should leave the wall at 38 HP, got %s" % enemy)
		_release_place(editor, world, chunks)
		return
	if int(_Integrity.record_at(Vector2i(10, 6)).get("structure_hp", 0)) != 48:
		_fail("enemy damage must stay on the wall that was hit")
		_release_place(editor, world, chunks)
		return
	var crystal: Array = _Integrity.erode_columns([Vector2i(4, 6), Vector2i(5, 6), Vector2i(6, 6)], null)
	if crystal.size() != 1 or int(crystal[0].get("hp", 0)) != 36 or str(crystal[0].get("source", "")) != "crystal":
		_fail("crystal should chip a touched wall once, got %s" % crystal)
		_release_place(editor, world, chunks)
		return
	var broke: Dictionary = _Integrity.repair_at(Vector2i(5, 6), _Inventory.new())
	if bool(broke.get("repaired", false)):
		_fail("repair without stone must fail")
		_release_place(editor, world, chunks)
		return
	var payer = _Inventory.new()
	payer.add_item("stone", 1)
	if not editor.try_repair_structure(Vector3(5.2, 0.0, 6.2), payer):
		_fail("the player must repair a damaged structure with stone")
		_release_place(editor, world, chunks)
		return
	if payer.count_item("stone") != 0 or int(_Integrity.record_at(Vector2i(6, 6)).get("structure_hp", 0)) != 44:
		_fail("one stone must restore 8 HP on every column of that wall")
		_release_place(editor, world, chunks)
		return
	var weapon_src := (_Weapon as GDScript).source_code
	var enemy_src := str((load("res://entities/crystal_enemy.gd") as GDScript).source_code)
	var animal_src := str((load("res://entities/world_entity.gd") as GDScript).source_code)
	var crystal_src := str((load("res://crystal/crystal_manager.gd") as GDScript).source_code)
	if "try_repair_structure" not in weapon_src or "chip_enemy" not in enemy_src or "chip_enemy" not in animal_src or "_erode_structures" not in crystal_src:
		_fail("the player, enemies, and the crystal must call structure damage and repair")
		_release_place(editor, world, chunks)
		return
	_WorldState.reset_trace_counters()
	var dead: Dictionary = _Integrity.apply_damage(Vector2i(4, 6), 100.0, &"enemy", null)
	var bumps := _WorldState.get_trace_bump_count()
	_WorldState.stop_trace_counters()
	if not bool(dead.get("destroyed", false)) or int(dead.get("edits", 0)) != 1 or int(dead.get("removed", 0)) != 6 or bumps != 1:
		_fail("destroying a wall must remove its 6 cells in one edit, got %s bumps %d" % [dead, bumps])
		_release_place(editor, world, chunks)
		return
	if _layers_at(4, 6) != 0 or _layers_at(5, 6) != 0 or _layers_at(6, 6) != 0:
		_fail("a destroyed wall must drop every column")
		_release_place(editor, world, chunks)
		return
	if not _Features.get_feature(4, 6).is_empty() or not _Features.get_feature(5, 6).is_empty():
		_fail("a destroyed wall must clear its cells")
		_release_place(editor, world, chunks)
		return
	if int(_Integrity.record_at(Vector2i(10, 6)).get("structure_hp", 0)) != 48:
		_fail("destroying one wall must leave the other")
		_release_place(editor, world, chunks)
		return
	if not editor.try_place_blueprint(Vector3(4.2, 0.0, 14.2), inv, _Blueprints.GATE, 0):
		_fail("damage test could not place a gate: %s" % editor.last_fail_reason)
		_release_place(editor, world, chunks)
		return
	var gate_dead: Dictionary = _Integrity.apply_damage(Vector2i(5, 14), 400.0, &"crystal", null)
	if not bool(gate_dead.get("destroyed", false)) or int(gate_dead.get("edits", 0)) != 1 or int(gate_dead.get("removed", 0)) != 5:
		_fail("destroying a gate must remove the posts and the opening in one edit, got %s" % gate_dead)
		_release_place(editor, world, chunks)
		return
	if _layers_at(4, 14) != 0 or _layers_at(6, 14) != 0 or not _Features.get_feature(5, 14).is_empty():
		_fail("a destroyed gate must clear the posts and the opening")
		_release_place(editor, world, chunks)
		return
	_release_place(editor, world, chunks)
	_Edits.reset()
	_Features.reset()
	_Integrity.reset()
	print("OK structures track HP, take enemy and crystal damage, repair with stone, and fall in one edit")


func _layers_at(x: int, z: int) -> int:
	var layer: float = _Settings.get_active().layer_height()
	return int(round(_Edits.get_height_delta(x, z) / maxf(layer, 0.001)))


func _raised_run(origin_x: int, origin_z: int, width: int) -> bool:
	for x in width:
		if _layers_at(origin_x + x, origin_z) != 2:
			return false
	return true


func _release_place(editor, world, chunks) -> void:
	if editor:
		editor.free()
	if world:
		world.free()
	if chunks:
		chunks.free()


func _reasons(plan: Dictionary, reason: String, count: int) -> bool:
	var cells: Array = plan.get("cells", [])
	if cells.size() != count:
		return false
	for cell in cells:
		if str(cell.get("reason", "")) != reason:
			return false
	return true


func _reason_at(plan: Dictionary, at: Vector3i, reason: String) -> bool:
	for cell in plan.get("cells", []):
		if cell.get("at") == at:
			return str(cell.get("reason", "")) == reason
	return false


func _has_cell(plan: Dictionary, at: Vector3i) -> bool:
	for cell in plan.get("cells", []):
		if cell.get("at") == at:
			return true
	return false


func _cells_of(plan: Dictionary) -> Array:
	var out: Array = []
	for cell in plan.get("cells", []):
		out.append(cell.get("at"))
	return out


func _reason_map(plan: Dictionary) -> String:
	var parts: PackedStringArray = []
	for cell in plan.get("cells", []):
		parts.append("%s=%s" % [cell.get("at"), cell.get("reason")])
	return " ".join(parts)


func _expect_box(bp: Dictionary, id: String, w: int, h: int, d: int, count: int) -> bool:
	if str(bp.get("id", "")) != id:
		_fail("%s id missing" % id)
		return false
	var foot: Dictionary = bp.get("footprint", {})
	if int(foot.get("w", -1)) != w or int(foot.get("h", -1)) != h or int(foot.get("d", -1)) != d:
		_fail("%s footprint %s is not %dx%dx%d" % [id, foot, w, h, d])
		return false
	var cells: Array = bp.get("cells", [])
	if cells.size() != count:
		_fail("%s has %d cells, want %d" % [id, cells.size(), count])
		return false
	var stone_tile := int(_Registry.get_def(&"stone_wall").tile_id)
	var seen := {}
	for cell in cells:
		var at := Vector3i(int(cell.get("x", -1)), int(cell.get("y", -1)), int(cell.get("z", -1)))
		if at.x < 0 or at.y < 0 or at.z < 0 or at.x >= w or at.y >= h or at.z >= d:
			_fail("%s cell %s is outside the footprint" % [id, at])
			return false
		if seen.has(at):
			_fail("%s repeats %s" % [id, at])
			return false
		seen[at] = true
		if int(cell.get("tile", -1)) != stone_tile:
			_fail("%s cell %s tile is not the stone wall tile" % [id, at])
			return false
	return true


func _expect_cost(bp: Dictionary, wall, occupied: int) -> bool:
	var count := occupied * int(wall.material_count)
	var cost: Dictionary = bp.get("cost", {})
	if str(cost.get("id", "")) != str(wall.material_id) or int(cost.get("count", -1)) != count:
		_fail("%s cost %s is not %d %s" % [bp.get("id", ""), cost, count, wall.material_id])
		return false
	var fallback := occupied * int(wall.wood_fallback_count)
	if int(cost.get("wood_fallback", -1)) != fallback:
		_fail("%s wood fallback %s is not %d" % [bp.get("id", ""), cost, fallback])
		return false
	var recipe: Array = bp.get("recipe", [])
	if recipe.size() != 1:
		_fail("%s recipe must be one stone stack" % bp.get("id", ""))
		return false
	var line: Dictionary = recipe[0]
	if str(line.get("id", "")) != str(wall.material_id) or int(line.get("count", -1)) != count:
		_fail("%s recipe %s does not match the stone cost" % [bp.get("id", ""), line])
		return false
	return true


class _FlatGround:
	extends RefCounted

	func get_surface_height(wx: float, wz: float) -> float:
		return _Edits.get_height_delta(floori(wx), floori(wz))


class _FlatWorld:
	extends InfiniteNoiseWorld

	func get_surface_height(wx: float, wz: float) -> float:
		return _Edits.get_height_delta(floori(wx), floori(wz))
