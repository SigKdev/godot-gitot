## git_branch_parser.gd
## Parses `git branch -a` output produced with GitEngine.BRANCH_LIST_FORMAT.
## Static and stateless (same pattern as GitStatusParser).
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


## Parses raw branch list output into branch entries (remote_ref/remote_hash stay empty here).
## @param raw_output: stdout from GitEngine.list_branches().
static func parse(raw_output: String) -> Array[GitBranchEntry]:
	var branches: Array[GitBranchEntry] = []
	for line: String in raw_output.split("\n", false):
		# maxsplit: a stray separator stays inside the last field (subject) instead of adding fields.
		var f: PackedStringArray = line.split(GitEngine.UNIT_SEP, true, Field.size() - 1)
		if f.size() < Field.size():
			continue
		var refname: String = f[Field.REF].strip_edges()
		# Skip origin/HEAD: a symbolic-ref alias, not a branch of its own.
		if refname.is_empty() or refname.ends_with("/HEAD"):
			continue
		var entry: GitBranchEntry = GitBranchEntry.new()
		entry.is_remote = refname.begins_with("refs/remotes/")
		entry.name = refname.trim_prefix("refs/remotes/" if entry.is_remote else "refs/heads/")
		entry.is_current = f[Field.HEAD].strip_edges() == "*"
		entry.upstream = f[Field.UPSTREAM].strip_edges()
		entry.sync = f[Field.SYNC].strip_edges()
		entry.track = f[Field.TRACK].strip_edges()
		entry.date_unix = f[Field.DATE_UNIX].to_int()
		entry.date_relative = f[Field.DATE_REL]
		entry.date_exact = f[Field.DATE_EXACT]
		entry.commit_hash = f[Field.HASH]
		entry.subject = f[Field.SUBJECT].strip_edges()
		branches.append(entry)
	return branches
