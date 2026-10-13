## git_stash_entry.gd
## One row of `git stash list` output (see GitStashParser).
## A typed class instead of a Dictionary: a misspelled field is a script error, not a silent null.
class_name GitStashEntry
extends RefCounted

## n of "stash@{n}": what pop/drop target. Shifts when the stack changes, so identity is commit_hash.
var index: int = 0
var commit_hash: String = ""
var date_relative: String = ""
var date_full: String = ""
## "" if the subject has an unknown shape (see GitStashParser).
var branch: String = ""
var name: String = ""
