## gitot_commit_log_diff.gd
## Commit mode of the bottom diff panel: history click -> changed-file list -> per-file diff.
## Engine results carry no request ID and worker threads can finish out of order, so a
## latest-wins gate keeps ONE request in flight and drops results that no longer match
## the newest click.
class_name GitotCommitLogDiff
extends RefCounted

## Render cap (chars): CodeEdit + per-line coloring gets slow past a few thousand lines.
const MAX_DIFF_CHARS: int = 200_000

var _git_engine: GitEngine
var _panel: GitotDiffPanel
var _commit_hash: String = "" # Newest wanted commit ("" = commit mode inactive).
var _path: String = "" # Newest wanted file ("" = file list not loaded yet).
var _in_flight: String = "" # Key of the running request ("" = idle).


func _init(git_engine: GitEngine, panel: GitotDiffPanel) -> void:
	_git_engine = git_engine
	_panel = panel
	_git_engine.command_completed.connect(_on_command_completed)
	_panel.commit_file_selected.connect(_on_file_selected)


## Disconnects from shared objects. Call from gitot.gd before freeing the panel.
func teardown() -> void:
	if _git_engine.command_completed.is_connected(_on_command_completed):
		_git_engine.command_completed.disconnect(_on_command_completed)
	if is_instance_valid(_panel) and _panel.commit_file_selected.is_connected(_on_file_selected):
		_panel.commit_file_selected.disconnect(_on_file_selected)


## Starts (or retargets) commit mode after a history click.
## @param entry: GitLogParser entry; "hash" drives git, the rest feeds the panel header.
func show_commit(entry: Dictionary) -> void:
	_commit_hash = entry["hash"]
	_path = ""
	_panel.show_commit_info(entry) # Header is instant; the file list arrives async.
	_pump()


## Leaves commit mode: any in-flight result now mismatches the key and is dropped.
func cancel() -> void:
	_commit_hash = ""
	_path = ""


func _key() -> String:
	return "%s\n%s" % [_commit_hash, _path]


func _on_file_selected(path: String) -> void:
	if _commit_hash.is_empty():
		return
	_path = path
	_pump()


## Requests the newest wanted state (file list, or one file's diff) unless a request is running.
func _pump() -> void:
	if _commit_hash.is_empty() or not _in_flight.is_empty():
		return
	_in_flight = _key()
	if _path.is_empty():
		_git_engine.get_commit_files(_commit_hash)
	else:
		_git_engine.get_commit_file_diff(_commit_hash, _path)


func _on_command_completed(
		command: GitEngine.Command,
		exit_code: int,
		output: Array[String],
) -> void:
	if command != GitEngine.Command.COMMIT_FILES and command != GitEngine.Command.DIFF_COMMIT:
		return
	var stale: bool = _in_flight != _key()
	_in_flight = ""
	if stale:
		_pump() # Newest click wins: drop this result, fetch what is wanted now.
		return

	var raw: String = output[0] if not output.is_empty() else ""
	if exit_code != 0:
		GitotLogger.e("Could not load commit '%s'." % _commit_hash)
		GitotLogger.g(raw)
		return

	if command == GitEngine.Command.COMMIT_FILES:
		# Auto-selects the first row -> _on_file_selected -> next request.
		_panel.show_commit_files(GitDiffParser.parse_name_status(raw))
	else:
		_show_file_diff(raw)


func _show_file_diff(raw: String) -> void:
	if raw.length() > MAX_DIFF_CHARS:
		GitotLogger.w("Diff of '%s' truncated for display." % _path)
		raw = raw.substr(0, MAX_DIFF_CHARS)
	var files: Array[Dictionary] = GitDiffParser.parse_full(raw)
	var hunks: Array[Dictionary] = []
	if not files.is_empty():
		hunks.assign(files[0]["hunks"])
	# Path comes from the list: parse_full() has no file name for deleted/binary files.
	_panel.show_diff(_path, hunks)
