## gitot_result_router.gd
## Routes finished GitEngine commands to their domain handler and updates
## the affected panel(s). Owns result-dispatch logic only.
class_name GitotResultRouter
extends RefCounted

## Emitted after a successful branch switch/create; dock notifies
## EditorFileSystem/script editor of files changed on disk.
signal branch_switched

var _git_engine: GitEngine
var _status_panel: GitotStatusPanel
var _status_tree: GitotStatusTree
var _log_panel: GitLogPanel
var _branch_panel: GitotBranchPanel
var _fetch_button: Button
var _pull_button: Button

var _has_upstream: bool = false
var _ahead_count: int = 0


## Determines whether a branch exists locally, remotely, or both.
static func _get_branch_scope(branch_name: String, branches: Array[Dictionary]) -> String:
	var local_exists: bool = false
	var remote_exists: bool = false

	for branch: Dictionary in branches:
		if branch["is_remote"]:
			if branch["name"] == "origin/" + branch_name:
				remote_exists = true
		elif branch["name"] == branch_name:
			local_exists = true

	if local_exists and remote_exists:
		return "(Local + Remote)"
	if remote_exists:
		return "(Remote)"
	return "(Local)"


## Finds the current branch's name from an already-parsed branch list.
static func _get_current_branch_from_list(branches: Array[Dictionary]) -> String:
	for branch: Dictionary in branches:
		if branch["is_current"]:
			return branch["name"]
	return ""


static func _icon(icon_name: String) -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon(icon_name, &"EditorIcons")


func _init(
	git_engine: GitEngine,
	status_panel: GitotStatusPanel,
	status_tree: GitotStatusTree,
	log_panel: GitLogPanel,
	branch_panel: GitotBranchPanel,
	fetch_button: Button,
	pull_button: Button,
) -> void:
	_git_engine = git_engine
	_status_panel = status_panel
	_status_tree = status_tree
	_log_panel = log_panel
	_branch_panel = branch_panel
	_fetch_button = fetch_button
	_pull_button = pull_button


## Read by GitotDock's amend/push guards (HEAD == upstream check).
func has_upstream() -> bool:
	return _has_upstream


func ahead_count() -> int:
	return _ahead_count


## Routes a finished GitEngine command to its domain handler.
func route(command: GitEngine.Command, exit_code: int, output: Array[String]) -> void:
	match command:
		GitEngine.Command.COMMIT, GitEngine.Command.AMEND:
			_handle_commit_result(exit_code)
		GitEngine.Command.STASH, GitEngine.Command.STASH_POP:
			_handle_stash_result(command, exit_code, output)
		GitEngine.Command.FETCH, GitEngine.Command.AHEAD_BEHIND, GitEngine.Command.PUSH, GitEngine \
				.Command \
				.PULL:
			_handle_sync_result(command, exit_code, output)
		GitEngine.Command.BRANCHES, GitEngine.Command.SWITCH, GitEngine.Command.CREATE_BRANCH:
			_handle_branch_result(command, exit_code, output)
		GitEngine.Command.LOG:
			_handle_log_result(output)
		GitEngine.Command.STATUS:
			_handle_status_result(output)
		GitEngine.Command.REFLOG:
			_handle_reflog_result(exit_code, output)


func _handle_commit_result(exit_code: int) -> void:
	if exit_code == 0:
		GitotLogger.s("Commit successful.")
	else:
		GitotLogger.x("Commit failed.")


func _handle_stash_result(
	command: GitEngine.Command,
	exit_code: int,
	output: Array[String],
) -> void:
	if command == GitEngine.Command.STASH:
		if exit_code == 0:
			if not output.is_empty() and output[0].contains("No local changes to save"):
				GitotLogger.w("Nothing to stash.")
			else:
				GitotLogger.s("Changes stashed.")
		else:
			GitotLogger.e("Stash failed.")
			if not output.is_empty():
				GitotLogger.g(output[0])
		return

	# stash_pop
	if exit_code == 0:
		GitotLogger.s("Stash popped.")
	else:
		GitotLogger.e("Pop failed (conflict or empty stack). Check files for conflict markers.")
		if not output.is_empty():
			GitotLogger.g(output[0])


