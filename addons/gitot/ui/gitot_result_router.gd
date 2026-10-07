## gitot_result_router.gd
## Routes finished GitEngine commands to their domain handler and updates
## the affected panel(s). Owns result-dispatch logic only.
class_name GitotResultRouter
extends RefCounted

## Emitted after HEAD moves (switch/create/pull); dock requests the changed-file listing
## (answered by files_changed).
signal head_moved

## Emitted after a successful file restore; dock refreshes EditorFileSystem/open tabs.
signal file_restored(path: String)

## Emitted with the files git changed on disk ({"reliable", "files"}): after a successful stash pop,
## and once the post-HEAD-move listing (CHANGED_FILES) arrives. Dock refreshes EditorFileSystem/open tabs.
signal files_changed(result: Dictionary)

var _git_engine: GitEngine
var _repo_state: GitotRepoState
var _status_panel: GitotStatusPanel
var _status_tree: GitotStatusTree
var _branch_panel: GitotBranchPanel
var _log_panel: GitotLogPanel
var _stash_panel: GitotStashPanel


## Determines whether a branch exists locally, remotely, or both.
static func _get_branch_scope(branch_name: String, branches: Array[GitBranchEntry]) -> String:
	var local_exists: bool = false
	var remote_exists: bool = false

	for branch: GitBranchEntry in branches:
		if branch.is_remote:
			if branch.name == "origin/" + branch_name:
				remote_exists = true
		elif branch.name == branch_name:
			local_exists = true

	var label: String = GitotUi.scope_label(local_exists, remote_exists)
	return "(%s)" % (label if not label.is_empty() else "Local")


## Keeps the two lines that matter of `git commit` output: "[main abc1234] subject" and
## "N files changed, ..." and drops the per-file "create mode ..." list (hundreds of lines on a big commit).
## Positional on purpose: the summary text is localized, the header's leading "[" is not.
static func _commit_summary(raw: String) -> String:
	var lines: PackedStringArray = raw.strip_edges().split("\n", false)
	var start: int = 0
	for i: int in lines.size():
		if lines[i].begins_with("["): # Hook output may come first.
			start = i
			break
	return "\n".join(lines.slice(start, start + 2))


## Finds the current branch's name from an already-parsed branch list.
static func _get_current_branch_from_list(branches: Array[GitBranchEntry]) -> String:
	for branch: GitBranchEntry in branches:
		if branch.is_current:
			return branch.name
	return ""


func _init(
	git_engine: GitEngine,
	repo_state: GitotRepoState,
	status_panel: GitotStatusPanel,
	status_tree: GitotStatusTree,
	branch_panel: GitotBranchPanel,
	log_panel: GitotLogPanel,
	stash_panel: GitotStashPanel,
) -> void:
	_git_engine = git_engine
	_repo_state = repo_state
	_status_panel = status_panel
	_status_tree = status_tree
	_branch_panel = branch_panel
	_log_panel = log_panel
	_stash_panel = stash_panel


## Routes a finished GitEngine command to its domain handler.
func route(
	command: GitEngine.Command,
	exit_code: int,
	output: Array[String],
	context: Dictionary,
) -> void:
	match command:
		GitEngine.Command.STAGE, GitEngine.Command.UNSTAGE:
			_handle_index_result(command, exit_code, context)
		GitEngine.Command.COMMIT, GitEngine.Command.AMEND:
			_handle_commit_result(command, exit_code, output)
		GitEngine.Command.STASH, GitEngine.Command.STASH_POP:
			_handle_stash_result(command, exit_code, output, context)
		GitEngine.Command.STASH_LIST:
			_handle_stash_list_result(exit_code, output)
		GitEngine.Command.STASH_DROP:
			_handle_stash_drop_result(exit_code, output)
		GitEngine.Command.FETCH:
			_handle_fetch_result(exit_code, output)
		GitEngine.Command.AHEAD_BEHIND:
			_handle_ahead_behind_result(exit_code, output)
		GitEngine.Command.PUSH, GitEngine.Command.PULL:
			_handle_push_pull_result(command, exit_code, output)
		GitEngine.Command.BRANCHES, GitEngine.Command.SWITCH, GitEngine.Command.CREATE_BRANCH:
			_handle_branch_result(command, exit_code, output, context)
		GitEngine.Command.DELETE_BRANCH:
			_handle_delete_branch_result(exit_code, output, context)
		GitEngine.Command.DELETE_REMOTE_BRANCH:
			_handle_delete_remote_branch_result(exit_code, output, context)
		GitEngine.Command.LOG:
			_handle_log_result(output)
		GitEngine.Command.STATUS:
			_handle_status_result(output)
		GitEngine.Command.REFLOG:
			_handle_reflog_result(exit_code, output)
		GitEngine.Command.COUNT_OBJECTS:
			_handle_repo_size_result(exit_code, output)
		GitEngine.Command.RESTORE_FILE:
			_handle_restore_result(exit_code, output, context)
		GitEngine.Command.CHANGED_FILES:
			files_changed.emit(GitEngine.to_file_list(exit_code, output))
		GitEngine.Command.REMOTE_URL:
			_handle_remote_url_result(exit_code, output)
		GitEngine.Command.SHOW_PREFIX:
			_handle_show_prefix_result(exit_code, output)


