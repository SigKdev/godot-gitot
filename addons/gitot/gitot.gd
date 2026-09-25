## Copyright (c) 2026-present SigK - under the MIT License.
##
## A Git workflow plugin for the Godot 4 editor in pure GDScript
## Gitot wraps your system's git binary directly,
## so it inherits your existing SSH/credential setup,
## and the full Git feature set without reimplementing any of it.
## Gitot does not manage credentials!!
##
## https://github.com/SigKdev/godot-gitot
##
## gitot.gd
## Gitot plugin entry point.
## Aborts initialization if Git is unavailable.
@tool
extends EditorPlugin

## Commands that change working tree / index state and require a status refresh.
const STATUS_TRIGGERING_COMMANDS: Array[GitEngine.Command] = [
	GitEngine.Command.STAGE,
	GitEngine.Command.UNSTAGE,
	GitEngine.Command.COMMIT,
	GitEngine.Command.PUSH,
	GitEngine.Command.PULL,
	GitEngine.Command.SWITCH,
	GitEngine.Command.CREATE_BRANCH,
	GitEngine.Command.STASH,
	GitEngine.Command.STASH_POP,
]

const GithubPanelScene: PackedScene = preload("res://addons/gitot/ui/github_panel.tscn")

const GitotDiffPanelScene: PackedScene = preload("res://addons/gitot/ui/gitot_diff_panel.tscn")

var _git_engine: GitEngine
var _dock: GitotDock
var _diff_gutter: GitotDiffGutter
var _sync_orchestrator: GitSyncOrchestrator
var _github_panel: Control
var _diff_panel: GitotDiffPanel
var _pending_diff_path: String = ""
var _pending_diff_line: int = -1
var _commit_log_diff: GitotCommitLogDiff


#region Plugin Initialisation
func _enter_tree() -> void:
	# Suppress interactive credential prompts for this session.
	OS.set_environment("GIT_TERMINAL_PROMPT", "0")

	# Binary failsafe: hard stop if git isn't on PATH.
	if not GitEngine.is_git_available():
		GitotLogger.x("'git' binary not found in system PATH. Plugin DISABLED!")
		return

	_git_engine = GitEngine.new()
	_git_engine.command_completed.connect(_on_git_command_completed)

	_diff_gutter = GitotDiffGutter.new(_git_engine)
	_diff_gutter.hunk_clicked.connect(_on_hunk_clicked)
	_git_engine.command_completed.connect(_on_diff_full_result)

	_sync_orchestrator = GitSyncOrchestrator.new(_git_engine)

	# Connect the resource saved signal to the gutter refresh function.
	resource_saved.connect(_on_resource_saved)

	# Load and register the dock UI in the editor's right-upper dock slot.
	_dock = preload("res://addons/gitot/ui/gitot_dock.tscn").instantiate()
	_dock.set_git_engine(_git_engine)
	_dock.set_diff_gutter(_diff_gutter)
	_dock.set_sync_orchestrator(_sync_orchestrator)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

	if GitotSettings.get_value("github_issues_enabled"):
		_github_panel = GithubPanelScene.instantiate()
		_github_panel.set_git_engine(_git_engine)
		EditorInterface.get_editor_main_screen().add_child(_github_panel)
		_github_panel.hide() # Godot calls _make_visible(true) when tab is selected

	_diff_panel = GitotDiffPanelScene.instantiate()
	add_control_to_bottom_panel(_diff_panel, "Gitot Diff")
	_diff_panel.refresh_requested.connect(_on_diff_refresh_requested)
	_commit_log_diff = GitotCommitLogDiff.new(_git_engine, _diff_panel)
	_dock.commit_selected.connect(_on_commit_selected)

	GitotLogger.s("'git' binary verified. Plugin ready!")


