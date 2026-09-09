## gitot_settings_panel.gd
## Self-contained settings UI. Reads/writes GitotSettings directly.
## No dependency on gitot_dock.gd — purely a UI painter for its own controls.
@tool
extends PanelContainer


func _ready() -> void:
	# Initialize controls from stored (or default) values.
	%LargeFileSpinBox.value = GitotSettings.get_value("large_file_mb")
	%ConfirmPushCheck.button_pressed = GitotSettings.get_value("confirm_push")
	%AutoRefreshCheck.button_pressed = GitotSettings.get_value("auto_refresh_on_focus")

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
