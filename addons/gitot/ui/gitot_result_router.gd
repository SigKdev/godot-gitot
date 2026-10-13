## gitot_result_router.gd
## Routes finished GitEngine commands to their domain handler and updates
## the affected panel(s). Branch and sync (fetch/push/pull/tag) commands are handled by GitotBranchResults
## and GitotSyncResults.
class_name GitotResultRouter
extends RefCounted

## Emitted after a successful file restore; dock refreshes EditorFileSystem/open tabs.
signal file_restored(path: String)

## Emitted with the files git changed on disk ({"reliable", "files"}): after a successful stash pop,
## and once the post-HEAD-move listing (CHANGED_FILES) arrives. Dock refreshes EditorFileSystem/open tabs.
signal files_changed(result: Dictionary)

## Emitted with each parsed status {"staged", "unstaged": Array[GitStatusEntry]}, after the lists are repainted.
signal status_parsed(parsed: Dictionary)

## Emitted after `remote add origin` succeeded; the dock resumes the push that asked for the remote.
signal origin_added

var _repo_state: GitotRepoState
var _status_panel: GitotStatusPanel
var _status_tree: GitotStatusTree
var _branch_results: GitotBranchResults
var _sync_results: GitotSyncResults
var _log_panel: GitotLogPanel
var _stash_panel: GitotStashPanel


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


func _init(
	repo_state: GitotRepoState,
	status_panel: GitotStatusPanel,
	status_tree: GitotStatusTree,
	branch_results: GitotBranchResults,
	sync_results: GitotSyncResults,
	log_panel: GitotLogPanel,
	stash_panel: GitotStashPanel,
) -> void:
	_repo_state = repo_state
	_status_panel = status_panel
	_status_tree = status_tree
	_branch_results = branch_results
	_sync_results = sync_results
	_log_panel = log_panel
	_stash_panel = stash_panel


## Routes a finished GitEngine command to its domain handler.
func route(
	command: GitEngine.Command,
	exit_code: int,
	output: Array[String],
	context: Dictionary,
) -> void:
	if command in GitotBranchResults.COMMANDS:
		_branch_results.handle(command, exit_code, output, context)
		return
	if command in GitotSyncResults.COMMANDS:
		_sync_results.handle(command, exit_code, output, context)
		return
	match command:
		GitEngine.Command.STAGE, GitEngine.Command.UNSTAGE:
			_handle_index_result(command, exit_code, output, context)
		GitEngine.Command.COMMIT, GitEngine.Command.AMEND:
			_handle_commit_result(command, exit_code, output)
		GitEngine.Command.STASH, GitEngine.Command.STASH_POP:
			_handle_stash_result(command, exit_code, output, context)
		GitEngine.Command.STASH_LIST:
			_handle_stash_list_result(exit_code, output)
		GitEngine.Command.STASH_DROP:
			_handle_stash_drop_result(exit_code, output)
		GitEngine.Command.LOG:
			_handle_log_result(exit_code, output)
		GitEngine.Command.STATUS:
			_handle_status_result(exit_code, output)
		GitEngine.Command.REFLOG:
			_handle_reflog_result(exit_code, output)
		GitEngine.Command.COUNT_OBJECTS:
			_handle_repo_size_result(exit_code, output)
		GitEngine.Command.RESTORE_FILE:
			_handle_restore_result(exit_code, output, context)
		GitEngine.Command.CHANGED_FILES:
			files_changed.emit(GitPath.to_file_list(exit_code, output))
		GitEngine.Command.REMOTE_URL:
			_handle_remote_url_result(exit_code, output)
		GitEngine.Command.REMOTE_ADD:
			_handle_remote_add_result(exit_code, output, context)
		GitEngine.Command.SHOW_PREFIX:
			_handle_show_prefix_result(exit_code, output)


