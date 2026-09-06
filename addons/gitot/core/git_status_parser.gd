## git_status_parser.gd
## Parses `git status --porcelain=v2` output into categorized file lists.
## Reference: https://git-scm.com/docs/git-status#_porcelain_format_version_2
class_name GitStatusParser
extends RefCounted

## Parses porcelain v2 raw output into staged/unstaged/untracked path arrays.
## @param raw_output: full stdout string from `git status --porcelain=v2`.
## @return: Dictionary with keys "staged", "unstaged", "untracked" (Array[String]).
static func parse(raw_output: String) -> Dictionary:
	var result: Dictionary = {"staged": [], "unstaged": [], "untracked": []}

	for line: String in raw_output.split("\n", false):
		if line.is_empty():
			continue

		match line[0]:
			"?": # Untracked file — format: "? <path>"
				result["untracked"].append(line.substr(2))
			"1", "2": # Ordinary / renamed entry — format: "<type> <XY> ... <path>"
				var parts: PackedStringArray = line.split(" ", false)
				if parts.size() < 2:
					continue
				var xy: String = parts[1]
				var path: String = parts[-1] # Last field; simplification, no quoted-path support (MVP scope)
				if xy[0] != ".":
					result["staged"].append(path)
				if xy[1] != ".":
					result["unstaged"].append(path)
			# "u" (unmerged/conflict) and "!" (ignored) intentionally unhandled in MVP.

	return result
