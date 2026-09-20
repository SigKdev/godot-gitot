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


## Reads a setting; falls back to its default if unset or file missing.
static func get_value(key: String) -> Variant:
	var cfg := ConfigFile.new()
	cfg.load(PATH) # Error ignored intentionally: missing file = use defaults.
	return cfg.get_value(SECTION, key, DEFAULTS.get(key))


## Writes a single setting and persists immediately.
static func set_value(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value(SECTION, key, value)
	cfg.save(PATH)
