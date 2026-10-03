## git_lfs_parser.gd
## Parses Git LFS output: `ls-files --json`, `track --json` and .gitattributes text.
## WARNING: the man pages document --json but NOT its schema. Key names below are
## unverified until compared with real output.
class_name GitLfsParser
extends RefCounted


## @return: Array[Dictionary] with "path", "size" (bytes), "present"
## (true = full object in the working tree, false = pointer only). Empty on blank/invalid input.
static func parse_files(raw: String) -> Array[Dictionary]:
	var files: Array[Dictionary] = []
	for item: Variant in _json_list(raw, "files"):
		if item is Dictionary:
			var entry: Dictionary = item
			files.append(
				{
					"path": GitPath.unquote(str(entry.get("name", ""))),
					"size": int(entry.get("size", 0)),
					"present": bool(entry.get("checkout", false)),
				}
			)
	return files


## Patterns of the active `filter=lfs` rules in .gitattributes text, in file order.
## Root file only: nested, global and info-level rules are not seen.
static func parse_patterns(attributes_text: String) -> PackedStringArray:
	var patterns: PackedStringArray = []
	for line: String in attributes_text.split("\n", false):
		var rule: String = line.strip_edges()
		if rule.begins_with("#") or not rule.contains("filter=lfs"):
			continue
		# The pattern is the first whitespace-separated field.
		patterns.append(rule.replace("\t", " ").split(" ", false)[0])
	return patterns


## Extracts the list under `key` (or a bare top-level array). [] on blank, invalid or null.
static func _json_list(raw: String, key: String) -> Array:
	if raw.strip_edges().is_empty():
		return [] # Nothing to parse.
	var data: Variant = JSON.parse_string(raw) # null on invalid JSON.
	if data is Array:
		return data as Array
	if data is Dictionary:
		var list: Variant = (data as Dictionary).get(key) # null when absent/empty.
		if list is Array:
			return list as Array
	return []
