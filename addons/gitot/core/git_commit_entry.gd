## git_commit_entry.gd
## One row of `git log` output (see GitLogParser).
## A typed class instead of a Dictionary: a misspelled field is a script error, not a silent null.
class_name GitCommitEntry
extends RefCounted

var commit_hash: String = ""
var author: String = ""
var date_relative: String = ""
var date_short: String = ""
## Subject line.
var message: String = ""
