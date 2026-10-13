## git_status_entry.gd
## One changed file of `git status` (see GitStatusParser).
## A typed class instead of a Dictionary: a misspelled field is a script error, not a silent null.
class_name GitStatusEntry
extends RefCounted

## Repo-relative path, already unquoted.
var path: String = ""
var status: GitStatusParser.FileStatus = GitStatusParser.FileStatus.MODIFIED


func _init(p_path: String, p_status: GitStatusParser.FileStatus) -> void:
	path = p_path
	status = p_status
