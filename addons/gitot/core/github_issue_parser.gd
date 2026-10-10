## github_issue_parser.gd
## Normalizes raw GitHub issue JSON into flat entries for the UI.
## Static and stateless (same pattern as GitLogParser).
class_name GithubIssueParser
extends RefCounted

## Priority options, lowest -> highest. SSOT for ranking (GitHub exposes no order).
const PRIORITY_ORDER: PackedStringArray = ["Low", "Medium", "High", "Urgent"]

## Maps a GitHub issue type to its git-flow-style branch prefix. Unlisted/unset -> no prefix.
const TYPE_BRANCH_PREFIX: Dictionary = { "Feature": "feature/", "Bug": "bugfix/", "Task": "task/" }

## Name of the org Issue Field holding the priority (in "issue_field_values").
const PRIORITY_FIELD_NAME: String = "Priority"

## Max slug length; keeps generated names readable.
const BRANCH_SLUG_MAX_CHARS: int = 40

## Compiled once on first use: _branch_name() runs per issue. Lazy: a static initializer is not
## reliably re-run on editor hot-reload (the var stays null).
static var _slug_regex: RegEx

## [seconds, unit] largest -> smallest, for relative dates.
const RELATIVE_UNITS: Array = [
	[31536000, "year"],
	[2592000, "month"],
	[604800, "week"],
	[86400, "day"],
	[3600, "hour"],
	[60, "minute"],
]


## Converts the raw API array into entries, skipping pull requests
## (the issues endpoint returns PRs too; they carry a "pull_request" key).
## @return: Array[Dictionary] {number, title, author, date_short, date_relative, created_at,
##          type, priority, priority_rank, labels[{name,color}], body, url, branch_name}.
static func parse(data: Array) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for issue: Dictionary in data:
		if not issue.has("pull_request"):
			entries.append(_to_entry(issue))
	return entries


## Label names of a normalized entry.
static func label_names(entry: Dictionary) -> PackedStringArray:
	var names: PackedStringArray = []
	for label: Dictionary in entry["labels"]:
		names.append(label["name"])
	return names


static func _to_entry(issue: Dictionary) -> Dictionary:
	var created: String = _str(issue, "created_at")
	var priority: String = _priority(issue)
	var number: int = int(issue.get("number", 0)) # JSON numbers arrive as floats.
	var title: String = _str(issue, "title")
	var type: String = _str(_dict(issue.get("type")), "name")
	return {
		"number": number,
		"title": title,
		"author": _str(_dict(issue.get("user")), "login", "unknown"),
		"date_short": created.left(10), # YYYY-MM-DD
		"date_relative": _relative_date(created),
		"created_at": created, # ISO 8601 UTC: sorts correctly as a plain string.
		"type": type,
		"priority": priority,
		"priority_rank": PRIORITY_ORDER.find(priority), # -1 = none/unknown.
		"labels": _labels(issue),
		"body": _str(issue, "body").replace("\r\n", "\n"), # "body" is null when empty.
		"url": _str(issue, "html_url"),
		"branch_name": _branch_name(number, title, type),
	}


## Priority lives in the "issue_field_values" array, not on the issue itself.
static func _priority(issue: Dictionary) -> String:
	var fields: Variant = issue.get("issue_field_values")
	if not fields is Array:
		return ""
	for field: Variant in fields:
		var field_dict: Dictionary = _dict(field)
		if field_dict.get("issue_field_name") == PRIORITY_FIELD_NAME:
			return _str(_dict(field_dict.get("single_select_option")), "name")
	return ""


## "<prefix><number>-<title-slug>" (e.g. "feature/12-fix-login-crash").
## Non-ASCII letters are dropped (kept simple; the user can edit the name).
static func _branch_name(number: int, title: String, type: String) -> String:
	if _slug_regex == null:
		_slug_regex = RegEx.create_from_string("[^a-z0-9]+")
	var slug: String = _slug_regex.sub(title.to_lower(), "-", true).lstrip("-")
	slug = slug.left(BRANCH_SLUG_MAX_CHARS).rstrip("-") # Cut first, then re-trim.
	var prefix: String = TYPE_BRANCH_PREFIX.get(type, "")
	return "%s%d-%s" % [prefix, number, slug] if not slug.is_empty() else "%s%d" % [prefix, number]


static func _labels(issue: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw: Variant = issue.get("labels")
	if raw is Array:
		for label: Variant in raw:
			var label_dict: Dictionary = _dict(label)
			result.append(
				{
					"name": _str(label_dict, "name"),
					"color": _str(label_dict, "color", "ffffff"), # hex, no "#"
				}
			)
	return result


## "3 days ago" style, like git's %cr in the commit history.
static func _relative_date(iso: String) -> String:
	# Time parser expects YYYY-MM-DDTHH:MM:SS, so the trailing "Z" (UTC) is cut.
	var then: int = int(Time.get_unix_time_from_datetime_string(iso.left(19)))
	var delta: int = int(Time.get_unix_time_from_system()) - then
	for unit: Array in RELATIVE_UNITS:
		var count: int = floori(delta / float(unit[0]))
		if count >= 1:
			return "%d %s%s ago" % [count, unit[1], "" if count == 1 else "s"]
	return "just now" # Also covers small negative deltas (clock skew).


## String value, or [param fallback] when missing/null (GitHub sends explicit nulls).
static func _str(dict: Dictionary, key: String, fallback: String = "") -> String:
	var value: Variant = dict.get(key)
	return value as String if value is String else fallback


## Dictionary value, or {} when null or of another type, so nested reads are null-safe.
static func _dict(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else { }
