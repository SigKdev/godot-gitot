## gitot_regex.gd
## Compile-once cache for the plugin's RegEx patterns: building a RegEx is the costly part, searching is cheap.
class_name GitotRegex
extends RefCounted

## pattern -> compiled RegEx.
static var _cache: Dictionary[String, RegEx] = { }


## The compiled RegEx of [param pattern], built on first use. Callers keep their pattern as a named const.
static func compiled(pattern: String) -> RegEx:
	if not _cache.has(pattern):
		_cache[pattern] = RegEx.create_from_string(pattern)
	return _cache[pattern]