## Shared by COMMIT and AMEND;
func _handle_commit_result(
	command: GitEngine.Command,
	exit_code: int,
	output: Array[String],
) -> void:
	var is_amend: bool = command == GitEngine.Command.AMEND
	if exit_code == 0:
		if is_amend:
			GitotLogger.s("Last commit amended.")
			GitotLogger.i("If it was already pushed, Push will ask to force-push it.")
		else:
			GitotLogger.s("Commit saved locally.")
		if not output.is_empty():
			GitotLogger.g(_commit_summary(output[0]))
	else:
		_log_failure(
			"Amend failed - nothing was changed." if is_amend else "Commit failed - nothing was saved.",
			output,
			"Common causes: no file is staged (stage files first), or your git name/email is not set (git config --global user.name / user.email).",
		)


## Stage / unstage success (failures are reported by gitot.gd). The status refresh shows the result;
## this line tells a newcomer that the click did something.
## @param context: {"count": files, -1 = everything}.
func _handle_index_result(command: GitEngine.Command, exit_code: int, context: Dictionary) -> void:
	if exit_code != 0:
		return
	var verb: String = "Staged" if command == GitEngine.Command.STAGE else "Unstaged"
	var count: int = context.get("count", -1)
	GitotLogger.i("%s %s." % [verb, "all files" if count < 0 else "%d file(s)" % count])


## Hint for a failed network op: our own timeout/refusal (exit -1) beats the generic one.
## Not a status text match (git's messages are localized): only the exit code.
func _network_hint(
	exit_code: int,
	fallback: String = "Common causes: no internet, or origin is not reachable.",
) -> String:
	if exit_code == -1:
		return "No answer in time (or the command was refused). Check your connection, or raise 'Network timeout' in the Gitot settings."
	return fallback


## Git's own output (e.g. "[main abc1234] message"), logged raw: proof of what git did.
func _log_git_output(output: Array[String]) -> void:
	if not output.is_empty() and not output[0].is_empty():
		GitotLogger.g(output[0])


## Failure report for newcomers: what happened (error line), git's own reason (raw), then a
## "common causes" hint.
func _log_failure(title: String, output: Array[String], hint: String) -> void:
	GitotLogger.e(title)
	_log_git_output(output)
	GitotLogger.i(hint)


func _handle_stash_result(
	command: GitEngine.Command,
	exit_code: int,
	output: Array[String],
	context: Dictionary,
) -> void:
	if command == GitEngine.Command.STASH:
		if exit_code == 0:
			if not output.is_empty() and output[0].contains("No local changes to save"):
				GitotLogger.w("Nothing to stash.")
			else:
				GitotLogger.s("Changes stashed. (Your files are back to the last commit).")
				if not output.is_empty():
					GitotLogger.g(output[0])
		else:
			GitotLogger.e("Stash failed.")
			if not output.is_empty():
				GitotLogger.g(output[0])
		return

	# stash_pop
	if exit_code == 0:
		GitotLogger.s("Popped entry applied and removed from the Shelf.")
		files_changed.emit(context)
	else:
		GitotLogger.e("Pop failed (conflict or empty stack). Check files for conflict markers.")
		if not output.is_empty():
			GitotLogger.g(output[0])


