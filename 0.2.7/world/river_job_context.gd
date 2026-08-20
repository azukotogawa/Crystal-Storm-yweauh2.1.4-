# river_job_context.gd
class_name RiverJobContext
extends RefCounted

var patch_cache: Dictionary = {}
var column_river_memo: Dictionary = {}
var local_heal_count: int = 0
var macro_heal_count: int = 0
var patch_lookups: int = 0
var patch_cache_hits: int = 0
