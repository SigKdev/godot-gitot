## git_lfs_file.gd
## One Git LFS file (see GitLfsParser): a `ls-files --json` row, later merged with the upstream tree.
## A typed class instead of a Dictionary: a misspelled field is a script error, not a silent null.
class_name GitLfsFile
extends RefCounted

var path: String = ""
## Bytes.
var size: int = 0
## True = full object in the working tree, false = pointer only.
var present: bool = false
## Content hash, "" if git-lfs did not report one.
var oid: String = ""
## Set by GitLfsParser.merge_scopes(): full object on this computer.
var local: bool = false
## Set by GitLfsParser.merge_scopes(): same content in the upstream tree (as of the last fetch).
var remote: bool = false


func _init(p_path: String, p_size: int, p_present: bool = false, p_oid: String = "") -> void:
	path = p_path
	size = p_size
	present = p_present
	oid = p_oid


## Copy with the merged scope flags set; the original is left untouched.
func with_scope(is_local: bool, is_remote: bool) -> GitLfsFile:
	var copy: GitLfsFile = GitLfsFile.new(path, size, present, oid)
	copy.local = is_local
	copy.remote = is_remote
	return copy
