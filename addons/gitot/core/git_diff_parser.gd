## git_diff_parser.gd
## Parses `git diff -U0` hunk headers into line-state data for gutter coloring.
## Reference: https://git-scm.com/docs/git-diff (unified diff hunk format)
class_name GitDiffParser
extends RefCounted

## Line state constants for gutter coloring.
enum LineState { ADDED, MODIFIED }

## Parses raw `git diff -U0` output into a Dictionary of line_number -> LineState.
## Only reads hunk headers (@@ -a,b +c,d @@); ignores actual +/- content lines
## per MVP color-only scope (no hover/content display).
## @param raw_diff: full stdout string from `git diff -U0 --no-ext-diff HEAD -- <file>`.
## @return: Dictionary[int, LineState] mapping new-file line numbers to their state.
static func parse(raw_diff: String) -> Dictionary:
	var result: Dictionary = {}

	for line: String in raw_diff.split("\n", false):
		if not line.begins_with("@@"):
			continue

		# Hunk header format: @@ -old_start,old_count +new_start,new_count @@
		var regex: RegEx = RegEx.new()
		regex.compile("\\+(\\d+)(?:,(\\d+))?")
		var match_result: RegExMatch = regex.search(line)
		if not match_result:
			continue

		var new_start: int = match_result.get_string(1).to_int()
		var new_count: int = match_result.get_string(2).to_int() if match_result.get_string(2) != "" else 1

		# A hunk with old_count 0 (pure addition) marks lines as ADDED;
		# otherwise treat as MODIFIED. Deletions (new_count 0) have no line to color.
		var is_pure_addition: bool = line.contains("-0,0") or (line.contains("-") and not line.contains(",") and new_count > 0 and _old_count(line) == 0)
		var state: LineState = LineState.ADDED if _old_count(line) == 0 else LineState.MODIFIED

		for i in range(new_count):
			result[new_start + i] = state

	return result

## Extracts the old-side line count from a hunk header for add-vs-modify detection.
static func _old_count(header: String) -> int:
	var regex: RegEx = RegEx.new()
	regex.compile("-(\\d+)(?:,(\\d+))?")
	var match_result: RegExMatch = regex.search(header)
	if not match_result:
		return -1
	return match_result.get_string(2).to_int() if match_result.get_string(2) != "" else 1
