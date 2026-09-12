## git_branch_parser.gd
## Parses `git branch --format="%(refname:short)|%(HEAD)"` output.
## Static parser, no state — same pattern as GitStatusParser.
class_name GitBranchParser
extends RefCounted


## Parses raw branch list output into a typed array of branch entries.
## @param raw_output: stdout from GitEngine.list_branches().
## @return: Array[Dictionary], each {"name": String, "is_current": bool}.
static func parse(raw_output: String) -> Array[Dictionary]:
	var branches: Array[Dictionary] = []
	for line in raw_output.split("\n", true):
		# allow_empty=true is required: %(HEAD) is empty (not "*") for
		# non-current branches, so split() with allow_empty=false would
		# silently drop that trailing empty field and break parsing.
		var parts: PackedStringArray = line.split("|", true, 1)
		if parts.size() < 2 or parts[0].strip_edges().is_empty():
			continue
		branches.append({
			"name": parts[0].strip_edges(),
			"is_current": parts[1].strip_edges() == "*",
		})
	return branches
