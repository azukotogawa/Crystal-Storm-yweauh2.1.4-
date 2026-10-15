extends Node

const _PlayerSettings = preload("res://systems/player_settings.gd")

const META := "cs_blueprint"

const CATEGORY_COLOR := {
	"terrain": Color(0.86, 0.48, 0.18),
	"vegetation": Color(0.22, 0.62, 0.28),
	"mobs": Color(0.78, 0.24, 0.28),
	"items": Color(0.90, 0.74, 0.18),
	"ui": Color(0.22, 0.42, 0.86),
	"effects": Color(0.62, 0.28, 0.78),
}

const _GLYPH := {
	"A": "01110100011000111111100011000110001",
	"B": "11110100011000111110100011000111110",
	"C": "01111100001000010000100001000001111",
	"D": "11110100011000110001100011000111110",
	"E": "11111100001000011110100001000011111",
	"F": "11111100001000011110100001000010000",
	"G": "01111100001000010111100011000101111",
	"H": "10001100011000111111100011000110001",
	"I": "01110001000010000100001000010001110",
	"J": "00111000100001000010100101001001100",
	"K": "10001100101010011000101001001010001",
	"L": "10000100001000010000100001000011111",
	"M": "10001110111010110001100011000110001",
	"N": "10001110011010110011100011000110001",
	"O": "01110100011000110001100011000101110",
	"P": "11110100011000111110100001000010000",
	"Q": "01110100011000110001101011001001101",
	"R": "11110100011000111110101001001010001",
	"S": "01111100001000001110000010000111110",
	"T": "11111001000010000100001000010000100",
	"U": "10001100011000110001100011000101110",
	"V": "10001100011000110001010100010000100",
	"W": "10001100011000110101101011010101010",
	"X": "10001100010101000100010101000110001",
	"Y": "10001100010101000100001000010000100",
	"Z": "11111000010001000100010001000011111",
	"0": "01110100011001110101110011000101110",
	"1": "00100011000010000100001000010001110",
	"2": "01110100010000100010001000100011111",
	"3": "11110000010000101110000010000111110",
	"4": "10010100101001011111000100001000010",
	"5": "11111100001000011110000010000111110",
	"6": "01110100001000011110100011000101110",
	"7": "11111000010001000100010000100001000",
	"8": "01110100011000101110100011000101110",
	"9": "01110100011000101111000010000101110",
	" ": "00000000000000000000000000000000000",
	".": "00000000000000000000000000110001100",
	",": "00000000000000000000001000010001000",
	"/": "00001000100001000100010000100010000",
	"-": "00000000000000011111000000000000000",
	"_": "00000000000000000000000000000111111",
}

var enabled: bool = false
var _slots: Array = []
var _slot_keys: Dictionary = {}
var _themes_done: Dictionary = {}
var _cache: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _PlayerSettings.texture_blueprint:
		set_enabled(true)


func _unhandled_input(event: InputEvent) -> void:
	if event == null or event.is_echo():
		return
	if not event.is_action_pressed(&"texture_blueprint_toggle"):
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	get_viewport().set_input_as_handled()
	var nxt := not enabled
	set_enabled(nxt)
	_save_toggle(nxt)
	var tree := get_tree()
	if tree == null:
		return
	for menu in tree.get_nodes_in_group("settings_menu"):
		if menu.has_method("set_texture_blueprint"):
			menu.set_texture_blueprint(nxt)


func set_enabled(on: bool) -> void:
	_PlayerSettings.texture_blueprint = on
	if enabled == on:
		return
	enabled = on
	var tree := get_tree()
	if tree == null:
		return
	if on:
		if not tree.node_added.is_connected(_on_node_added):
			tree.node_added.connect(_on_node_added)
		_swap_tree(tree.root)
	else:
		if tree.node_added.is_connected(_on_node_added):
			tree.node_added.disconnect(_on_node_added)
		_restore_all()
	_rebind_chunk_materials(tree)


func _rebind_chunk_materials(tree: SceneTree) -> void:
	var script = load("res://chunks/chunk_view.gd")
	if script != null:
		script.rebind_live_materials(tree)


func remember_shader_texture(mat: ShaderMaterial, param: String, source: Texture2D) -> void:
	if not enabled or mat == null or source == null:
		return
	if _is_bp(source):
		return
	var grid := _grid_of(mat, source, true)
	var key := "shader:%d:%s" % [mat.get_instance_id(), param]
	var slot := {
		"obj": mat,
		"kind": "shader",
		"prop": param,
	}
	var ph := _begin(key, source, slot, null, true, grid)
	if ph != null:
		_assign_shader_texture(mat, param, ph)