## Shared by COMMIT and AMEND.
func _handle_commit_result(
	command: GitEngine.Command,
	exit_code: int,
	output: Array[String],
) -> void:
	var is_amend: bool = command == GitEngine.Command.AMEND
	if exit_code == 0:
		if is_amend:
			GitotLogger.s("Last commit amended on branch '%s'." % _branch())
			GitotLogger.h("If it was already pushed, Push will ask to force-push it.")
		else:
			GitotLogger.s("Commit saved locally on branch '%s'." % _branch())
		if not output.is_empty():
			GitotLogger.g(_commit_summary(output[0]))
	else:
		GitotMessages.log_failure(
			(
				"Amend failed on branch '%s' - nothing was changed."
				if is_amend
				else "Commit failed on branch '%s' - nothing was saved."
			)
			% _branch(),
			output,
			"Common fail causes: no file is staged (stage files first), or your git name/email is not set (git config --global user.name / user.email).",
		)


## Stage / unstage result. On success the status refresh shows the change; the log line confirms that the
## click did something.
## @param context: {"count": files, -1 = everything}.
func _handle_index_result(
	command: GitEngine.Command,
	exit_code: int,
	output: Array[String],
	context: Dictionary,
) -> void:
	var is_stage: bool = command == GitEngine.Command.STAGE
	if exit_code != 0:
		# git add / reset aborts the WHOLE batch: never fail silently.
		GitotMessages.log_failure(
			"Staging failed - no file was staged." if is_stage else "Unstaging failed - no file was unstaged.",
			output,
			"Common fail causes: a listed file changed or vanished since the list was drawn, or another Git tool holds .git/index.lock.",
		)
		return
	var verb: String = "Staged" if is_stage else "Unstaged"
	var count: int = context.get("count", -1)
	GitotLogger.i("%s %s." % [verb, "all files" if count < 0 else "%d file(s)" % count])


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
				GitotLogger.s(
					"Changes stashed from branch '%s'. Your files are back to the last commit."
					% _branch()
				)
				if not output.is_empty():
					GitotLogger.g(output[0])
		else:
			GitotMessages.log_failure(
				"Stash failed on branch '%s' - nothing was stashed." % _branch(),
				output,
				"Common fail causes: the repository has no commit yet (a stash needs one), or files have unresolved merge conflicts.",
			)
		return

	# stash_pop
	if exit_code == 0:
		GitotLogger.s("Stash popped & applied to branch '%s'. Removed from the Shelf." % _branch())
		files_changed.emit(context)
	else:
		GitotMessages.log_failure(
			"Pop failed - the entry was not removed from the Shelf.",
			output,
			"Common fail causes: the entry conflicts with your current changes (resolve the conflict markers written into the files), or uncommitted changes would be overwritten (commit or stash them first).",
		)


## Result of restoring a file to an older commit's content.
func _handle_restore_result(exit_code: int, output: Array[String], context: Dictionary) -> void:
	var path: String = context["path"]
	if exit_code != 0:
		GitotMessages.log_failure(
			"Restore of '%s' failed - the file was not changed." % path,
			output,
			"Common cause: the file does not exist in that commit.",
		)
		return
	GitotLogger.s("Restored '%s'." % path)
	GitotLogger.h("If '%s' was open, unfocus/focus the editor window to refresh." % path)
	file_restored.emit(path)


## Populates the shelf. On failure the previous list is kept.
## Empty stdout (no stashes) must still repopulate, otherwise a dropped/popped last entry would
## linger. An empty output array is treated the same way.
func _handle_stash_list_result(exit_code: int, output: Array[String]) -> void:
	if exit_code != 0:
		return
	var raw: String = output[0] if not output.is_empty() else ""
	_stash_panel.populate(GitStashParser.parse(raw))


## Git's drop output contains the dropped SHA - logged raw so a mistaken drop
## stays recoverable (`git stash store -m <msg> <sha>`).
func _handle_stash_drop_result(exit_code: int, output: Array[String]) -> void:
	if exit_code != 0:
		GitotMessages.log_failure(
			"Drop failed - the stash was not removed.",
			output,
			"Common cause: the entry no longer exists (the stash list changed outside Gitot).",
		)
		return
	GitotLogger.s("Stash deleted.")
	GitotMessages.log_git_output(output)


## Branch name for log messages (see GitotRepoState.branch_label()).
func _branch() -> String:
	return _repo_state.branch_label()




