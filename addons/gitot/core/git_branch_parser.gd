## git_branch_parser.gd
## Parses `git branch -a` output produced with FORMAT.
## Static and stateless.
class_name GitBranchParser
extends RefCounted

## Column order of FORMAT - keep both in sync.
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

## `git branch -a` format, columns as in Field: refname, HEAD marker, upstream, trackshort, track, commit
## date (unix = sort key, relative = display, exact = tooltip), short hash, subject.
## Unit Separator-delimited: "|" is a valid ref-name character.
const FORMAT: String = (
	"--format=%(refname)" + GitFormat.UNIT_SEP + "%(HEAD)" + GitFormat.UNIT_SEP + "%(upstream:short)"
	+ GitFormat.UNIT_SEP + "%(upstream:trackshort)" + GitFormat.UNIT_SEP + "%(upstream:track)"
	+ GitFormat.UNIT_SEP + "%(committerdate:unix)" + GitFormat.UNIT_SEP + "%(committerdate:relative)"
	+ GitFormat.UNIT_SEP + "%(committerdate:format:%Y-%m-%d %H:%M)" + GitFormat.UNIT_SEP
	+ "%(objectname:short)" + GitFormat.UNIT_SEP + "%(subject)"
)


## Parses raw branch list output into branch entries (remote_ref/remote_hash stay empty here).
## @param raw_output: stdout from GitEngine.list_branches().
static func parse(raw_output: String) -> Array[GitBranchEntry]:
	var branches: Array[GitBranchEntry] = []
	for line: String in raw_output.split("\n", false):
		# maxsplit: a stray separator stays inside the last field (subject) instead of adding fields.
		var f: PackedStringArray = line.split(GitFormat.UNIT_SEP, true, Field.size() - 1)
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
