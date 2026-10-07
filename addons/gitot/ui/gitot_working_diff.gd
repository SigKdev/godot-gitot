## gitot_working_diff.gd
## Working-tree mode of the bottom diff panel: gutter click / Refresh -> `git diff` of ONE script -> hunks.
## Mirrors GitotCommitLogDiff (commit mode). Remembers the wanted file so a late result for a
## script tab the user already left is dropped.
class_name GitotWorkingDiff
extends RefCounted

var _git_engine: GitEngine
var _panel: GitotDiffPanel
var _path: String = "" # res:// path of the file wanted.
var _line: int = -1 # 1-based line to scroll to once shown (-1 = keep the panel's position).


func _init(git_engine: GitEngine, panel: GitotDiffPanel) -> void:
	_git_engine = git_engine
	_panel = panel
	_git_engine.command_completed.connect(_on_command_completed)
	_panel.refresh_requested.connect(_on_refresh_requested)


## Disconnects from shared objects. Call from gitot.gd before freeing the panel.
func teardown() -> void:
	if _git_engine.command_completed.is_connected(_on_command_completed):
		_git_engine.command_completed.disconnect(_on_command_completed)
	if is_instance_valid(_panel) and _panel.refresh_requested.is_connected(_on_refresh_requested):
		_panel.refresh_requested.disconnect(_on_refresh_requested)


## Gutter click: shows the file's diff and scrolls to the clicked hunk.
## @param line: 0-based CodeEdit line (converted to git's 1-based, as GitDiffParser reports).
func show_file(file_path: String, line: int) -> void:
	_request(file_path, line + 1)


## The panel's Refresh button: reloads the content in place, no re-navigation.
func _on_refresh_requested(file_path: String) -> void:
	_request(file_path, -1)


func _request(file_path: String, line: int) -> void:
	_path = file_path
	_line = line
	_git_engine.diff_full(ProjectSettings.globalize_path(file_path))


## Applies a finished DIFF_FULL, dropping it if the active script tab is no longer the requested file.
func _on_command_completed(
	command: GitEngine.Command,
	exit_code: int,
	output: Array[String],
	_context: Dictionary,
) -> void:
	if command != GitEngine.Command.DIFF_FULL or exit_code != 0 or output.is_empty():
		return
	var current_script: Script = EditorInterface.get_script_editor().get_current_script()
	if not current_script or current_script.resource_path != _path:
		return
	var raw: String = output[0].left(GitotDiffPanel.MAX_DIFF_CHARS)
	var files: Array[Dictionary] = GitDiffParser.parse_full(raw)
	if files.is_empty():
		return
	var hunks: Array[Dictionary] = []
	hunks.assign(files[0]["hunks"])
	_panel.set_commit_mode(false)
	_panel.show_diff(_path, hunks)
	_panel.jump_to_source_line(_line)
