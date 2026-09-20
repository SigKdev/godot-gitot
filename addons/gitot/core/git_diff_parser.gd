## git_diff_parser.gd
## Parses `git diff -U0` hunk headers into line-state data for gutter coloring.
## Reference: https://git-scm.com/docs/git-diff (unified diff hunk format)
class_name GitDiffParser
extends RefCounted

## Line state constants for gutter coloring.
enum LineState {
	ADDED,
	MODIFIED,
}

static var _new_hunk_regex: RegEx
static var _old_hunk_regex: RegEx


static func parse(raw_diff: String) -> Dictionary:
	# Lazy compile-once: avoids relying on _static_init() timing during
	# editor plugin hot-reload, which is not always reliable.
	if not _new_hunk_regex:
		_new_hunk_regex = RegEx.create_from_string("\\+(\\d+)(?:,(\\d+))?")
	if not _old_hunk_regex:
		_old_hunk_regex = RegEx.create_from_string("-(\\d+)(?:,(\\d+))?")

	var result: Dictionary = { }

	for line: String in raw_diff.split("\n", false):
		if not line.begins_with("@@"):
			continue

		var match_result: RegExMatch = _new_hunk_regex.search(line)
		if not match_result:
			continue

		var new_start: int = match_result.get_string(1).to_int()
		var new_count: int = match_result.get_string(2).to_int() if match_result.get_string(2) != "" else 1

		var old_count: int = _old_count(line)
		var state: LineState = LineState.ADDED if old_count == 0 else LineState.MODIFIED

		for i in range(new_count):
			result[new_start + i] = state

	return result


## Parses a full-context `git diff -U3` into per-file hunks for the bottom-dock viewer.
## Multi-file-ready shape (single entry for v1's single-file -- <path> diffs; reused
## as-is for future commit-diff support — see Command.DIFF_COMMIT, not yet implemented).
## Line numbers are 1-based, matching git's own convention (same as parse()'s hunk parsing).
## @return: [{file: String, hunks: [{old_start: int, new_start: int, lines: [{type, text}]}]}]
##   type is "add" / "del" / "context". Malformed input yields an empty Array.
static func parse_full(raw_diff: String) -> Array[Dictionary]:
	if not _new_hunk_regex:
		_new_hunk_regex = RegEx.create_from_string("\\+(\\d+)(?:,(\\d+))?")
	if not _old_hunk_regex:
		_old_hunk_regex = RegEx.create_from_string("-(\\d+)(?:,(\\d+))?")

	var files: Array[Dictionary] = []
	var current_file: Dictionary = { }
	var current_hunk: Dictionary = { }

	for line: String in raw_diff.split("\n", false):
		if line.begins_with("diff --git"):
			_flush_hunk(current_file, current_hunk)
			current_hunk = { }
			if not current_file.is_empty():
				files.append(current_file)
			current_file = { "file": "", "hunks": [] }
		elif line.begins_with("+++ b/"):
			current_file["file"] = line.trim_prefix("+++ b/")
		elif line.begins_with("@@"):
			_flush_hunk(current_file, current_hunk)
			var new_match: RegExMatch = _new_hunk_regex.search(line)
			var old_match: RegExMatch = _old_hunk_regex.search(line)
			if not new_match or not old_match:
				current_hunk = { }
				continue
			current_hunk = {
				"old_start": old_match.get_string(1).to_int(),
				"new_start": new_match.get_string(1).to_int(),
				"lines": [],
			}
		elif not current_hunk.is_empty():
			if line.begins_with("+"):
				current_hunk["lines"].append({ "type": "add", "text": line.substr(1) })
			elif line.begins_with("-"):
				current_hunk["lines"].append({ "type": "del", "text": line.substr(1) })
			else:
				current_hunk["lines"].append({ "type": "context", "text": line.substr(1) })

	_flush_hunk(current_file, current_hunk)
	if not current_file.is_empty():
		files.append(current_file)
	return files


## Appends a completed hunk to its file entry, if one is in progress.
static func _flush_hunk(file: Dictionary, hunk: Dictionary) -> void:
	if not hunk.is_empty() and not file.is_empty():
		file["hunks"].append(hunk)


## Returns the old hunk's line count from a unified diff header, or -1 if the header is malformed.
static func _old_count(header: String) -> int:
	var match_result: RegExMatch = _old_hunk_regex.search(header)
	if not match_result:
		return -1
	return match_result.get_string(2).to_int() if match_result.get_string(2) != "" else 1
