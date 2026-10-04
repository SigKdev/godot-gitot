## git_lfs_parser.gd
## Parses Git LFS output: `ls-files --json`, `track --json` and .gitattributes text.
## The man pages do not document the --json schema; the keys used here (files[].name / size / checkout /
## oid) were read from git-lfs's own source (commands/command_ls_files.go, lsFilesObject).
class_name GitLfsParser
extends RefCounted


## @return: Array[Dictionary] with "path", "size" (bytes), "present"
## (true = full object in the working tree, false = pointer only), "oid" (content hash, "" if absent).
## Empty on blank/invalid input.
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
					"oid": str(entry.get("oid", "")),
				}
			)
	return files


## Combines this checkout's LFS files with the ones in the upstream tree (`ls-files @{u}`).
## Every row gets "local" (full object on this computer = "present") and "remote" (the SAME content,
## compared by oid, is in the upstream tree: pushed as of the last fetch). Upstream files missing from
## this checkout are appended as remote-only rows. No upstream -> pass [] -> nothing is "remote".
static func merge_scopes(local_files: Array[Dictionary], remote_files: Array[Dictionary]) -> Array[Dictionary]:
	var remote_by_path: Dictionary[String, String] = { }
	for file: Dictionary in remote_files:
		remote_by_path[file["path"]] = file["oid"]
	var merged: Array[Dictionary] = []
	var local_paths: Dictionary[String, bool] = { }
	for file: Dictionary in local_files:
		local_paths[file["path"]] = true
		var row: Dictionary = file.duplicate()
		row["local"] = file["present"]
		# An unknown oid (older git-lfs) falls back to "same path = same file".
		var remote_oid: String = remote_by_path.get(file["path"], "")
		row["remote"] = remote_by_path.has(file["path"]) and (
			remote_oid == file["oid"] or remote_oid.is_empty() or file["oid"].is_empty()
		)
		merged.append(row)
	for file: Dictionary in remote_files:
		if not local_paths.has(file["path"]):
			var row: Dictionary = file.duplicate()
			row["local"] = false
			row["remote"] = true
			merged.append(row)
	return merged


## Totals for the LFS dashboard, from merge_scopes() rows. Sizes are in bytes.
## "remote_size" = what origin's tree holds as of the last fetch: an ESTIMATE of GitHub storage
## (current files only; GitHub also counts old versions). No LFS quota API exists.
static func summarize(files: Array[Dictionary]) -> Dictionary:
	var stats: Dictionary = {
		"count": files.size(), "total": 0,
		"local": 0, "local_size": 0, "remote": 0, "remote_size": 0,
		"unpushed": 0, "unpushed_size": 0, # Local only: Commit + Push uploads it.
		"to_pull": 0, "to_pull_size": 0, # On origin, pointer here: LFS pull downloads it.
		"missing": 0, # Neither: pointer here, not found on origin.
		"largest_path": "", "largest_size": 0,
	}
	for file: Dictionary in files:
		var size: int = file["size"]
		var local: bool = file["local"]
		var remote: bool = file["remote"]
		stats["total"] += size
		if local:
			stats["local"] += 1
			stats["local_size"] += size
		if remote:
			stats["remote"] += 1
			stats["remote_size"] += size
		if local and not remote:
			stats["unpushed"] += 1
			stats["unpushed_size"] += size
		elif remote and not local:
			stats["to_pull"] += 1
			stats["to_pull_size"] += size
		elif not local and not remote:
			stats["missing"] += 1
		if size > stats["largest_size"]:
			stats["largest_size"] = size
			stats["largest_path"] = file["path"]
	return stats


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
