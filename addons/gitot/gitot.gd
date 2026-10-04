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
	GitEngine.Command.AMEND,
	GitEngine.Command.PUSH,
	GitEngine.Command.PULL,
	GitEngine.Command.SWITCH,
	GitEngine.Command.CREATE_BRANCH,
	GitEngine.Command.STASH,
	GitEngine.Command.STASH_POP,
	GitEngine.Command.STASH_DROP,
	GitEngine.Command.RESTORE_FILE,
	GitEngine.Command.LFS_TRACK,
	GitEngine.Command.LFS_UNTRACK,
]

const GithubPanelScene: PackedScene = preload("res://addons/gitot/ui/github_panel.tscn")

const GitotDiffPanelScene: PackedScene = preload("res://addons/gitot/ui/gitot_diff_panel.tscn")

const GitotLfsPanelScene: PackedScene = preload("res://addons/gitot/ui/gitot_lfs_panel.tscn")

var _git_engine: GitEngine
var _dock: GitotDock
var _diff_gutter: GitotDiffGutter
var _sync_orchestrator: GitSyncOrchestrator
var _github_panel: Control
var _diff_panel: GitotDiffPanel
var _pending_diff_path: String = ""
var _pending_diff_line: int = -1
var _files_refresh_queued: bool = false
var _commit_log_diff: GitotCommitLogDiff

var _lfs: GitLfs
var _lfs_panel: GitotLfsPanel


#region Plugin Initialisation
func _enter_tree() -> void:
	# Suppress interactive credential prompts for this session.
	OS.set_environment("GIT_TERMINAL_PROMPT", "0")

	# Binary failsafe: hard stop if git isn't on PATH.
	var git_version: String = GitEngine.get_git_version()
	if git_version.is_empty():
		GitotLogger.x("'git' binary not found in system PATH. Plugin DISABLED!")
		return

	_git_engine = GitEngine.new()
	_git_engine.command_completed.connect(_on_git_command_completed)
	_lfs = GitLfs.new(_git_engine) # Before the dock: the Size Guard needs it.
	_lfs.ready_changed.connect(_on_lfs_ready_changed)

	_diff_gutter = GitotDiffGutter.new(_git_engine)
	_diff_gutter.hunk_clicked.connect(_on_hunk_clicked)
	_git_engine.command_completed.connect(_on_diff_full_result)

	_sync_orchestrator = GitSyncOrchestrator.new(_git_engine)

	# Saves refresh the diff gutter (scripts) and the Staged/Unstaged lists (any file).
	resource_saved.connect(_on_resource_saved)
	scene_saved.connect(_on_scene_saved)

	# Load and register the dock UI in the editor's right-upper dock slot.
	_dock = preload("res://addons/gitot/ui/gitot_dock.tscn").instantiate()
	_dock.set_git_engine(_git_engine)
	_dock.set_diff_gutter(_diff_gutter)
	_dock.set_sync_orchestrator(_sync_orchestrator)
	_dock.set_lfs(_lfs)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

	if GitotSettings.get_value("github_issues_enabled"):
		_github_panel = GithubPanelScene.instantiate()
		_github_panel.set_git_engine(_git_engine)
		EditorInterface.get_editor_main_screen().add_child(_github_panel)
		_github_panel.hide() # Godot calls _make_visible(true) when tab is selected

	var lfs_version: String = GitEngine.get_lfs_version()
	GitotLogger.s("'git' binary verified. Plugin ready!")
	GitotLogger.i(
		"git v%s | LFS v%s"
		% [git_version, "not installed" if lfs_version.is_empty() else lfs_version],
	)

	_lfs_panel = GitotLfsPanelScene.instantiate()
	_lfs_panel.set_lfs(_lfs) # Before entering the tree: _ready() needs it.
	add_control_to_bottom_panel(_lfs_panel, "Gitot LFS")
	# The Size Guard exemption and the Track-with-LFS button need the LFS state: detect at startup
	# (async, two quick git calls). The panel's own refresh is lazy.
	_lfs.detect_state()

	_diff_panel = GitotDiffPanelScene.instantiate()
	add_control_to_bottom_panel(_diff_panel, "Gitot Diff")
	_diff_panel.refresh_requested.connect(_on_diff_refresh_requested)
	_commit_log_diff = GitotCommitLogDiff.new(_git_engine, _diff_panel)
	_dock.commit_selected.connect(_on_commit_selected)


