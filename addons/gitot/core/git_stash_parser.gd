## git_stash_parser.gd
## Parses `git stash list` output produced with FORMAT.
class_name GitStashParser
extends RefCounted

## "WIP on" = git's default subject (no -m), "On" = custom -m.
## Branch names can't contain ":" (git ref rules), so the first ": " splits reliably.
const SUBJECT_PATTERN: String = "^(?:WIP on|On) ([^:]+): (.*)$"

## `git stash list` format: selector, full hash (stable preview key), relative date, absolute date
## (tooltip), subject. Field order = what parse() reads.
const FORMAT: String = (
	"--format=%gd" + GitFormat.UNIT_SEP + "%H" + GitFormat.UNIT_SEP + "%cr" + GitFormat.UNIT_SEP
	+ "%ci" + GitFormat.UNIT_SEP + "%s"
)


## @return: Array[GitStashEntry]. Empty on blank input (no stashes).
static func parse(raw: String) -> Array[GitStashEntry]:
	var entries: Array[GitStashEntry] = []
	var text: String = raw.strip_edges()
	if text.is_empty():
		return entries

	for line: String in text.split("\n", false):
		var fields: PackedStringArray = line.strip_edges().split(GitFormat.UNIT_SEP)
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
	var m: RegExMatch = GitotRegex.compiled(SUBJECT_PATTERN).search(subject)
	if m == null:
		return PackedStringArray(["", subject])
	return PackedStringArray([m.get_string(1), m.get_string(2)])