## Fetch / ahead-behind / push / pull - everything touching remote sync status.
func _handle_sync_result(command: GitEngine.Command, exit_code: int, output: Array[String]) -> void:
	if command == GitEngine.Command.FETCH:
		_fetch_button.disabled = false
		_fetch_button.icon = _icon("AssetStore")
		if exit_code == 0:
			GitotLogger.s("Fetch finished.")
			_git_engine.list_branches() # new remote branches only become visible after fetch
			_git_engine.get_ahead_behind() # keep sync status current with new remote refs
		else:
			GitotLogger.e("Fetch failed.")
		if not output.is_empty() and not output[0].is_empty():
			GitotLogger.g(output[0])
		return

	if command == GitEngine.Command.AHEAD_BEHIND:
		if exit_code != 0 or output.is_empty():
			_has_upstream = false
			_ahead_count = 0
			_status_panel.update_sync(0, 0)
			return
		var parts: PackedStringArray = output[0].strip_edges().split("\t")
		if parts.size() != 2:
			return
		var behind: int = int(parts[0])
		var ahead: int = int(parts[1])
		_has_upstream = true
		_ahead_count = ahead
		if _status_panel.update_sync(ahead, behind) and (ahead > 0 or behind > 0):
			GitotLogger.i("Current branch is %d ahead, %d behind origin." % [ahead, behind])
		return

	# push / pull
	if command == GitEngine.Command.PULL:
		_pull_button.disabled = false
		_pull_button.icon = _icon("MoveDown")

	var display_name: String = GitEngine.Command.keys()[command].capitalize()
	if exit_code == 0:
		GitotLogger.s("%s finished." % display_name)
	else:
		GitotLogger.e("%s failed." % display_name)
	if not output.is_empty() and not output[0].is_empty():
		GitotLogger.g(output[0])
	if command == GitEngine.Command.PULL and exit_code == 0:
		EditorInterface.get_resource_filesystem().scan()


## Branch list refresh, switch, and create - everything that changes HEAD or the dropdown.
func _handle_branch_result(
	command: GitEngine.Command,
	exit_code: int,
	output: Array[String],
) -> void:
	if command == GitEngine.Command.BRANCHES and exit_code == 0:
		if not output.is_empty():
			var branches: Array[Dictionary] = GitBranchParser.parse(output[0])
			var branch_scopes: Dictionary[String, String] = { }

			for branch: Dictionary in branches:
				if branch["is_remote"]:
					branch_scopes[branch["name"]] = "Remote"
				else:
					branch_scopes[branch["name"]] = _get_branch_scope(branch["name"], branches)

			_branch_panel.populate(branches, branch_scopes)

			var current_branch: String = _get_current_branch_from_list(branches)
			_status_panel.update_branch(current_branch, branch_scopes.get(current_branch, ""))
		return

	# switch / create_branch
	var display_name: String = GitEngine.Command.keys()[command].capitalize()
	if exit_code == 0:
		GitotLogger.s(
			"%s successful, now on '[color=gray]%s[/color]'"
			% [display_name, _git_engine.get_last_switch_target()]
		)
		branch_switched.emit()
	else:
		GitotLogger.e("%s failed." % display_name)
		if not output.is_empty():
			GitotLogger.g(output[0])
	_git_engine.list_branches() # also refreshes the status panel's branch label
	_status_panel.update_branch(_git_engine.get_current_branch())


##  Populate the log panel.
func _handle_log_result(output: Array[String]) -> void:
	if not output.is_empty():
		_log_panel.populate(GitLogParser.parse(output[0]))


## Dumps raw reflog to Godot Output + Gitot console.
## stderr is merged into output, so a failure's git message shows here too.
func _handle_reflog_result(exit_code: int, output: Array[String]) -> void:
	if exit_code != 0:
		GitotLogger.e("Reflog failed.")
	if not output.is_empty() and not output[0].strip_edges().is_empty():
		GitotLogger.g(output[0].strip_edges()) # strip: avoids trailing blank line in the label


## Refreshes the status tree.
func _handle_status_result(output: Array[String]) -> void:
	if output.is_empty():
		return
	var parsed: Dictionary = GitStatusParser.parse(output[0])
	_status_tree.populate(parsed)
