## gitot_commit_log_diff.gd
## Commit mode of the bottom diff panel: history click -> changed-file list -> per-file diff.
## Latest wins: ONE request runs at a time (cheap on a low-end PC while arrowing through history);
## each request carries what it asked for, and a result that no longer matches the newest click is
## dropped and the newest state is fetched instead.
class_name GitotCommitLogDiff
extends RefCounted

var _git_engine: GitEngine
var _panel: GitotDiffPanel
var _commit_hash: String = "" # Newest wanted commit ("" = commit mode inactive).
var _path: String = "" # Newest wanted file ("" = file list not loaded yet).
var _busy: bool = false # A request is running.


func _init(git_engine: GitEngine, panel: GitotDiffPanel) -> void:
	_git_engine = git_engine
	_panel = panel
	_panel.commit_file_selected.connect(_on_file_selected)
	_panel.restore_file_requested.connect(_on_restore_requested)


## Disconnects from shared objects. Call from gitot.gd before freeing the panel.
func teardown() -> void:
	if is_instance_valid(_panel) and _panel.commit_file_selected.is_connected(_on_file_selected):
		_panel.commit_file_selected.disconnect(_on_file_selected)
	if is_instance_valid(_panel) and _panel.restore_file_requested.is_connected(
			_on_restore_requested
		):
		_panel.restore_file_requested.disconnect(_on_restore_requested)


## Starts (or retargets) commit mode after a history click.
## @param entry: the clicked commit; its hash drives git, the rest feeds the panel header.
func show_commit(entry: GitCommitEntry) -> void:
	_commit_hash = entry.commit_hash
	_path = ""
	_panel.show_commit_info(entry) # Header is instant; the file list arrives async.
	_pump()


## Leaves commit mode: any in-flight result now mismatches and is dropped.
func cancel() -> void:
	_commit_hash = ""
	_path = ""


func _on_file_selected(path: String) -> void:
	if _commit_hash.is_empty():
		return
	_path = path
	_pump()


## Requests the newest wanted state (file list, or one file's diff) unless a request is running.
func _pump() -> void:
	if _commit_hash.is_empty() or _busy:
		return
	_busy = true
	if _path.is_empty():
		_git_engine.get_commit_files(_commit_hash, _on_files_done.bind(_commit_hash))
	else:
		_git_engine.get_commit_file_diff(_commit_hash, _path, _on_diff_done.bind(_commit_hash, _path))


func _on_restore_requested(commit_hash: String, path: String) -> void:
	_git_engine.restore_file(commit_hash, path)


## Ends the running request. True if its result no longer matches the newest wanted state
## (it is then dropped and the newest state is fetched instead).
func _is_stale(commit_hash: String, path: String) -> bool:
	_busy = false
	var stale: bool = commit_hash != _commit_hash or path != _path
	if stale:
		_pump()
	return stale


func _on_files_done(exit_code: int, output: Array[String], commit_hash: String) -> void:
	if _is_stale(commit_hash, ""):
		return
	var raw: String = _first_output(output)
	if exit_code != 0:
		_log_load_failure(commit_hash, raw)
		return
	# Auto-selects the first row -> _on_file_selected -> next request.
	_panel.show_commit_files(GitDiffParser.parse_name_status(raw))


func _on_diff_done(exit_code: int, output: Array[String], commit_hash: String, path: String) -> void:
	if _is_stale(commit_hash, path):
		return
	var raw: String = _first_output(output)
	if exit_code != 0:
		_log_load_failure(commit_hash, raw)
		return
	_show_file_diff(path, raw)


func _first_output(output: Array[String]) -> String:
	return output[0] if not output.is_empty() else ""


func _log_load_failure(commit_hash: String, raw: String) -> void:
	GitotLogger.e("Could not load commit '%s'." % commit_hash)
	GitotLogger.g(raw)


func _show_file_diff(path: String, raw: String) -> void:
	if raw.length() > GitotDiffPanel.MAX_DIFF_CHARS:
		GitotLogger.w("Diff of '%s' truncated for display." % path)
		raw = raw.substr(0, GitotDiffPanel.MAX_DIFF_CHARS)
	var files: Array[Dictionary] = GitDiffParser.parse_full(raw)
	var hunks: Array[Dictionary] = []
	if not files.is_empty():
		hunks.assign(files[0]["hunks"])
	# Path comes from the list: parse_full() has no file name for deleted/binary files.
	_panel.show_diff(path, hunks)
