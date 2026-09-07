## git_diff_parser.gd
## Parses `git diff -U0` hunk headers into line-state data for gutter coloring.
## Reference: https://git-scm.com/docs/git-diff (unified diff hunk format)
class_name GitDiffParser
extends RefCounted

## Line state constants for gutter coloring.
enum LineState {ADDED, MODIFIED}

static var _new_hunk_regex: RegEx
static var _old_hunk_regex: RegEx


static func parse(raw_diff: String) -> Dictionary:
	# Lazy compile-once: avoids relying on _static_init() timing during
	# editor plugin hot-reload, which is not always reliable.
	if not _new_hunk_regex:
		_new_hunk_regex = RegEx.create_from_string("\\+(\\d+)(?:,(\\d+))?")
	if not _old_hunk_regex:
		_old_hunk_regex = RegEx.create_from_string("-(\\d+)(?:,(\\d+))?")

	var result: Dictionary = {}

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


static func _old_count(header: String) -> int:
	var match_result: RegExMatch = _old_hunk_regex.search(header)
	if not match_result:
		return -1
	return match_result.get_string(2).to_int() if match_result.get_string(2) != "" else 1