## Git's output ("Deleted branch x (was <sha>)") is logged raw so a mistaken delete
## stays recoverable (`git branch <name> <sha>`); on refusal it carries git's reason.
func _handle_delete_branch_result(
	exit_code: int,
	output: Array[String],
	context: Dictionary,
) -> void:
	if exit_code == 0:
		GitotLogger.s("Local branch '%s' deleted." % context["branch"])
		if context["on_remote"]:
			# Deleting locally never touches GitHub: say so, and where the next step is.
			GitotLogger.w(
				"'%s' still exists on origin. Select 'origin/%s' in the list and use the remote-delete button to remove it too."
				% [context["branch"], context["branch"]]
			)
		_git_engine.list_branches()
	else:
		GitotLogger.e("Deleting local branch failed.")
	if not output.is_empty() and not output[0].is_empty():
		GitotLogger.g(output[0])


## Branch removed from origin (GitHub). On success git's own line ("- [deleted] x") is logged raw;
## on refusal it carries the server's reason. The local `origin/<name>` ref is dropped by git itself.
func _handle_delete_remote_branch_result(
	exit_code: int,
	output: Array[String],
	context: Dictionary,
) -> void:
	var branch: String = context["branch"]
	if exit_code == 0:
		GitotLogger.s("Remote Branch '%s' deleted on origin." % branch)
		_git_engine.list_branches()
	else:
		GitotLogger.e("Could not delete '%s' on origin." % branch)
		GitotLogger.i("GitHub refuses to delete the default branch and protected branches.")
	if not output.is_empty() and not output[0].is_empty():
		GitotLogger.g(output[0])


## File restored to an older commit's content.
func _handle_restore_result(exit_code: int, output: Array[String], context: Dictionary) -> void:
	var path: String = context["path"]
	if exit_code == 0:
		GitotLogger.s("Restored '%s'." % path)
		GitotLogger.i("If '%s' was open, unfocus/focus the editor window to refresh." % path)
		file_restored.emit(path)
	else:
		GitotLogger.e("Restore failed for '%s'." % path)
		if not output.is_empty():
			GitotLogger.g(output[0])


## Populates the shelf. On failure the previous list is kept (stale beats blank).
## Empty stdout (no stashes) must still repopulate, otherwise a dropped/popped
## last entry would linger. Empty output array is handled too, since I haven't
## verified whether OS.execute returns [""] or [] for empty stdout.
func _handle_stash_list_result(exit_code: int, output: Array[String]) -> void:
	if exit_code != 0:
		return
	var raw: String = output[0] if not output.is_empty() else ""
	_stash_panel.populate(GitStashParser.parse(raw))


## Git's drop output contains the dropped SHA - logged raw so a mistaken drop
## stays recoverable (`git stash store -m <msg> <sha>`).
func _handle_stash_drop_result(exit_code: int, output: Array[String]) -> void:
	if exit_code == 0:
		GitotLogger.s("Shelf entry deleted.")
	else:
		GitotLogger.e("Drop failed.")
	if not output.is_empty() and not output[0].is_empty():
		GitotLogger.g(output[0])


## Fetch: new remote branches only become visible after it, so refresh both lists.
func _handle_fetch_result(exit_code: int, output: Array[String]) -> void:
	if exit_code != 0:
		_log_failure("Fetch failed - nothing was downloaded.", output, _network_hint(exit_code))
		return
	GitotLogger.s("Fetched: origin's latest branches are downloaded.")
	_log_git_output(output)
	_git_engine.list_branches()
	_git_engine.get_ahead_behind() # keep sync status current with new remote refs


## Ahead/behind of HEAD vs its upstream: stored once in the repo state, panels redraw from it.
func _handle_ahead_behind_result(exit_code: int, output: Array[String]) -> void:
	if exit_code != 0 or output.is_empty():
		_repo_state.set_sync(false, 0, 0) # No upstream (or git failed): counts are meaningless.
		return
	var parts: PackedStringArray = output[0].strip_edges().split("\t")
	if parts.size() != 2:
		return
	var behind: int = int(parts[0])
	var ahead: int = int(parts[1])
	if _repo_state.set_sync(true, ahead, behind) and (ahead > 0 or behind > 0):
		GitotLogger.i("Current branch is %d ahead, %d behind origin." % [ahead, behind])