func _exit_tree() -> void:
	OS.unset_environment("GIT_TERMINAL_PROMPT")

	if resource_saved.is_connected(_on_resource_saved):
		resource_saved.disconnect(_on_resource_saved)
	if scene_saved.is_connected(_on_scene_saved):
		scene_saved.disconnect(_on_scene_saved)

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

	if _lfs:
		_lfs.teardown()
		_lfs = null

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

	if _lfs_panel:
		remove_control_from_bottom_panel(_lfs_panel)
		_lfs_panel.queue_free()
		_lfs_panel = null
#endregion


#region Gitot Issues Panel
## Required for the panel to appear as a selectable main-screen tab (2D/3D/Script/AssetLib row).
func _has_main_screen() -> bool:
	return GitotSettings.get_value("github_issues_enabled")


func _get_plugin_name() -> String:
	return "Gitot Issues"


func _get_plugin_icon() -> Texture2D:
	return GitotUi.get_icon("Debug")


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
	exit_code: int,
	output: Array[String],
	_context: Dictionary,
) -> void:
	# A failed stage/unstage aborts the WHOLE batch (git add is all-or-nothing): never fail silently.
	if exit_code != 0 and command in [GitEngine.Command.STAGE, GitEngine.Command.UNSTAGE]:
		GitotLogger.e("%s failed." % GitEngine.Command.keys()[command].capitalize())
		if not output.is_empty():
			GitotLogger.g(output[0])
	if command in STATUS_TRIGGERING_COMMANDS:
		_dock.refresh_status() # status + ahead/behind + history + shelf
		if _lfs_panel:
			_lfs_panel.refresh_files() # LFS file list follows stage/commit/switch/pull


## The Size Guard exemption depends on LFS being READY: re-evaluate the trees when that flips.
func _on_lfs_ready_changed() -> void:
	if _dock:
		_dock.refresh_status()


## Triggers gutter refresh on script save
## (can be unreliable - manual refresh in dock is the reliable fallback).
func _on_resource_saved(resource: Resource) -> void:
	if resource is Script:
		_diff_gutter.refresh_current_script()
	_queue_files_refresh()


func _on_scene_saved(_path: String) -> void:
	_queue_files_refresh()


## Coalesces a burst of saves (Alt+S saves every open file) into ONE status call on the next
## idle moment, instead of one `git status` per file.
func _queue_files_refresh() -> void:
	if _files_refresh_queued:
		return
	_files_refresh_queued = true
	_flush_files_refresh.call_deferred()


func _flush_files_refresh() -> void:
	_files_refresh_queued = false
	if _dock:
		_dock.refresh_files()


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
	_context: Dictionary,
) -> void:
	if command != GitEngine.Command.DIFF_FULL or exit_code != 0 or output.is_empty():
		return
	var current_script: Script = EditorInterface.get_script_editor().get_current_script()
	if not current_script or current_script.resource_path != _pending_diff_path:
		return
	var raw: String = output[0]
	if raw.length() > GitotCommitLogDiff.MAX_DIFF_CHARS:
		raw = raw.substr(0, GitotCommitLogDiff.MAX_DIFF_CHARS)
	var files: Array[Dictionary] = GitDiffParser.parse_full(raw)
	if files.is_empty():
		return
	var hunks: Array[Dictionary] = []
	hunks.assign(files[0]["hunks"])
	_diff_panel.set_commit_mode(false)
	_diff_panel.show_diff(_pending_diff_path, hunks)
	_diff_panel.jump_to_source_line(_pending_diff_line)