## Populates the history panel.
## A failed log keeps the previous list and stays silent: an unborn branch (fresh `git init`) fails
## on every refresh, and a failing STATUS already reports the shared causes.
func _handle_log_result(exit_code: int, output: Array[String]) -> void:
	if exit_code == 0 and not output.is_empty():
		_log_panel.populate(GitLogParser.parse(output[0]))


## Logs the raw reflog (Godot Output + Gitot console).
## stderr is merged into output, so a failure's git message shows here too.
func _handle_reflog_result(exit_code: int, output: Array[String]) -> void:
	if exit_code != 0:
		GitotMessages.log_failure(
			"Reflog failed.",
			output,
			"Common fail causes: the project folder is not a git repository, or it has no commit yet.",
		)
		return
	if not output.is_empty() and not output[0].strip_edges().is_empty():
		GitotLogger.g(output[0].strip_edges()) # strip: avoids trailing blank line in the label


## Raw `count-objects -vH` to the console: "size" = loose objects, "size-pack" = packed history.
func _handle_repo_size_result(exit_code: int, output: Array[String]) -> void:
	if exit_code != 0:
		GitotMessages.log_failure(
			"Repo size failed.",
			output,
			"Common cause: the project folder is not a git repository.",
		)
		return
	if output.is_empty():
		return
	GitotLogger.i("Repository size (loose objects + packs):")
	if not output[0].strip_edges().is_empty():
		GitotLogger.g(output[0].strip_edges())


## Origin's URL answered: "owner/repo" in the status header, or blank when origin is missing/unparsable.
func _handle_remote_url_result(exit_code: int, output: Array[String]) -> void:
	_apply_origin_url(GitRemote.url_of(exit_code, output))


## Result of `remote add origin <url>`. On success origin is stored right away (no extra git call) and
## the dock is told to resume the push.
## @param context: {"url": the URL that was added}.
func _handle_remote_add_result(exit_code: int, output: Array[String], context: Dictionary) -> void:
	if exit_code != 0:
		GitotMessages.log_failure(
			"Could not add the remote 'origin' - the push was not started.",
			output,
			"Common fail causes: the URL is not https://, ssh:// or git@host:path (https URLs must not contain user:token@), or an 'origin' remote already exists.",
		)
		return
	_apply_origin_url(context["url"])
	GitotLogger.s("Remote 'origin' added: %s" % context["url"])
	origin_added.emit()


## Single place that stores origin in the repo state ("" = no origin) and repaints the status header.
func _apply_origin_url(url: String) -> void:
	var owner_repo: Dictionary = GitRemote.parse_owner_repo(url)
	_repo_state.has_origin = not url.is_empty()
	_repo_state.repo = "%s/%s" % [owner_repo["owner"], owner_repo["repo"]] if not owner_repo.is_empty() else ""
	_repo_state.repo_url = GitRemote.web_url(url) # Before update_repo(): the panel reads it on render.
	_status_panel.update_repo(_repo_state.repo)


## Gitot turns git's repo-relative paths into "res://" paths, which only holds when the Godot project
## folder IS the repository root. Warns once at startup otherwise (not a repo at all: stays silent).
func _handle_show_prefix_result(exit_code: int, output: Array[String]) -> void:
	var prefix: String = output[0].strip_edges() if exit_code == 0 and not output.is_empty() else ""
	if not prefix.is_empty():
		GitotLogger.w(
			"This Godot project is the folder '%s' of its git repository, but Gitot expects it to be the repository root. File lists, open-file buttons and editor refresh may point at the wrong files."
			% prefix
		)


## Repaints the Staged/Unstaged lists, then announces the parsed status (status_parsed).
## A failed status must not parse as a clean tree (it would hide every change): report it, keep the lists.
func _handle_status_result(exit_code: int, output: Array[String]) -> void:
	if exit_code != 0:
		GitotMessages.log_failure(
			"Could not read the working tree status.",
			output,
			"Common fail causes: another Git tool holds .git/index.lock, or Git refuses the folder ('dubious ownership').",
		)
		return
	if output.is_empty():
		return
	var parsed: Dictionary = GitStatusParser.parse(output[0])
	_status_tree.populate(parsed)
	status_parsed.emit(parsed)
