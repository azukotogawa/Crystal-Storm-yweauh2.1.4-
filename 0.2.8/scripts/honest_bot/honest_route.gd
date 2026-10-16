extends RefCounted


static func from_markdown(text: String) -> Dictionary:
	var mark := text.find("```json")
	if mark < 0:
		return {}
	var start := text.find("\n", mark)
	var end := text.find("```", start + 1)
	if start < 0 or end < 0:
		return {}
	var parsed = JSON.parse_string(text.substr(start + 1, end - start - 1))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


static func from_file(path: String) -> Dictionary:
	return from_markdown(FileAccess.get_file_as_string(path))


static func ids(route: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var features: Array = route.get("features", [])
	for item in features:
		if item is Dictionary:
			out.append(str(item.get("id", "")))
	return out
