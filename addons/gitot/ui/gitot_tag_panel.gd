## gitot_tag_panel.gd
## Owns the tag-versioning UI: toggles, version-tag formatting, tag input resolution.
## Pure UI unit (SoC) — no knowledge of push/tag git orchestration.
class_name GitotTagPanel
extends RefCounted

var _toggle: CheckButton
var _panel: Control
var _use_project_toggle: CheckButton
var _tag_name_edit: LineEdit
var _use_commit_toggle: CheckButton
var _tag_message_edit: TextEdit


func _init(toggle: CheckButton, panel: Control, use_project_toggle: CheckButton, tag_name_edit: LineEdit, use_commit_toggle: CheckButton, tag_message_edit: TextEdit) -> void:
	_toggle = toggle
	_panel = panel
	_use_project_toggle = use_project_toggle
	_tag_name_edit = tag_name_edit
	_use_commit_toggle = use_commit_toggle
	_tag_message_edit = tag_message_edit

	_toggle.toggled.connect(func(on: bool) -> void:
		_panel.visible = on
		if on:
			_update_project_version_label()
	)
	_use_project_toggle.toggled.connect(func(on: bool) -> void:
		_tag_name_edit.visible = not on
		_update_project_version_label()
	)
	_use_commit_toggle.toggled.connect(func(on: bool) -> void: _tag_message_edit.visible = not on)


## True when the user opted into tagging this push.
func is_enabled() -> bool:
	return _toggle.button_pressed


## Resolves current tag input state for the push orchestration.
## Returns empty tag_name if tag versioning is off — caller treats that as no-tag push.
func get_tag_input(last_commit_message: String) -> Dictionary:
	if not is_enabled():
		return {"tag_name": "", "tag_message": ""}
	var tag_name: String = (
		_format_version_tag(ProjectSettings.get_setting("application/config/version", ""))
		if _use_project_toggle.button_pressed
		else _tag_name_edit.text
	)
	var tag_message: String = (
		last_commit_message
		if _use_commit_toggle.button_pressed
		else _tag_message_edit.text
	)
	return {"tag_name": tag_name, "tag_message": tag_message}


## Prefixes a raw version string with "v" (e.g. "0.3.0" -> "v0.3.0").
## Guards against double-prefixing if the version setting already includes it.
static func _format_version_tag(raw_version: String) -> String:
	if raw_version.is_empty():
		return ""
	return raw_version if raw_version.begins_with("v") else "v" + raw_version


## Reflects the current project version on the toggle label,
## refreshed on tag panel toggle and when the setting is toggled on/off
## in case project.godot may have changed since last check.
func _update_project_version_label() -> void:
	var raw_version: String = ProjectSettings.get_setting("application/config/version", "")
	var display: String = _format_version_tag(raw_version) if not raw_version.is_empty() else "unset"
	_use_project_toggle.text = "Use Project Version (%s)" % display
