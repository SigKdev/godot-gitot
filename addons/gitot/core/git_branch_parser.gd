## git_branch_parser.gd
## Parses `git branch -a` output produced with GitEngine.BRANCH_LIST_FORMAT.
## Static parser, no state — same pattern as GitStatusParser.
class_name GitBranchParser
extends RefCounted

## Column order of GitEngine.BRANCH_LIST_FORMAT - keep both in sync.
enum Field {
	REF,
	HEAD,
	UPSTREAM,
	SYNC,
	TRACK,
	DATE_UNIX,
	DATE_REL,
	DATE_EXACT,
	HASH,
	SUBJECT,
}


## Parses raw branch list output into a typed array of branch entries.
## @param raw_output: stdout from GitEngine.list_branches().
## @return: Array[Dictionary], each:
##   "name", "is_current", "is_remote",
##   "upstream": short upstream ref ("" = none),
##   "sync": locale-independent trackshort (">" ahead, "<" behind, "<>" diverged, "=" in sync),
##   "track": git's own localized tracking text - display only, never parse it,
##   "date_unix": int, "date_relative", "date_exact", "hash", "subject".
static func parse(raw_output: String) -> Array[Dictionary]:
	var branches: Array[Dictionary] = []
	for line: String in raw_output.split("\n", false):
		# maxsplit: a stray separator stays inside the last field (subject) instead of adding fields.
		var f: PackedStringArray = line.split(GitEngine.UNIT_SEP, true, Field.size() - 1)
		if f.size() < Field.size():
			continue
		var refname: String = f[Field.REF].strip_edges()
		# Skip origin/HEAD: a symbolic-ref alias, not a real checkout-able branch.
		if refname.is_empty() or refname.ends_with("/HEAD"):
			continue
		var is_remote: bool = refname.begins_with("refs/remotes/")
		var prefix: String = "refs/remotes/" if is_remote else "refs/heads/"
		branches.append(
			{
				"name": refname.trim_prefix(prefix),
				"is_current": f[Field.HEAD].strip_edges() == "*",
				"is_remote": is_remote,
				"upstream": f[Field.UPSTREAM].strip_edges(),
				"sync": f[Field.SYNC].strip_edges(),
				"track": f[Field.TRACK].strip_edges(),
				"date_unix": f[Field.DATE_UNIX].to_int(),
				"date_relative": f[Field.DATE_REL],
				"date_exact": f[Field.DATE_EXACT],
				"hash": f[Field.HASH],
				"subject": f[Field.SUBJECT].strip_edges(),
			}
		)
	return branches
