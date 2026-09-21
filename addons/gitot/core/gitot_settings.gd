## gitot_settings.gd
## Static for user-configurable plugin settings.
## Storage: user://gitot_settings.cfg - plaintext, non-sensitive values only.
class_name GitotSettings
extends RefCounted

const PATH: String = "user://gitot_settings.cfg"
const SECTION: String = "settings"

const DEFAULTS: Dictionary = {
	"large_file_mb": 50,
	"confirm_push": true,
	"auto_refresh_on_focus": true,
	"github_issues_enabled": true,
}

## In-memory cache, populated on first read - avoids a ConfigFile disk load per get_value() call.
static var _cache: Dictionary = { }
static var _loaded: bool = false


## Reads a setting; falls back to its default if unset or file missing.
static func get_value(key: String) -> Variant:
	_ensure_loaded()
	return _cache.get(key, DEFAULTS.get(key))


## Writes a single setting, persists immediately, and keeps the cache in sync.
static func set_value(key: String, value: Variant) -> void:
	_ensure_loaded()
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
	for key in DEFAULTS:
		_cache[key] = cfg.get_value(SECTION, key, DEFAULTS[key])
	_loaded = true
