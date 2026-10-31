class_name VegetationVoxelCatalog
extends RefCounted

const _Veg = preload("res://world/vegetation_manager.gd")

const ROOT := "res://assets/voxel/vegetation/lod/"
const LOD0_COLUMNS := 10
const EDGE_DETAIL := true
const _FLOWERS := ["red", "yellow", "blue", "white"]
const SPECIES := {
	"grass_tuft": {"scale": 1.6, "cells": 1},
	"tall_grass": {"scale": 1.4, "cells": 1},
	"flower_red": {"scale": 1.6, "cells": 1},
	"flower_yellow": {"scale": 1.4, "cells": 1},
	"flower_blue": {"scale": 1.4, "cells": 1},
	"flower_white": {"scale": 1.4, "cells": 1},
	"mushroom": {"scale": 1.7, "cells": 1},
	"fern": {"scale": 1.6, "cells": 3},
	"bush": {"scale": 1.2, "cells": 1},
	"reeds": {"scale": 1.3, "cells": 1},
	"sapling": {"scale": 0.5, "cells": 1},
	"tree": {"scale": 1.0, "cells": 1},
}


static func is_authored(plant_id: String) -> bool:
	return plant_id in [
		"tree",
		"sapling",
		"grass_tuft",
		"tall_grass",
		"wildflower",
		"fern",
		"bush",
		"reeds",
		"mushroom",
		"flower_red",
		"flower_yellow",
		"flower_blue",
		"flower_white",
		"flower",
	]


static func model_path(plant_id: String, stage: int, wx: int, wz: int, biome: String, lod: int) -> String:
	var id := plant_id
	var use_stage := stage
	if id == "sapling":
		id = "tree"
		use_stage = 1
	if id == "wildflower" or id == "flower":
		id = "flower_" + _FLOWERS[_variant(wx, wz, 44002) % 4]
	var variant := _variant(wx, wz, 55021) % 3
	use_stage = _clamp_stage(id, use_stage)
	var file := ""
	if id == "tree":
		var species := _species(wx, wz, biome)
		file = "tree_%s_v0_s%d_lod%d.json" % [species, use_stage, 0 if lod <= 0 else 1]
	elif id in ["grass_tuft", "tall_grass", "fern", "bush", "reeds", "mushroom"] or id.begins_with("flower_"):
		file = "%s_v%d_s%d.json" % [id, variant, use_stage]
	else:
		return ""
	return ROOT + file


static func mirror_variant(plant_id: String, wx: int, wz: int) -> int:
	if plant_id == "tree" or plant_id == "sapling":
		return _variant(wx, wz, 55021) % 3
	return 0


static func _clamp_stage(id: String, stage: int) -> int:
	var cap := 2 if id == "tree" or id == "bush" else 1
	return clampi(stage, 0, cap)


static func _variant(wx: int, wz: int, salt: int) -> int:
	return absi(_Veg._hash_seed(wx, wz, salt))


static func _species(wx: int, wz: int, biome: String) -> String:
	var h := _variant(wx, wz, 88002) % 3
	if biome == "mountain" or biome == "highland":
		return "pine"
	if biome == "marsh":
		return "birch"
	if biome == "steppe":
		return "pine" if h != 0 else "birch"
	if biome == "plains":
		return "oak" if h != 2 else "birch"
	return ["oak", "birch", "pine"][h]


static func species_key(plant_id: String, wx: int, wz: int) -> String:
	if plant_id == "wildflower" or plant_id == "flower":
		return "flower_" + _FLOWERS[_variant(wx, wz, 44002) % 4]
	return plant_id


static func species_scale(plant_id: String, wx: int, wz: int) -> float:
	var row: Dictionary = SPECIES.get(species_key(plant_id, wx, wz), {})
	return float(row.get("scale", 1.0))


static func footprint_cells(plant_id: String, wx: int, wz: int) -> int:
	var row: Dictionary = SPECIES.get(species_key(plant_id, wx, wz), {})
	return int(row.get("cells", 1))