func _handle_push_pull_result(command: GitEngine.Command, exit_code: int, output: Array[String]) -> void:
	var is_pull: bool = command == GitEngine.Command.PULL
	if exit_code == 0:
		GitotLogger.s(
			(
				"Pulled: origin's new commits are merged into your branch."
				if is_pull
				else "Pushed: your commits are now on remote origin."
			)
		)
		_log_git_output(output)
		if is_pull:
			head_moved.emit() # pull moves HEAD like a switch - same HEAD@{1}..HEAD diff applies
		return
	var hint: String = (
		"Common causes: your uncommitted changes would be overwritten (commit or stash them first), or a merge conflict (resolve the marked files)."
		if is_pull
		else "Common causes: not signed in / no permission on GitHub, or origin has newer commits (Pull first)."
	)
	_log_failure(
		"%s failed - nothing was %s."
		% ["Pull" if is_pull else "Push", "merged" if is_pull else "uploaded"],
		output,
		_network_hint(exit_code, hint),
	)


## Branch list refresh, switch, and create - everything that changes HEAD or the dropdown.
func _handle_branch_result(
	command: GitEngine.Command,
	exit_code: int,
	output: Array[String],
	context: Dictionary,
) -> void:
	if command == GitEngine.Command.BRANCHES and exit_code == 0:
		if not output.is_empty():
			var branches: Array[GitBranchEntry] = GitBranchParser.parse(output[0])
			var branch_scopes: Dictionary[String, String] = { }

			for branch: GitBranchEntry in branches:
				if branch.is_remote:
					branch_scopes[branch.name] = "Remote"
				else:
					branch_scopes[branch.name] = _get_branch_scope(branch.name, branches)

			_branch_panel.populate(branches, branch_scopes)

			var current_branch: String = _get_current_branch_from_list(branches)
			_status_panel.update_branch(current_branch, branch_scopes.get(current_branch, ""))
		return

	# switch / create_branch
	var display_name: String = GitEngine.Command.keys()[command].capitalize()
	if exit_code == 0:
		GitotLogger.s(
			"%s successful, now on '[color=gray]%s[/color]'" % [display_name, context["branch"]]
		)
		head_moved.emit()
	else:
		GitotLogger.e("%s failed." % display_name)
		if not output.is_empty():
			GitotLogger.g(output[0])
	# No sync branch read here: the status refresh after switch/create re-lists branches and
	# updates the status line (with its scope).


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


## Raw `count-objects -vH` to the console: "size" = loose objects, "size-pack" = packed history.
func _handle_repo_size_result(exit_code: int, output: Array[String]) -> void:
	if exit_code != 0:
		GitotLogger.e("Repo size failed.")
	elif not output.is_empty():
		GitotLogger.i("Repository size (loose objects + packs):")
	if not output.is_empty() and not output[0].strip_edges().is_empty():
		GitotLogger.g(output[0].strip_edges())


## "owner/repo" in the status header, or blank when origin is missing/unparsable.
func _handle_remote_url_result(exit_code: int, output: Array[String]) -> void:
	var owner_repo: Dictionary = GitEngine.parse_owner_repo(GitEngine.remote_url_of(exit_code, output))
	_status_panel.update_repo("%s/%s" % [owner_repo["owner"], owner_repo["repo"]] if not owner_repo.is_empty() else "")


## Gitot turns git's repo-relative paths into "res://" paths, which only holds when the Godot project
## folder IS the repository root. Warns once at startup otherwise (not a repo at all: stays silent).
func _handle_show_prefix_result(exit_code: int, output: Array[String]) -> void:
	var prefix: String = output[0].strip_edges() if exit_code == 0 and not output.is_empty() else ""
	if not prefix.is_empty():
		GitotLogger.w(
			"This Godot project is the folder '%s' of its git repository, but Gitot expects it to be the repository root. File lists, open-file buttons and editor refresh may point at the wrong files." % prefix
		)


## Refreshes the status tree.
func _handle_status_result(output: Array[String]) -> void:
	if output.is_empty():
		return
	var parsed: Dictionary = GitStatusParser.parse(output[0])
	_status_tree.populate(parsed)