func _exit_tree() -> void:
	OS.unset_environment("GIT_TERMINAL_PROMPT")

	if resource_saved.is_connected(_on_resource_saved):
		resource_saved.disconnect(_on_resource_saved)

	if _dock:
		_dock.teardown()
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null

	if _diff_gutter:
		_diff_gutter.teardown()
		_diff_gutter = null

	if _sync_orchestrator:
		_sync_orchestrator.teardown()
		_sync_orchestrator = null

	if _git_engine and _git_engine.command_completed.is_connected(_on_git_command_completed):
		_git_engine.command_completed.disconnect(_on_git_command_completed)

	if _git_engine and _git_engine.command_completed.is_connected(_on_diff_full_result):
		_git_engine.command_completed.disconnect(_on_diff_full_result)

	if _diff_panel and _diff_panel.refresh_requested.is_connected(_on_diff_refresh_requested):
		_diff_panel.refresh_requested.disconnect(_on_diff_refresh_requested)

	if _git_engine:
		_git_engine.teardown()
		_git_engine = null

	if _github_panel:
		_github_panel.queue_free()
		_github_panel = null

	if _commit_log_diff:
		_commit_log_diff.teardown()
		_commit_log_diff = null

	if _diff_panel:
		remove_control_from_bottom_panel(_diff_panel)
		_diff_panel.queue_free()
		_diff_panel = null
#endregion


#region Gitot Issues Panel
## Required for the panel to appear as a selectable main-screen tab (2D/3D/Script/AssetLib row).
func _has_main_screen() -> bool:
	return GitotSettings.get_value("github_issues_enabled")


func _get_plugin_name() -> String:
	return "Gitot Issues"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("Debug", "EditorIcons")


## Called by the editor when the user switches to/away from the tab.
func _make_visible(visible: bool) -> void:
	if _github_panel:
		_github_panel.visible = visible
		if visible and not _github_panel.has_fetched:
			_github_panel.has_fetched = true
			_github_panel.fetch_current_repo_issues()
#endregion


## Decides which finished commands should trigger an automatic status refresh.
func _on_git_command_completed(
	command: GitEngine.Command,
	_exit_code: int,
	_output: Array[String],
) -> void:
	if command in STATUS_TRIGGERING_COMMANDS:
		_git_engine.run_fast(GitEngine.Command.STATUS, GitEngine.STATUS_ARGS)
		_git_engine.get_ahead_behind()
		_dock.refresh_log() # exposed passthrough


## Triggers gutter refresh on script save
## (can be unreliable - manual refresh in dock is the reliable fallback).
func _on_resource_saved(resource: Resource) -> void:
	if resource is Script:
		_diff_gutter.refresh_current_script()


## Gutter click, request full-context diff. Line/path stored to guard against
## a stale result if the user switches script tabs before git responds.
func _on_hunk_clicked(file_path: String, line: int) -> void:
	_commit_log_diff.cancel()
	_pending_diff_path = file_path
	_pending_diff_line = line + 1 # CodeEdit's 0-based -> git's 1-based (matches GitDiffParser)
	_git_engine.diff_full(ProjectSettings.globalize_path(file_path))
	make_bottom_panel_item_visible(_diff_panel)


## History row clicked: load that commit into the bottom panel and bring it to front.
func _on_commit_selected(entry: Dictionary) -> void:
	_commit_log_diff.show_commit(entry)
	make_bottom_panel_item_visible(_diff_panel)


## Re-fetches the diff for the file currently shown in the panel.
## Refreshes content in place, it doesn't re-navigate (see _on_hunk_clicked).
func _on_diff_refresh_requested(file_path: String) -> void:
	_pending_diff_path = file_path
	_pending_diff_line = -1
	_git_engine.diff_full(ProjectSettings.globalize_path(file_path))


## Applies a finished DIFF_FULL result, discarding it if the active script
## tab no longer matches the file that was requested.
func _on_diff_full_result(
	command: GitEngine.Command,
	exit_code: int,
	output: Array[String],
) -> void:
	if command != GitEngine.Command.DIFF_FULL or exit_code != 0 or output.is_empty():
		return
	var current_script: Script = EditorInterface.get_script_editor().get_current_script()
	if not current_script or current_script.resource_path != _pending_diff_path:
		return
	var files: Array[Dictionary] = GitDiffParser.parse_full(output[0])
	if files.is_empty():
		return
	var hunks: Array[Dictionary] = []
	hunks.assign(files[0]["hunks"])
	_diff_panel.set_commit_mode(false)
	_diff_panel.show_diff(_pending_diff_path, hunks)
	_diff_panel.jump_to_source_line(_pending_diff_line)
