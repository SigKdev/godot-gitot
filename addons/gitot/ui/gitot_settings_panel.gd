## gitot_settings_panel.gd
## Self-contained settings UI. Reads/writes GitotSettings directly.
## No dependency on gitot_dock.gd
@tool
class_name GitotSettingsPanel
extends PanelContainer

## Emitted after max_stashes is persisted, so the shelf can re-evaluate its cap.
signal stash_cap_changed


func _ready() -> void:
	# Initialize controls from stored (or default) values.
	%LargeFileSpinBox.value = GitotSettings.get_value("large_file_mb")
	%NetworkTimeoutSpinBox.value = GitotSettings.get_value("network_timeout_sec")
	%MaxStashSpinBox.value = GitotSettings.get_value("max_stashes")
	%ConfirmPushCheck.button_pressed = GitotSettings.get_value("confirm_push")
	%AutoRefreshCheck.button_pressed = GitotSettings.get_value("auto_refresh_on_focus")
	%GithubEnabledCheck.button_pressed = GitotSettings.get_value("github_issues_enabled")

	# Persist on change — no intermediate state
	%LargeFileSpinBox.value_changed.connect(
		func(v: float) -> void:
			GitotSettings.set_value("large_file_mb", int(v)),
	)
	%NetworkTimeoutSpinBox.value_changed.connect(
		func(v: float) -> void:
			GitotSettings.set_value("network_timeout_sec", int(v)),
	)
	%MaxStashSpinBox.value_changed.connect(
		func(v: float) -> void:
			GitotSettings.set_value("max_stashes", int(v))
			stash_cap_changed.emit(),
	)
	%ConfirmPushCheck.toggled.connect(
		func(v: bool) -> void:
			GitotSettings.set_value("confirm_push", v),
	)
	%AutoRefreshCheck.toggled.connect(
		func(v: bool) -> void:
			GitotSettings.set_value("auto_refresh_on_focus", v),
	)
	%GithubEnabledCheck.toggled.connect(
		func(v: bool) -> void:
			GitotSettings.set_value("github_issues_enabled", v)
			if not v:
				GithubAuth.clear_token()
				GitotLogger.w(
					"GitHub Issues Tracker disabled. Restart the editor to completely remove the feature."
				),
	)
