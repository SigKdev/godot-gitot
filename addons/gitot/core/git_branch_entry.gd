## git_branch_entry.gd
## One row of `git branch -a` output (see GitBranchParser).
## A typed class instead of a Dictionary: a misspelled field is a script error, not a silent null.
class_name GitBranchEntry
extends RefCounted

## Local name ("main") or remote ref without "refs/remotes/" ("origin/main").
var name: String = ""
var is_current: bool = false
var is_remote: bool = false
## Short upstream ref ("" = none).
var upstream: String = ""
## Locale-independent trackshort (">" ahead, "<" behind, "<>" diverged, "=" in sync).
var sync: String = ""
## Git's own localized tracking text - display only, never parse it.
var track: String = ""
var date_unix: int = 0
var date_relative: String = ""
var date_exact: String = ""
var commit_hash: String = ""
var subject: String = ""
## Its copy on origin ("origin/<name>"), "" if none. Set by GitotBranchPanel, not by the parser.
var remote_ref: String = ""
## Tip commit of remote_ref, "" if none.
var remote_hash: String = ""
