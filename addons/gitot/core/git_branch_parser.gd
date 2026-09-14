## git_branch_parser.gd
## Parses `git branch -a --format="%(refname)|%(HEAD)"` output.
## Static parser, no state — same pattern as GitStatusParser.
class_name GitBranchParser
extends RefCounted


## Parses raw branch list output into a typed array of branch entries.
## @param raw_output: stdout from GitEngine.list_branches().
## @return: Array[Dictionary], each {"name": String, "is_current": bool, "is_remote": bool}.
static func parse(raw_output: String) -> Array[Dictionary]:
	var branches: Array[Dictionary] = []
	for line in raw_output.split("\n", true):
		var parts: PackedStringArray = line.split("|", true, 1)
		if parts.size() < 2:
			continue
		var refname: String = parts[0].strip_edges()
		# Skip origin/HEAD: a symbolic-ref alias, not a real checkout-able branch.
		if refname.is_empty() or refname.ends_with("/HEAD"):
			continue
		var is_remote: bool = refname.begins_with("refs/remotes/")
		var prefix: String = "refs/remotes/" if is_remote else "refs/heads/"
		branches.append({
			"name": refname.trim_prefix(prefix),
			"is_current": parts[1].strip_edges() == "*",
			"is_remote": is_remote,
		})
	return branches
