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

	# Split the raw output into lines and process each line.
	for line: String in raw_output.split("\n", false):
		# Skip empty lines.
		if line.is_empty():
			continue

		match line[0]:
			"?": # Untracked file — format: "? <path>"
				result["untracked"].append(line.substr(2))
			"1", "2": # Ordinary / renamed entry — format: "<type> <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>"
				# maxsplit=8 keeps everything after the 8th field-separator intact,
				# so paths containing spaces are not shredded.
				var parts: PackedStringArray = line.split(" ", false, 8)
				if parts.size() < 9:
					continue
				var xy: String = parts[1]
				var path: String = parts[8] # Path field; git does not quote paths with plain spaces
				if xy[0] != ".":
					result["staged"].append(path)
				if xy[1] != ".":
					result["unstaged"].append(path)
			# TODO: "u" (unmerged/conflict) and "!" (ignored) intentionally unhandled in MVP.

	return result
