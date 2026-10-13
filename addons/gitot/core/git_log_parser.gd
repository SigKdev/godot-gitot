## git_log_parser.gd
## Parses `git log` output formatted with GitEngine.LOG_FORMAT into entries.
class_name GitLogParser
extends RefCounted


## Parses raw `git log` stdout into commit entries.
## @param raw: stdout from GitEngine.get_log().
## @return: Array[GitCommitEntry]. Empty on blank input (e.g. repo with zero commits).
static func parse(raw: String) -> Array[GitCommitEntry]:
	var entries: Array[GitCommitEntry] = []
	if raw.strip_edges().is_empty():
		return entries

	for line: String in raw.strip_edges().split("\n", false):
		var fields: PackedStringArray = line.split(GitEngine.UNIT_SEP)
		if fields.size() != 5:
			continue # Malformed line: skip it.
		var entry: GitCommitEntry = GitCommitEntry.new()
		entry.commit_hash = fields[0]
		entry.author = fields[1]
		entry.date_relative = fields[2]
		entry.date_short = fields[3]
		entry.message = fields[4]
		entries.append(entry)

	return entries
