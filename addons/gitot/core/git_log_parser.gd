## git_log_parser.gd
## Parses `git log` output formatted with GitEngine.LOG_FORMAT into entries.
class_name GitLogParser
extends RefCounted

## Unit Separator - matches GitEngine.LOG_FORMAT's %x1f delimiter.
## Never appears in commit subjects/author names, unlike "|" or "-".
# GDScript doesn't support \x escapes - only \uXXXX (4-digit unicode)
const FIELD_SEP: String = "\u001f"


## Parses raw `git log` stdout into an array of commit dictionaries.
## @param raw: stdout from GitEngine.get_log().
## @return: Array[Dictionary] with keys "hash", "author", "date", "message".
## Empty on blank input (e.g. repo with zero commits).
static func parse(raw: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if raw.strip_edges().is_empty():
		return entries

	for line in raw.strip_edges().split("\n", false):
		var fields: PackedStringArray = line.split(FIELD_SEP)
		if fields.size() != 5:
			continue # Malformed line safeguard - skip rather than crash the UI.
		entries.append({
			"hash": fields[0],
			"author": fields[1],
			"date_relative": fields[2],
			"date_short": fields[3],
			"message": fields[4],
		})

	return entries