func _save_toggle(on: bool) -> void:
	var data := _PlayerSettings.load_settings()
	data["texture_blueprint"] = on
	_PlayerSettings.save_settings(data)


func _on_node_added(node: Node) -> void:
	if not enabled or node == null:
		return
	call_deferred("_swap_node_if_enabled", node)


func _swap_node_if_enabled(node: Node) -> void:
	if not enabled or node == null or not is_instance_valid(node):
		return
	_swap_node(node)


func _swap_tree(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	_swap_node(node)
	for child in node.get_children():
		_swap_tree(child)


func _restore_all() -> void:
	for slot in _slots:
		var tex: Texture2D = slot.get("tex")
		if tex == null:
			continue
		_apply(slot, tex)
	_slots.clear()
	_slot_keys.clear()
	_themes_done.clear()


func _swap_node(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			_swap_mesh(mi.mesh, node)
			for s in mi.mesh.get_surface_count():
				var ov := mi.get_surface_override_material(s)
				if ov:
					_swap_material(ov, node)
	elif node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		if mmi.multimesh and mmi.multimesh.mesh:
			_swap_mesh(mmi.multimesh.mesh, node)
	elif node is CPUParticles3D:
		var cpu := node as CPUParticles3D
		if cpu.mesh:
			_swap_mesh(cpu.mesh, node)
	elif node is GPUParticles3D:
		var gpu := node as GPUParticles3D
		if gpu.draw_pass_1:
			_swap_mesh(gpu.draw_pass_1, node)
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		if gi.material_override:
			_swap_material(gi.material_override, node)
		if gi.material_overlay:
			_swap_material(gi.material_overlay, node)
	if node is CanvasItem:
		var canvas_mat := (node as CanvasItem).material
		if canvas_mat:
			_swap_material(canvas_mat, node)
	if "texture" in node:
		_swap_prop(node, "texture")
	if node is BaseButton:
		_swap_prop(node, "icon")
	if node is TextureButton:
		for prop in ["texture_normal", "texture_pressed", "texture_hover", "texture_disabled", "texture_focused"]:
			_swap_prop(node, prop)
	if node is AnimatedSprite2D and (node as AnimatedSprite2D).sprite_frames:
		_swap_frames((node as AnimatedSprite2D).sprite_frames, node)
	elif node is AnimatedSprite3D and (node as AnimatedSprite3D).sprite_frames:
		_swap_frames((node as AnimatedSprite3D).sprite_frames, node)
	if node is Control:
		var theme := (node as Control).theme
		if theme:
			_swap_theme(theme, node)


func _swap_mesh(mesh: Mesh, node: Node) -> void:
	if mesh == null:
		return
	for s in mesh.get_surface_count():
		var surface_mat := mesh.surface_get_material(s)
		if surface_mat:
			_swap_material(surface_mat, node)


func _swap_material(mat: Material, node: Node) -> void:
	if mat == null or not is_instance_valid(mat):
		return
	if mat is BaseMaterial3D:
		var albedo := (mat as BaseMaterial3D).albedo_texture
		var key := "albedo:%d" % mat.get_instance_id()
		var slot := {"obj": mat, "kind": "albedo"}
		var atlas := _is_atlas_name("", node, albedo)
		var ph := _begin(key, albedo, slot, node, atlas, _grid_of(mat, albedo, atlas))
		if ph != null:
			(mat as BaseMaterial3D).albedo_texture = ph
	if mat is ShaderMaterial:
		var sh := (mat as ShaderMaterial).shader
		if sh == null:
			return
		for uniform in sh.get_shader_uniform_list():
			var pname := str(uniform.get("name", ""))
			if pname.is_empty():
				continue
			var val = (mat as ShaderMaterial).get_shader_parameter(pname)
			if not (val is Texture2D):
				continue
			var tex := val as Texture2D
			var key := "shader:%d:%s" % [mat.get_instance_id(), pname]
			var slot := {"obj": mat, "kind": "shader", "prop": pname}
			var atlas := _is_atlas_name(pname, node, tex)
			var ph := _begin(key, tex, slot, node, atlas, _grid_of(mat, tex, atlas))
			if ph != null:
				_assign_shader_texture(mat as ShaderMaterial, pname, ph)


func _swap_prop(node: Node, prop: String) -> void:
	var val = node.get(prop)
	if not (val is Texture2D):
		return
	var tex := val as Texture2D
	var key := "prop:%d:%s" % [node.get_instance_id(), prop]
	var slot := {"obj": node, "kind": "prop", "prop": prop}
	var atlas := _is_atlas_name(prop, node, tex)
	var ph := _begin(key, tex, slot, node, atlas, _grid_of(null, tex, atlas))
	if ph != null:
		node.set(prop, ph)


func _swap_frames(frames: SpriteFrames, node: Node) -> void:
	if frames == null:
		return
	for anim in frames.get_animation_names():
		var count := frames.get_frame_count(anim)
		for i in count:
			var tex: Texture2D = frames.get_frame_texture(anim, i)
			if tex == null:
				continue
			var dur := frames.get_frame_duration(anim, i)
			var key := "frame:%d:%s:%d" % [frames.get_instance_id(), str(anim), i]
			var slot := {
				"obj": frames,
				"kind": "frame",
				"a": str(anim),
				"i": i,
				"dur": dur,
			}
			var ph := _begin(key, tex, slot, node, false, Vector2i.ONE)
			if ph != null:
				var use_dur := dur
				if _slot_keys.has(key):
					use_dur = float(_slot_keys[key].get("dur", dur))
				frames.set_frame(anim, i, ph, use_dur)


func _swap_theme(theme: Theme, node: Node) -> void:
	var id := theme.get_instance_id()
	if _themes_done.has(id):
		return
	_themes_done[id] = true
	for type_name in theme.get_type_list():
		for icon_name in theme.get_icon_list(type_name):
			var tex: Texture2D = theme.get_icon(icon_name, type_name)
			var key := "theme:%d:%s:%s" % [id, str(type_name), str(icon_name)]
			var slot := {
				"obj": theme,
				"kind": "theme_icon",
				"a": str(icon_name),
				"b": str(type_name),
				"label": "theme/%s/%s" % [str(type_name), str(icon_name)],
			}
			var ph := _begin(key, tex, slot, node, false, Vector2i.ONE)
			if ph != null:
				theme.set_icon(icon_name, type_name, ph)
		for sb_name in theme.get_stylebox_list(type_name):
			var sb := theme.get_stylebox(sb_name, type_name)
			if not (sb is StyleBoxTexture):
				continue
			var stex := (sb as StyleBoxTexture).texture
			var key := "style:%d" % sb.get_instance_id()
			var slot := {
				"obj": sb,
				"kind": "style",
				"label": "style/%s/%s" % [str(type_name), str(sb_name)],
			}
			var ph := _begin(key, stex, slot, node, false, Vector2i.ONE)
			if ph != null:
				(sb as StyleBoxTexture).texture = ph


func _begin(
	key: String,
	tex: Texture2D,
	slot: Dictionary,
	node: Node,
	atlas: bool,
	grid: Vector2i
) -> Texture2D:
	if _slot_keys.has(key):
		var prev: Dictionary = _slot_keys[key]
		return _make_ph(prev.get("tex"), node, prev, atlas, grid)
	if tex == null or _is_bp(tex):
		return null
	if tex.get_width() <= 0 or tex.get_height() <= 0:
		return null
	slot["tex"] = tex
	_slots.append(slot)
	_slot_keys[key] = slot
	return _make_ph(tex, node, slot, atlas, grid)


func _make_ph(src: Texture2D, node: Node, slot: Dictionary, atlas: bool, grid: Vector2i) -> Texture2D:
	if src == null:
		return null
	var kind := str(slot.get("kind", ""))
	var cat := _category(node, src)
	var scale := _scale_of(node)
	var pivot := _pivot_of(node)
	if kind == "theme_icon" or kind == "style":
		cat = "ui"
		scale = Vector2.ONE
		pivot = Vector2.ZERO
	var label := str(slot.get("label", ""))
	if label.is_empty():
		label = _label(src, node)
	return _placeholder(src, cat, label, scale, pivot, atlas, grid)


func _assign_shader_texture(mat: ShaderMaterial, param: String, tex: Texture2D) -> void:
	if mat == null or tex == null:
		return
	mat.set_shader_parameter(param, tex)
	RenderingServer.material_set_param(mat.get_rid(), param, tex.get_rid())


func _apply(slot: Dictionary, tex: Texture2D) -> void:
	var obj = slot.get("obj")
	if obj == null or not is_instance_valid(obj) or tex == null:
		return
	var kind := str(slot.get("kind", ""))
	if kind == "shader":
		_assign_shader_texture(obj as ShaderMaterial, str(slot.get("prop", "")), tex)
	elif kind == "albedo":
		(obj as BaseMaterial3D).albedo_texture = tex
	elif kind == "prop":
		obj.set(str(slot.get("prop", "")), tex)
	elif kind == "theme_icon":
		(obj as Theme).set_icon(str(slot.get("a", "")), str(slot.get("b", "")), tex)
	elif kind == "style":
		(obj as StyleBoxTexture).texture = tex
	elif kind == "frame":
		(obj as SpriteFrames).set_frame(str(slot.get("a", "")), int(slot.get("i", 0)), tex, float(slot.get("dur", 1.0)))


func _is_bp(tex: Texture2D) -> bool:
	return tex != null and tex.has_meta(META)


func _category(node: Node, tex: Texture2D) -> String:
	if node != null and node.has_meta("cs_texture_category"):
		var forced := str(node.get_meta("cs_texture_category"))
		if CATEGORY_COLOR.has(forced):
			return forced
	var node_name := ""
	if node != null:
		node_name = str(node.name)
	var path := ""
	if tex != null:
		path = str(tex.resource_path)
	var low_name := node_name.to_lower()
	if low_name.begins_with("terrain"):
		return "terrain"
	if low_name.begins_with("vegetation"):
		return "vegetation"
	if low_name.begins_with("mob"):
		return "mobs"
	if low_name.begins_with("item"):
		return "items"
	if low_name.begins_with("ui"):
		return "ui"
	if low_name.begins_with("effect"):
		return "effects"
	var blob := (path + " " + node_name).to_lower()
	if blob.contains("shadow") or blob.contains("particle") or blob.contains("vfx") or blob.contains("effect"):
		return "effects"
	if blob.contains("vegetation") or blob.contains("plant"):
		return "vegetation"
	if blob.contains("/entity/") or blob.contains("player.png") or blob.contains("mob"):
		return "mobs"
	if blob.contains("/items/") or blob.contains("/structures/") or blob.contains("/building/"):
		return "items"
	if blob.contains("/ui/") or blob.contains("theme"):
		return "ui"
	if blob.contains("/crystal/"):
		return "effects"
	if blob.contains("/tiles/") or blob.contains("atlas") or blob.contains("cube.png") or blob.contains("terrain"):
		return "terrain"
	if node is Control:
		return "ui"
	return "terrain"


func _label(tex: Texture2D, node: Node) -> String:
	var path := ""
	if tex != null:
		path = str(tex.resource_path)
	if not path.is_empty():
		var file := path.get_file()
		var parent := path.get_base_dir().get_file()
		if parent.is_empty():
			return file
		return parent + "/" + file
	if node != null:
		return str(node.name)
	return "texture"


func _scale_of(node: Node) -> Vector2:
	if node == null:
		return Vector2.ONE
	if node is SpriteBase3D:
		var sprite := node as SpriteBase3D
		return Vector2(sprite.scale.x * sprite.pixel_size, sprite.scale.y * sprite.pixel_size)
	if node is Node3D:
		var scale3 := (node as Node3D).scale
		return Vector2(scale3.x, scale3.y)
	if node is Node2D:
		return (node as Node2D).scale
	if node is Control:
		return (node as Control).scale
	return Vector2.ONE


func _pivot_of(node: Node) -> Vector2:
	if node is Sprite2D:
		return Vector2(0.5, 0.5) if (node as Sprite2D).centered else Vector2.ZERO
	if node is SpriteBase3D:
		return Vector2(0.5, 0.5) if (node as SpriteBase3D).centered else Vector2.ZERO
	if node is Control:
		return Vector2.ZERO
	return Vector2(0.5, 0.5)


func _is_atlas_name(prop: String, node: Node, tex: Texture2D) -> bool:
	var blob := prop.to_lower()
	if node != null:
		blob += " " + str(node.name).to_lower()
	if tex != null:
		blob += " " + str(tex.resource_path).to_lower()
	return blob.contains("atlas") or blob.contains("cube.png") or blob.contains("/tiles/")


func _grid_of(mat: Material, tex: Texture2D, atlas: bool) -> Vector2i:
	if not atlas or tex == null:
		return Vector2i.ONE
	if mat is ShaderMaterial:
		var g = (mat as ShaderMaterial).get_shader_parameter("atlas_grid")
		if g is Vector2 and g.x >= 1.0 and g.y >= 1.0:
			return Vector2i(maxi(int(round(g.x)), 1), maxi(int(round(g.y)), 1))
	var w := tex.get_width()
	var h := tex.get_height()
	if w >= 32 and h >= 32 and w % 32 == 0 and h % 32 == 0 and (w > 32 or h > 32):
		return Vector2i(maxi(w / 32, 1), maxi(h / 32, 1))
	return Vector2i.ONE


func _placeholder(
	src: Texture2D,
	category: String,
	label: String,
	scale: Vector2,
	pivot: Vector2,
	atlas: bool,
	grid: Vector2i
) -> Texture2D:
	var w := src.get_width()
	var h := src.get_height()
	if w <= 0 or h <= 0:
		return src
	if not CATEGORY_COLOR.has(category):
		category = "terrain"
	var cells := grid if atlas else Vector2i.ONE
	cells = Vector2i(maxi(cells.x, 1), maxi(cells.y, 1))
	var cache_key := "%d,%d|%s|%s|%.2f,%.2f|%.2f,%.2f|%d,%d" % [
		w, h, category, label, scale.x, scale.y, pivot.x, pivot.y, cells.x, cells.y
	]
	if _cache.has(cache_key):
		return _cache[cache_key]
	var fill: Color = CATEGORY_COLOR[category]
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(fill)
	var border := Color(fill.r * 0.35, fill.g * 0.35, fill.b * 0.35, 1.0)
	var grid_c := Color(fill.r * 0.55, fill.g * 0.55, fill.b * 0.55, 1.0)
	var ink := Color(0.06, 0.05, 0.04, 1.0)
	for x in w:
		_put(img, x, 0, border)
		_put(img, x, h - 1, border)
	for y in h:
		_put(img, 0, y, border)
		_put(img, w - 1, y, border)
	for x in range(0, w, 8):
		for y in h:
			_put(img, x, y, grid_c)
	for y in range(0, h, 8):
		for x in w:
			_put(img, x, y, grid_c)
	var cw := maxi(int(float(w) / float(cells.x)), 1)
	var ch := maxi(int(float(h) / float(cells.y)), 1)
	if cells.x > 1 or cells.y > 1:
		for cy in cells.y:
			for cx in cells.x:
				var x0 := cx * cw
				var y0 := cy * ch
				for yy in range(y0, mini(y0 + ch, h)):
					_put(img, x0, yy, border)
				for xx in range(x0, mini(x0 + cw, w)):
					_put(img, xx, y0, border)
				if ch >= 16:
					_draw_text(img, x0 + 2, y0 + 12, _short(label, 10), ink)
				if ch >= 24:
					_draw_text(img, x0 + 2, y0 + 20, "%d,%d" % [cx, cy], ink)
		if h >= 16:
			_draw_text(img, 2, 12, "%dx%d" % [w, h], ink)
		if h >= 32:
			_draw_text(img, 2, 28, "s=%.2f" % scale.x, ink)
	else:
		if h >= 16:
			_draw_text(img, 2, 12, _short(label, 18), ink)
		if h >= 24:
			_draw_text(img, 2, 20, "%dx%d" % [w, h], ink)
		if h >= 32:
			_draw_text(img, 2, 28, "s=%.2f,%.2f" % [scale.x, scale.y], ink)
	var px := int(round(clampf(pivot.x, 0.0, 1.0) * float(maxi(w - 1, 0))))
	var py := int(round(clampf(pivot.y, 0.0, 1.0) * float(maxi(h - 1, 0))))
	var mark := Color(1.0, 1.0, 1.0, 1.0)
	for d in range(-2, 3):
		_put(img, px + d, py, mark)
		_put(img, px, py + d, mark)
	var tex := ImageTexture.create_from_image(img)
	tex.set_meta(META, true)
	tex.set_meta("cs_blueprint_category", category)
	tex.resource_name = "bp_%s" % category
	_cache[cache_key] = tex
	return tex


func _put(img: Image, x: int, y: int, color: Color) -> void:
	if x == 3 and y == 3:
		return
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, color)


func _draw_text(img: Image, x0: int, y0: int, text: String, ink: Color) -> void:
	if img.get_height() < 16:
		return
	if y0 < 12:
		y0 = 12
	var x := x0
	var upper := text.to_upper()
	for i in upper.length():
		var ch := upper.substr(i, 1)
		_draw_glyph(img, x, y0, ch, ink)
		x += 6
		if x >= img.get_width():
			break


func _draw_glyph(img: Image, x0: int, y0: int, ch: String, ink: Color) -> void:
	var bits := str(_GLYPH.get(ch, ""))
	if bits.length() != 35:
		return
	var i := 0
	for row in 7:
		for col in 5:
			if bits.substr(i, 1) == "1":
				_put(img, x0 + col, y0 + row, ink)
			i += 1


func _short(text: String, max_len: int) -> String:
	var clean := ""
	var upper := text.to_upper()
	for i in upper.length():
		var ch := upper.substr(i, 1)
		if _GLYPH.has(ch):
			clean += ch
	if clean.length() > max_len:
		return clean.substr(0, max_len)
	return clean
