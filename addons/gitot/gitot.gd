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

## Reference to the GitEngine instance.
var _git_engine: GitEngine

## Reference to the dock UI instance, kept for clean removal on exit.
var _dock: GitotDock
var _diff_gutter: GitotDiffGutter
var _sync_orchestrator: GitSyncOrchestrator

var _github_panel: Control

#region Plugin Initialisation

## Initializes the plugin when it is added to the editor.
func _enter_tree() -> void:
	# Suppress interactive credential prompts for this editor session.
	# Must be set before any git network command runs.
	OS.set_environment("GIT_TERMINAL_PROMPT", "0")

	# Binary failsafe: hard stop if git isn't on PATH.
	if not GitEngine.is_git_available():
		GitotLogger.x("'git' binary not found in system PATH. Plugin DISABLED!")
		return

	# Create the GitEngine instance.
	_git_engine = GitEngine.new()
	_git_engine.command_completed.connect(_on_git_command_completed)

	# Create the GitotDiffGutter instance.
	_diff_gutter = GitotDiffGutter.new(_git_engine)

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

	GitotLogger.s("'git' binary verified. Plugin ready!")


## Cleans up the plugin on exit.
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

	if _git_engine:
		_git_engine.teardown()
		_git_engine = null

	if _github_panel:
		_github_panel.queue_free()
		_github_panel = null

#endregion


## Required for the panel to appear as a selectable main-screen tab (2D/3D/Script/AssetLib row).
func _has_main_screen() -> bool:
	return GitotSettings.get_value("github_issues_enabled")


## Called by the editor when the user switches to/away from this tab.
func _make_visible(visible: bool) -> void:
	if _github_panel:
		_github_panel.visible = visible
		if visible and not _github_panel.has_fetched:
			_github_panel.has_fetched = true
			_github_panel.fetch_current_repo_issues()


## main-screen Tab label text.
func _get_plugin_name() -> String:
	return "Gitot Issues"


## main-screen Tab icon.
func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("Debug", "EditorIcons")


## Decides which finished commands should trigger an automatic status refresh.
## Kept here (composition root) rather than in GitEngine (generic executor)
## or GitotDock (UI painter) — neither should own this workflow decision.
func _on_git_command_completed(command: GitEngine.Command, _exit_code: int, _output: Array) -> void:
	if command in STATUS_TRIGGERING_COMMANDS:
		_git_engine.run_fast(GitEngine.Command.STATUS, GitEngine.STATUS_ARGS)
		_git_engine.get_ahead_behind()
		_dock.refresh_log() # exposed passthrough


## Triggers gutter refresh on script save
## (can be unreliable - manual refresh in dock is the reliable fallback).
func _on_resource_saved(resource: Resource) -> void:
	if resource is Script:
		_diff_gutter.refresh_current_script()
