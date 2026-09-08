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
const STATUS_TRIGGERING_COMMANDS: PackedStringArray = ["stage", "unstage", "commit", "push", "pull"]

const GithubPanelScene: PackedScene = preload("res://addons/gitot/ui/github_panel.tscn")

## Reference to the GitEngine instance.
var git_engine: GitEngine

## Reference to the dock UI instance, kept for clean removal on exit.
var dock: GitotDock
var diff_gutter: GitotDiffGutter

var github_panel: Control


## Initializes the plugin when it is added to the editor.
func _enter_tree() -> void:
	# Suppress interactive credential prompts for this editor session.
	# Must be set before any git network command runs.
	OS.set_environment("GIT_TERMINAL_PROMPT", "0")

	# Binary failsafe: hard stop if git isn't on PATH.
	if not GitEngine.is_git_available():
		print_rich("[color=red]Gitot ERROR: 'git' binary not found in system PATH. Plugin disabled.[/color]")
		return

	# Create the GitEngine instance.
	git_engine = GitEngine.new()
	git_engine.command_completed.connect(_on_git_command_completed)

	# Create the GitotDiffGutter instance.
	diff_gutter = GitotDiffGutter.new(git_engine)

	# Connect the resource saved signal to the gutter refresh function.
	resource_saved.connect(_on_resource_saved)

	# Load and register the dock UI in the editor's left-upper dock slot.
	dock = preload("res://addons/gitot/ui/gitot_dock.tscn").instantiate()
	dock.set_git_engine(git_engine)
	dock.set_diff_gutter(diff_gutter)
	add_control_to_dock(DOCK_SLOT_LEFT_UL, dock)

	github_panel = GithubPanelScene.instantiate()
	github_panel.set_git_engine(git_engine)
	EditorInterface.get_editor_main_screen().add_child(github_panel)
	github_panel.hide() # Godot calls _make_visible(true) when the tab is selected

	print_rich("[color=green]Gitot: 'git' binary verified. Plugin ready.[/color]")


## Decides which finished commands should trigger an automatic status refresh.
## Kept here (composition root) rather than in GitEngine (generic executor)
## or GitotDock (UI painter) — neither should own this workflow decision.
func _on_git_command_completed(command_name: String, _exit_code: int, _output: Array) -> void:
	if command_name in STATUS_TRIGGERING_COMMANDS:
		git_engine.run_fast("status", ["status", "--porcelain=v2"])


## Triggers gutter refresh on script save
## (can be unreliable - manual refresh in dock is the reliable fallback).
func _on_resource_saved(resource: Resource) -> void:
	if resource is Script:
		diff_gutter.refresh_current_script()


## Required for the panel to appear as a selectable main-screen tab (2D/3D/Script/AssetLib row).
func _has_main_screen() -> bool:
	return true


## Called by the editor when the user switches to/away from this tab.
func _make_visible(visible: bool) -> void:
	if github_panel:
		github_panel.visible = visible
		if visible and not github_panel.has_fetched:
			github_panel.has_fetched = true
			github_panel.fetch_current_repo_issues()


## Tab label text.
func _get_plugin_name() -> String:
	return "Gitot"


## Tab icon — using a built-in editor icon avoids shipping an asset for v1.
func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("ExternalLink", "EditorIcons")


## Cleans up the plugin on exit.
func _exit_tree() -> void:
	if resource_saved.is_connected(_on_resource_saved):
		resource_saved.disconnect(_on_resource_saved)

	if dock:
		dock.teardown()
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null

	if diff_gutter:
		diff_gutter.teardown()
		diff_gutter = null

	if git_engine and git_engine.command_completed.is_connected(_on_git_command_completed):
		git_engine.command_completed.disconnect(_on_git_command_completed)

	if git_engine:
		git_engine.teardown()
	git_engine = null

	if github_panel:
		github_panel.queue_free()
