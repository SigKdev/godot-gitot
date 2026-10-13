## gitot_settings_panel.gd
## Self-contained settings UI. Reads/writes GitotSettings directly, no dependency on gitot_dock.gd.
@tool
class_name GitotSettingsPanel
extends PanelContainer

## Emitted after max_stashes is persisted, so the shelf can re-evaluate its cap.
signal stash_cap_changed

## Emitted after status_letters is persisted, so the Staged/Unstaged lists repaint.
signal status_display_changed


func _ready() -> void:
	# Each control shows its stored (or default) value and saves every change at once (no Apply button).
	_bind_spin(%LargeFileSpinBox, GitotSettings.KEY_LARGE_FILE_MB)
	_bind_spin(%NetworkTimeoutSpinBox, GitotSettings.KEY_NETWORK_TIMEOUT_SEC)
	_bind_spin(%MaxStashSpinBox, GitotSettings.KEY_MAX_STASHES, stash_cap_changed)
	_bind_check(%ConfirmPushCheck, GitotSettings.KEY_CONFIRM_PUSH)
	_bind_check(%ConfirmCreateBranchCheck, GitotSettings.KEY_CONFIRM_CREATE_BRANCH)
	_bind_check(%ConfirmAmendCheck, GitotSettings.KEY_CONFIRM_AMEND)
	_bind_check(%AutoRefreshCheck, GitotSettings.KEY_AUTO_REFRESH_ON_FOCUS)
	_bind_check(%StatusLettersCheck, GitotSettings.KEY_STATUS_LETTERS, status_display_changed)
	_bind_check(%EchoOutputCheck, GitotSettings.KEY_ECHO_TO_OUTPUT)
	_bind_check(%GithubEnabledCheck, GitotSettings.KEY_GITHUB_ISSUES_ENABLED)
	%GithubEnabledCheck.toggled.connect(_on_github_toggled) # After the save connected above.


## Spin box bounded by the setting's range (GitotSettings.RANGES).
## @param changed: optional signal emitted after each save.
func _bind_spin(spin: SpinBox, key: String, changed: Signal = Signal()) -> void:
	var bounds: Vector2i = GitotSettings.RANGES[key]
	spin.min_value = bounds.x
	spin.max_value = bounds.y
	spin.value = GitotSettings.get_value(key)
	spin.value_changed.connect(_on_value_changed.bind(key, changed))


## @param changed: optional signal emitted after each save.
func _bind_check(check: CheckButton, key: String, changed: Signal = Signal()) -> void:
	check.button_pressed = GitotSettings.get_value(key)
	check.toggled.connect(_on_value_changed.bind(key, changed))


## Saves the new value (a float from a spin box is stored as int, see GitotSettings._sanitized).
func _on_value_changed(value: Variant, key: String, changed: Signal) -> void:
	GitotSettings.set_value(key, value)
	if not changed.is_null():
		changed.emit()


func _on_github_toggled(enabled: bool) -> void:
	if enabled:
		return
	GithubAuth.clear_token()
	GitotLogger.w("GitHub Issues Tracker disabled. Restart the editor to completely remove the feature.")
