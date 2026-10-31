class_name ObjectVoxelCatalog
extends RefCounted

const _Loader = preload("res://helpers/crystal_voxel_loader.gd")
const _Builder = preload("res://helpers/voxel_model_builder.gd")
const _Palette = preload("res://ui/crystal_palette.gd")

const DIR := "res://assets/voxel/objects/"
const BUDGET := 1500

const MODELS: Array[String] = [
	"torch", "chest", "door", "workbench", "furnace", "crystal_node", "bed", "sign",
	"wood_wall", "stone_wall", "gate", "bridge", "town_hall", "ruin_pillar",
]

const _PARTS := {
	"torch": ["body", "flame"],
	"chest": ["body", "lid"],
	"door": ["hinge", "leaf"],
	"furnace": ["body", "ember"],
	"crystal_node": ["body", "crystal"],
}

static func path_for(model_name: String) -> String:
	return DIR + model_name + ".json"


static func is_authored(model_name: String) -> bool:
	return model_name in MODELS


static func glow_color(part_name: String) -> Color:
	if part_name == "crystal":
		return _Palette.mass_emission(false)
	return Color8(230, 140, 56)


static func emits(part_name: String) -> bool:
	return part_name in ["flame", "ember", "crystal"]


static func build(model_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = model_name
	var rig: Dictionary = _Loader.rig_for(path_for(model_name))
	var parts: Dictionary = rig.get("parts", {})
	if _PARTS.has(model_name):
		for part_name in _PARTS[model_name]:
			var pack: Dictionary = parts.get(part_name, {})
			var mesh: ArrayMesh = pack.get("mesh", null)
			if mesh == null:
				continue
			root.add_child(_instance(part_name, mesh, emits(part_name)))
		return root
	var full: ArrayMesh = rig.get("mesh", null)
	if full != null:
		root.add_child(_instance("Mesh", full, false))
	return root


static func _instance(part_name: String, mesh: ArrayMesh, glow: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if glow:
		mi.material_override = _Builder.make_glow_material(glow_color(part_name))
		mi.set_meta("emissive_part", true)
	else:
		mi.material_override = _Builder.make_material()
	return mi
