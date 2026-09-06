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

var git_engine: GitEngine

## Reference to the dock UI instance, kept for clean removal on exit.
var dock: GitotDock

var diff_gutter: GitotDiffGutter


func _enter_tree() -> void:
	# 1.2 — Suppress interactive credential prompts for this editor session.
	# Must be set before any git network command runs (Phase 2).
	OS.set_environment("GIT_TERMINAL_PROMPT", "0")

	# 1.1 — Binary failsafe: hard stop if git isn't on PATH.
	if not GitEngine.is_git_available():
		print_rich("[color=red]Gitot ERROR: Git binary verified. Plugin ready.[/color]")
		#push_error("Gitot: 'git' binary not found in system PATH. Plugin disabled.")
		return

	git_engine = GitEngine.new()

	diff_gutter = GitotDiffGutter.new(git_engine)
	resource_saved.connect(_on_resource_saved)

	# Load and register the dock UI in the editor's left-upper dock slot.
	dock = preload("res://addons/gitot/ui/gitot_dock.tscn").instantiate()
	dock.set_git_engine(git_engine)
	dock.set_diff_gutter(diff_gutter)
	add_control_to_dock(DOCK_SLOT_LEFT_UL, dock)

	print_rich("[color=green]Gitot: Git binary verified. Plugin ready.[/color]")


func _on_diff_test(command_name: String, exit_code: int, output: Array) -> void:
	if command_name != "diff" or output.is_empty():
		return
	print(GitDiffParser.parse(output[0]))


## Triggers gutter refresh on script save (best-effort; unreliable when a .git
## folder is present — manual refresh in dock is the reliable fallback).
func _on_resource_saved(resource: Resource) -> void:
	if resource is Script:
		diff_gutter.refresh_current_script()


func _exit_tree() -> void:
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
	if resource_saved.is_connected(_on_resource_saved):
		resource_saved.disconnect(_on_resource_saved)
