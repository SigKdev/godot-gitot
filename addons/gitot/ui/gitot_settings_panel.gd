## gitot_settings_panel.gd
## Self-contained settings UI. Reads/writes GitotSettings directly.
## No dependency on gitot_dock.gd — purely a UI painter for its own controls.
@tool
class_name GitotSettingsPanel
extends PanelContainer


func _ready() -> void:
	# Initialize controls from stored (or default) values.
	%LargeFileSpinBox.value = GitotSettings.get_value("large_file_mb")
	%ConfirmPushCheck.button_pressed = GitotSettings.get_value("confirm_push")
	%AutoRefreshCheck.button_pressed = GitotSettings.get_value("auto_refresh_on_focus")
	%GithubEnabledCheck.button_pressed = GitotSettings.get_value("github_issues_enabled")

	# Persist on change — no intermediate state, each control is its own SSOT write.
	%LargeFileSpinBox.value_changed.connect(
		func(v: float) -> void: GitotSettings.set_value("large_file_mb", int(v))
	)
	%ConfirmPushCheck.toggled.connect(
		func(v: bool) -> void: GitotSettings.set_value("confirm_push", v)
	)
	%AutoRefreshCheck.toggled.connect(
		func(v: bool) -> void: GitotSettings.set_value("auto_refresh_on_focus", v)
	)
	%GithubEnabledCheck.toggled.connect(
		func(v: bool) -> void:
			GitotSettings.set_value("github_issues_enabled", v)
			if not v:
				GithubAuth.clear_token()
				GitotLogger.w("GitHub Issues Tracker disabled. Restart the editor to completely remove the feature.")
	)
