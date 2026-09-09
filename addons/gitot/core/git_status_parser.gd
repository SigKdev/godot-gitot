## git_status_parser.gd
## Parses `git status --porcelain=v2` output into categorized file lists.
## Reference: https://git-scm.com/docs/git-status#_porcelain_format_version_2
class_name GitStatusParser
extends RefCounted

## Visual/semantic category of a file entry, used by the dock for coloring.
enum FileStatus {NEW_FILE, MODIFIED, DELETED, CONFLICT}


## Parses porcelain v2 raw output into staged/unstaged entries.
## @param raw_output: stdout from `git status --porcelain=v2 --untracked-files=all`.
## @return: Dictionary with keys "staged", "unstaged" (Array[Dictionary]),
##          each entry shaped {"path": String, "status": FileStatus}.
static func parse(raw_output: String) -> Dictionary:
	var result: Dictionary = {"staged": [], "unstaged": []}

	for line: String in raw_output.split("\n", false):
		if line.is_empty():
			continue

		match line[0]:
			"?": # Untracked — format: "? <path>"
				result["unstaged"].append({"path": line.substr(2), "status": FileStatus.NEW_FILE})
			"1": # Ordinary entry — format: "<type> <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>"
				var parts: PackedStringArray = line.split(" ", false, 8)
				if parts.size() < 9:
					continue
				var xy: String = parts[1]
				var path: String = parts[8]
				if xy[0] != ".":
					result["staged"].append({"path": path, "status": _status_from_code(xy[0])})
				if xy[1] != ".":
					result["unstaged"].append({"path": path, "status": _status_from_code(xy[1])})
			"u": # Unmerged/conflict — format: "u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>"
				var parts: PackedStringArray = line.split(" ", false, 10)
				if parts.size() < 11:
					continue
				result["unstaged"].append({"path": parts[10], "status": FileStatus.CONFLICT})
			# "!" (ignored) intentionally unhandled.

	return result


## Maps a single porcelain status letter to a display category.
static func _status_from_code(code: String) -> FileStatus:
	match code:
		"D": return FileStatus.DELETED
		"A": return FileStatus.NEW_FILE
		_: return FileStatus.MODIFIED # M, R, C, T, etc.
