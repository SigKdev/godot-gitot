## gitot_settings.gd
## Static accessors for the user-configurable plugin settings.
## Storage: user://gitot_settings.cfg - plaintext, non-sensitive values only.
class_name GitotSettings
extends RefCounted

const PATH: String = "user://gitot_settings.cfg"
const SECTION: String = "settings"

## Setting keys: always use these, never a bare string, so a typo fails to parse instead of reading null.
const KEY_LARGE_FILE_MB: String = "large_file_mb"
const KEY_NETWORK_TIMEOUT_SEC: String = "network_timeout_sec"
const KEY_MAX_STASHES: String = "max_stashes"
const KEY_CONFIRM_PUSH: String = "confirm_push"
const KEY_CONFIRM_CREATE_BRANCH: String = "confirm_create_branch"
const KEY_CONFIRM_AMEND: String = "confirm_amend"
const KEY_AUTO_REFRESH_ON_FOCUS: String = "auto_refresh_on_focus"
const KEY_GITHUB_ISSUES_ENABLED: String = "github_issues_enabled"
const KEY_LFS_NOTE_VISIBLE: String = "lfs_note_visible"
const KEY_STATUS_LETTERS: String = "status_letters"
const KEY_ECHO_TO_OUTPUT: String = "echo_to_output"

const DEFAULTS: Dictionary[String, Variant] = {
	KEY_LARGE_FILE_MB: 50,
	KEY_NETWORK_TIMEOUT_SEC: 120,
	KEY_MAX_STASHES: 10,
	KEY_CONFIRM_PUSH: true,
	KEY_CONFIRM_CREATE_BRANCH: true,
	KEY_CONFIRM_AMEND: true,
	KEY_AUTO_REFRESH_ON_FOCUS: true,
	KEY_GITHUB_ISSUES_ENABLED: true,
	KEY_LFS_NOTE_VISIBLE: true,
	KEY_STATUS_LETTERS: false,
	KEY_ECHO_TO_OUTPUT: true,
}

## Accepted range (inclusive) of each numeric setting, also the bounds of its spin box. A hand-edited value
## outside it is clamped: a 0 s network timeout would kill every push/pull the moment it starts.
const RANGES: Dictionary[String, Vector2i] = {
	KEY_LARGE_FILE_MB: Vector2i(0, 500), # 0 = Size Guard off.
	KEY_NETWORK_TIMEOUT_SEC: Vector2i(30, 900),
	KEY_MAX_STASHES: Vector2i(1, 50),
}

## In-memory cache, populated on first read - avoids a ConfigFile disk load per get_value() call.
static var _cache: Dictionary[String, Variant] = { }
static var _loaded: bool = false


## Reads a setting; falls back to its default if unset or file missing.
static func get_value(key: String) -> Variant:
	assert(DEFAULTS.has(key), "Unknown setting '%s'." % key)
	_ensure_loaded()
	return _cache.get(key, DEFAULTS.get(key))


## Writes a single setting, persists immediately, and keeps the cache in sync.
static func set_value(key: String, value: Variant) -> void:
	assert(DEFAULTS.has(key), "Unknown setting '%s'." % key)
	_ensure_loaded()
	value = _sanitized(key, value)
	_cache[key] = value
	var cfg := ConfigFile.new()
	cfg.load(PATH) # Error ignored intentionally: missing file = starts empty, still writes.
	cfg.set_value(SECTION, key, value)
	cfg.save(PATH)


## Loads PATH into _cache once per editor session; no-op afterward.
static func _ensure_loaded() -> void:
	if _loaded:
		return
	var cfg := ConfigFile.new()
	cfg.load(PATH) # Error ignored intentionally: missing file = use defaults.
	for key: String in DEFAULTS:
		_cache[key] = _sanitized(key, cfg.get_value(SECTION, key, DEFAULTS[key]))
	_loaded = true


## Keeps a hand-edited value inside what the plugin can work with.
static func _sanitized(key: String, value: Variant) -> Variant:
	if RANGES.has(key):
		var bounds: Vector2i = RANGES[key]
		return clampi(int(value), bounds.x, bounds.y)
	return value
