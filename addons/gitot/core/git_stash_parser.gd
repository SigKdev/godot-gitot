## git_stash_parser.gd
## Parses `git stash list` output formatted with GitEngine.STASH_LIST_FORMAT.
class_name GitStashParser
extends RefCounted

## "WIP on" = git's default subject (no -m), "On" = custom -m.
## Branch names can't contain ":" (git ref rules), so the first ": " splits reliably.
const SUBJECT_PATTERN: String = "^(?:WIP on|On) ([^:]+): (.*)$"

## Lazy-compiled: _static_init() is unreliable on hot-reload.
static var _subject_re: RegEx = null


## @return: Array[GitStashEntry]. Empty on blank input (no stashes).
static func parse(raw: String) -> Array[GitStashEntry]:
	var entries: Array[GitStashEntry] = []
	var text: String = raw.strip_edges()
	if text.is_empty():
		return entries

	for line: String in text.split("\n", false):
		var fields: PackedStringArray = line.strip_edges().split(GitEngine.UNIT_SEP)
		if fields.size() != 5:
			continue # Malformed line: skip it.
		var parts: PackedStringArray = _split_subject(fields[4])
		var entry: GitStashEntry = GitStashEntry.new()
		# "stash@{n}" -> n. Parsed, not counted, so a skipped line can't shift indices.
		entry.index = fields[0].trim_prefix("stash@{").trim_suffix("}").to_int()
		entry.commit_hash = fields[1]
		entry.date_relative = fields[2]
		entry.date_full = fields[3]
		entry.branch = parts[0]
		entry.name = parts[1]
		entries.append(entry)
	return entries


## @return: [branch, name]. No match -> ["", raw subject], so nothing is ever lost.
static func _split_subject(subject: String) -> PackedStringArray:
	if _subject_re == null:
		_subject_re = RegEx.create_from_string(SUBJECT_PATTERN)
	var m: RegExMatch = _subject_re.search(subject)
	if m == null:
		return PackedStringArray(["", subject])
	return PackedStringArray([m.get_string(1), m.get_string(2)])
